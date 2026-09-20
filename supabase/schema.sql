-- =============================================================================
-- InstaPharm — Script SQL complet (Supabase / PostgreSQL)
-- Exécuter dans : Supabase Dashboard → SQL Editor → New query → Run
-- =============================================================================

-- Extensions utiles
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- 1. PROFILS (lié à auth.users)
-- -----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  phone text,
  avatar_url text,
  role text not null default 'patient'
    check (role in ('patient', 'pharmacist', 'courier', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 2. PHARMACIES (partenaires plateforme + cache OSM)
-- -----------------------------------------------------------------------------
create table if not exists public.pharmacies (
  id text primary key,
  name text not null,
  address text,
  city text,
  postal_code text,
  latitude double precision,
  longitude double precision,
  phone text,
  email text,
  website text,
  is_duty boolean default false,
  is_open boolean default true,
  is_verified boolean default false,
  is_platform boolean not null default false,
  owner_user_id uuid,
  registered_by uuid,
  services text[] default '{}',
  rating numeric(3,2),
  review_count int default 0,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 3. MÉDICAMENTS
-- -----------------------------------------------------------------------------
create table if not exists public.medicines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  brand text,
  dosage text,
  form text,
  category text,
  description text,
  requires_prescription boolean default false,
  price_xaf int default 0,
  created_at timestamptz not null default now()
);

create index if not exists medicines_name_idx
  on public.medicines
  using gin (to_tsvector('french', coalesce(name,'') || ' ' || coalesce(brand,'')));

-- -----------------------------------------------------------------------------
-- 4. STOCK (par pharmacie)
-- -----------------------------------------------------------------------------
create table if not exists public.inventory (
  id uuid primary key default gen_random_uuid(),
  pharmacy_id text not null references public.pharmacies(id) on delete cascade,
  medicine_id uuid not null references public.medicines(id) on delete cascade,
  status text not null default 'available'
    check (status in ('available', 'low_stock', 'out_of_stock', 'unknown')),
  quantity int,
  unit_price_xaf int,
  updated_at timestamptz not null default now(),
  unique (pharmacy_id, medicine_id)
);

-- -----------------------------------------------------------------------------
-- 5. LIVREURS
-- -----------------------------------------------------------------------------
create table if not exists public.couriers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id),
  full_name text not null,
  phone text not null,
  is_available boolean default true,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 6. COMMANDES
-- -----------------------------------------------------------------------------
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  public_code text unique not null,
  user_id uuid not null references public.profiles(id),
  pharmacy_id text not null references public.pharmacies(id),
  pharmacy_name text not null,
  fulfillment text not null check (fulfillment in ('pickup', 'delivery')),
  payment_method text not null check (payment_method in ('cash', 'mtn_momo', 'orange_money')),
  status text not null default 'pending'
    check (status in (
      'pending', 'confirmed', 'preparing',
      'out_for_delivery', 'ready_for_pickup',
      'delivered', 'cancelled'
    )),
  subtotal_xaf int not null default 0,
  delivery_fee_xaf int not null default 0,
  notes text,
  has_prescription boolean default false,
  recipient_name text,
  recipient_phone text,
  delivery_city text,
  delivery_neighborhood text,
  delivery_address text,
  dest_lat double precision,
  dest_lng double precision,
  from_live_gps boolean default false,
  route_geometry jsonb default '[]',
  route_distance_m double precision,
  route_duration_s int,
  courier_id uuid references public.couriers(id),
  courier_lat double precision,
  courier_lng double precision,
  courier_progress numeric(5,4) default 0,
  eta_minutes int,
  departed_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_user_idx on public.orders(user_id);
create index if not exists orders_status_idx on public.orders(status);
create index if not exists orders_pharmacy_idx on public.orders(pharmacy_id);
create index if not exists orders_courier_idx on public.orders(courier_id);

-- -----------------------------------------------------------------------------
-- 7. LIGNES DE COMMANDE
-- -----------------------------------------------------------------------------
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  medicine_id text,
  medicine_name text not null,
  brand text,
  dosage text,
  quantity int not null default 1,
  unit_price_xaf int not null default 0,
  requires_prescription boolean default false
);

create index if not exists order_items_order_idx on public.order_items(order_id);

-- -----------------------------------------------------------------------------
-- 8. NOTES (livraison + livreur + pharmacie)
-- -----------------------------------------------------------------------------
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  delivery_rating int not null check (delivery_rating between 1 and 5),
  courier_rating int check (courier_rating between 1 and 5),
  pharmacy_rating int check (pharmacy_rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (order_id, user_id)
);

-- -----------------------------------------------------------------------------
-- 9. FAVORIS
-- -----------------------------------------------------------------------------
create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  pharmacy_id text not null references public.pharmacies(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, pharmacy_id)
);

-- -----------------------------------------------------------------------------
-- 10. TRIGGERS — profil auto à l'inscription
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'role', 'patient')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- updated_at sur commandes
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists orders_updated_at on public.orders;
create trigger orders_updated_at
  before update on public.orders
  for each row execute procedure public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 11. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.pharmacies enable row level security;
alter table public.medicines enable row level security;
alter table public.inventory enable row level security;
alter table public.couriers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.ratings enable row level security;
alter table public.favorites enable row level security;

-- Profiles
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- Pharmacies
drop policy if exists "pharmacies_read_all" on public.pharmacies;
drop policy if exists "pharmacies_upsert_auth" on public.pharmacies;
drop policy if exists "pharmacies_update_auth" on public.pharmacies;
create policy "pharmacies_read_all" on public.pharmacies
  for select using (true);
create policy "pharmacies_upsert_auth" on public.pharmacies
  for insert with check (auth.role() = 'authenticated');
create policy "pharmacies_update_auth" on public.pharmacies
  for update using (auth.role() = 'authenticated');

-- Medicines / inventory / couriers (lecture publique)
drop policy if exists "medicines_read_all" on public.medicines;
drop policy if exists "inventory_read_all" on public.inventory;
drop policy if exists "couriers_read_all" on public.couriers;
create policy "medicines_read_all" on public.medicines for select using (true);
create policy "inventory_read_all" on public.inventory for select using (true);
create policy "couriers_read_all" on public.couriers for select using (true);

-- Orders
drop policy if exists "orders_select_own" on public.orders;
drop policy if exists "orders_insert_own" on public.orders;
drop policy if exists "orders_update_own" on public.orders;
create policy "orders_select_own" on public.orders
  for select using (auth.uid() = user_id);
create policy "orders_insert_own" on public.orders
  for insert with check (auth.uid() = user_id);
create policy "orders_update_own" on public.orders
  for update using (auth.uid() = user_id);

-- Order items
drop policy if exists "order_items_select" on public.order_items;
drop policy if exists "order_items_insert" on public.order_items;
create policy "order_items_select" on public.order_items for select using (
  exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
);
create policy "order_items_insert" on public.order_items for insert with check (
  exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
);

-- Ratings
drop policy if exists "ratings_select_own" on public.ratings;
drop policy if exists "ratings_insert_own" on public.ratings;
drop policy if exists "ratings_update_own" on public.ratings;
create policy "ratings_select_own" on public.ratings
  for select using (auth.uid() = user_id);
create policy "ratings_insert_own" on public.ratings
  for insert with check (auth.uid() = user_id);
create policy "ratings_update_own" on public.ratings
  for update using (auth.uid() = user_id);

-- Favorites
drop policy if exists "favorites_all_own" on public.favorites;
create policy "favorites_all_own" on public.favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- -----------------------------------------------------------------------------
-- 12. REALTIME (suivi livraison)
-- -----------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception
  when duplicate_object then null;
end $$;

-- -----------------------------------------------------------------------------
-- 13. DONNÉES INITIALES — médicaments Cameroun
-- -----------------------------------------------------------------------------
insert into public.medicines (name, brand, dosage, form, category, requires_prescription, price_xaf, description)
select * from (values
  ('Paracétamol', 'Paracetamol Denk', '500 mg', 'Comprimé', 'Antalgique', false, 1500, 'Douleur et fièvre'),
  ('Paracétamol', 'Doliprane', '1 g', 'Comprimé', 'Antalgique', false, 2500, null::text),
  ('Ibuprofène', 'Ibuprofen CIPLA', '400 mg', 'Comprimé', 'AINS', false, 2000, null),
  ('Amoxicilline', 'Amoxil', '500 mg', 'Gélule', 'Antibiotique', true, 3500, null),
  ('Artémether / Luméfantrine', 'Coartem', '20/120 mg', 'Comprimé', 'Antipaludéen', true, 4500, 'Paludisme non compliqué'),
  ('Sels de réhydratation orale', 'ORS UNICEF', 'Sachet', 'Poudre', 'Réhydratation', false, 500, null),
  ('Artésunate', 'Artesun', '60 mg', 'Injectable', 'Antipaludéen', true, 8000, null),
  ('Métronidazole', 'Flagyl', '250 mg', 'Comprimé', 'Antiparasitaire', true, 1800, null),
  ('Vitamine C', 'Cevita', '500 mg', 'Comprimé', 'Vitamine', false, 1200, null),
  ('Zinc', 'Zincatil', '20 mg', 'Comprimé', 'Complément', false, 1000, null),
  ('Salbutamol', 'Ventoline', '100 µg', 'Aérosol', 'Respiratoire', true, 5500, null),
  ('Moustiquaire imprégnée', 'Permanet', '1 unité', 'Accessoire', 'Prévention', false, 3500, null)
) as v(name, brand, dosage, form, category, requires_prescription, price_xaf, description)
where not exists (
  select 1 from public.medicines m
  where m.name = v.name and coalesce(m.brand,'') = coalesce(v.brand,'')
    and coalesce(m.dosage,'') = coalesce(v.dosage,'')
);

-- Livreur initial
insert into public.couriers (full_name, phone, is_available)
select 'Jean Mbarga', '+237699123456', true
where not exists (
  select 1 from public.couriers where phone = '+237699123456'
);

-- =============================================================================
-- 14. HISTORIQUE + NOTIFICATIONS
-- =============================================================================
alter table public.profiles
  add column if not exists notifications_enabled boolean not null default true;

create table if not exists public.search_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  query text not null,
  created_at timestamptz not null default now()
);

create index if not exists search_history_user_idx
  on public.search_history(user_id, created_at desc);

create table if not exists public.pharmacy_views (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  pharmacy_id text not null,
  pharmacy_name text not null,
  address text,
  created_at timestamptz not null default now()
);

create index if not exists pharmacy_views_user_idx
  on public.pharmacy_views(user_id, created_at desc);

alter table public.search_history enable row level security;
alter table public.pharmacy_views enable row level security;

drop policy if exists "search_history_own" on public.search_history;
create policy "search_history_own" on public.search_history
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "pharmacy_views_own" on public.pharmacy_views;
create policy "pharmacy_views_own" on public.pharmacy_views
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Staff : pharmaciens / livreurs peuvent lire et mettre à jour les commandes
drop policy if exists "orders_staff_select" on public.orders;
create policy "orders_staff_select" on public.orders for select using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('pharmacist', 'courier', 'admin')
  )
);

drop policy if exists "orders_staff_update" on public.orders;
create policy "orders_staff_update" on public.orders for update using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('pharmacist', 'courier', 'admin')
  )
);

drop policy if exists "couriers_upsert_own" on public.couriers;
create policy "couriers_upsert_own" on public.couriers
  for all using (
    user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role in ('courier', 'admin')
    )
  )
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role in ('courier', 'admin')
    )
  );

-- =============================================================================
-- Fin du script de base.
-- Exécuter ensuite :
--   1) supabase/platform_pharmacies.sql
--   2) supabase/stock_system.sql
--   3) supabase/admin_system.sql
-- =============================================================================
