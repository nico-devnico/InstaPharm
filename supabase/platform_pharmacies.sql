-- =============================================================================
-- InstaPharm — Pharmacies plateforme (admin) + inventaires
-- À exécuter après schema.sql dans Supabase → SQL Editor
-- =============================================================================

-- Colonnes plateforme
alter table public.pharmacies
  add column if not exists is_platform boolean not null default false;

alter table public.pharmacies
  add column if not exists owner_user_id uuid references public.profiles(id);

alter table public.pharmacies
  add column if not exists registered_by uuid references public.profiles(id);

create index if not exists pharmacies_platform_idx
  on public.pharmacies (is_platform)
  where is_platform = true;

-- Helper rôle
create or replace function public.is_staff_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

create or replace function public.is_pharmacist()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('pharmacist', 'admin')
  );
$$;

-- Policies admin / pharmacien sur pharmacies
drop policy if exists "pharmacies_admin_insert" on public.pharmacies;
create policy "pharmacies_admin_insert" on public.pharmacies
  for insert with check (public.is_staff_admin() or auth.role() = 'authenticated');

drop policy if exists "pharmacies_admin_update" on public.pharmacies;
create policy "pharmacies_admin_update" on public.pharmacies
  for update using (
    public.is_staff_admin()
    or owner_user_id = auth.uid()
    or auth.role() = 'authenticated'
  );

drop policy if exists "pharmacies_admin_delete" on public.pharmacies;
create policy "pharmacies_admin_delete" on public.pharmacies
  for delete using (public.is_staff_admin());

-- Inventaire : écriture admin + pharmacien propriétaire
drop policy if exists "inventory_write_staff" on public.inventory;
create policy "inventory_write_staff" on public.inventory
  for all using (
    public.is_staff_admin()
    or exists (
      select 1 from public.pharmacies ph
      where ph.id = pharmacy_id
        and ph.is_platform = true
        and (ph.owner_user_id = auth.uid() or public.is_pharmacist())
    )
  )
  with check (
    public.is_staff_admin()
    or exists (
      select 1 from public.pharmacies ph
      where ph.id = pharmacy_id
        and ph.is_platform = true
        and (ph.owner_user_id = auth.uid() or public.is_pharmacist())
    )
  );

-- Médicaments : admin peut ajouter au catalogue
drop policy if exists "medicines_admin_write" on public.medicines;
create policy "medicines_admin_write" on public.medicines
  for all using (public.is_staff_admin())
  with check (public.is_staff_admin());

-- Pharmacies plateforme de démo (Douala / Yaoundé)
insert into public.pharmacies (
  id, name, address, city, latitude, longitude, phone,
  is_duty, is_open, is_verified, is_platform, services
)
select * from (values
  (
    'plat-douala-bonanjo',
    'Pharmacie du Port',
    'Boulevard de la République, Bonanjo',
    'Douala',
    4.0503::double precision,
    9.7000::double precision,
    '+237233421100',
    false, true, true, true,
    array['Livraison', 'Garde']::text[]
  ),
  (
    'plat-douala-akwa',
    'Pharmacie Akwa Centre',
    'Rue Joss, Akwa',
    'Douala',
    4.0511::double precision,
    9.7085::double precision,
    '+237233422200',
    false, true, true, true,
    array['Livraison']::text[]
  ),
  (
    'plat-yaounde-bastos',
    'Pharmacie Bastos',
    'Rue 1.770, Bastos',
    'Yaoundé',
    3.8900::double precision,
    11.5021::double precision,
    '+237222201100',
    true, true, true, true,
    array['Livraison', '24h/24']::text[]
  ),
  (
    'plat-yaounde-mvog',
    'Pharmacie Mvog-Ada',
    'Carrefour Mvog-Ada',
    'Yaoundé',
    3.8667::double precision,
    11.5167::double precision,
    '+237222202200',
    false, true, true, true,
    array['Livraison']::text[]
  )
) as v(id, name, address, city, latitude, longitude, phone, is_duty, is_open, is_verified, is_platform, services)
where not exists (
  select 1 from public.pharmacies p where p.id = v.id
);

-- Remplir l’inventaire de chaque pharmacie plateforme pour les médicaments seed
insert into public.inventory (pharmacy_id, medicine_id, status, quantity, unit_price_xaf)
select
  ph.id,
  m.id,
  case
    when (hashtext(ph.id || m.id::text) % 11) = 0 then 'out_of_stock'
    when (hashtext(ph.id || m.id::text) % 7) = 0 then 'low_stock'
    else 'available'
  end,
  case
    when (hashtext(ph.id || m.id::text) % 11) = 0 then 0
    when (hashtext(ph.id || m.id::text) % 7) = 0 then 5 + (abs(hashtext(m.id::text)) % 8)
    else 15 + (abs(hashtext(ph.id || m.name)) % 40)
  end,
  coalesce(m.price_xaf, 1000) + (abs(hashtext(ph.id)) % 500)
from public.pharmacies ph
cross join public.medicines m
where ph.is_platform = true
  and not exists (
    select 1 from public.inventory i
    where i.pharmacy_id = ph.id and i.medicine_id = m.id
  );
