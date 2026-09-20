-- =============================================================================
-- InstaPharm — Administration plateforme
-- Exécuter après schema.sql, platform_pharmacies.sql, stock_system.sql
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "postgis";

-- -----------------------------------------------------------------------------
-- 1. PROFILS — activation + bootstrap admin
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_active boolean not null default true;

alter table public.profiles
  add column if not exists disabled_reason text;

alter table public.profiles
  add column if not exists last_seen_at timestamptz;

-- -----------------------------------------------------------------------------
-- Audit logs + signalements + settings (créés tôt pour les fonctions)
-- -----------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  resource_type text not null,
  resource_id text,
  meta jsonb default '{}'::jsonb,
  ip text,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);
create index if not exists audit_logs_actor_idx on public.audit_logs(actor_id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete set null,
  target_type text not null
    check (target_type in ('user', 'pharmacy', 'order', 'delivery', 'other')),
  target_id text,
  pharmacy_id text references public.pharmacies(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  reason text not null,
  description text,
  status text not null default 'OPEN'
    check (status in ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  admin_notes text,
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reports_status_idx on public.reports(status, created_at desc);
create index if not exists reports_reporter_idx on public.reports(reporter_id);

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  label text,
  category text not null default 'general',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

-- Empêche un utilisateur de s'auto-promouvoir admin via update direct
create or replace function public.prevent_self_admin_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.role = 'admin'
     and old.role is distinct from 'admin'
     and auth.uid() = new.id
     and not public.is_staff_admin() then
    -- Autoriser uniquement le bootstrap (aucun admin existant)
    if exists (select 1 from public.profiles where role = 'admin' and id <> new.id) then
      raise exception 'FORBIDDEN_ADMIN_ESCALATION';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_prevent_self_admin on public.profiles;
create trigger profiles_prevent_self_admin
  before update on public.profiles
  for each row execute procedure public.prevent_self_admin_escalation();

-- Bootstrap : l'utilisateur authentifié devient admin s'il n'y a aucun admin
create or replace function public.claim_bootstrap_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  admin_count int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  end if;

  select count(*) into admin_count from public.profiles where role = 'admin';

  if admin_count > 0 then
    -- Si l'appelant est déjà admin, OK
    if exists (select 1 from public.profiles where id = uid and role = 'admin') then
      return jsonb_build_object('ok', true, 'already', true);
    end if;
    return jsonb_build_object('ok', false, 'error', 'ADMIN_EXISTS');
  end if;

  update public.profiles
  set role = 'admin', updated_at = now()
  where id = uid;

  insert into public.audit_logs (actor_id, action, resource_type, resource_id, meta)
  values (uid, 'BOOTSTRAP_ADMIN', 'profile', uid::text, jsonb_build_object('note', 'Premier administrateur'));

  return jsonb_build_object('ok', true, 'promoted', true, 'user_id', uid);
end;
$$;

-- Forcer un utilisateur en admin (service_role / déjà admin via RPC dédiée)
create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff_admin() then
    return jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
  end if;
  if p_role not in ('patient', 'pharmacist', 'courier', 'admin') then
    return jsonb_build_object('ok', false, 'error', 'INVALID_ROLE');
  end if;

  update public.profiles
  set role = p_role, updated_at = now()
  where id = p_user_id;

  insert into public.audit_logs (actor_id, action, resource_type, resource_id, meta)
  values (
    auth.uid(), 'SET_ROLE', 'profile', p_user_id::text,
    jsonb_build_object('role', p_role)
  );

  return jsonb_build_object('ok', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. PHARMACIES — statut plateforme + PostGIS
-- -----------------------------------------------------------------------------
alter table public.pharmacies
  add column if not exists platform_status text not null default 'VERIFIED'
    check (platform_status in ('PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED'));

alter table public.pharmacies
  add column if not exists is_active boolean not null default true;

alter table public.pharmacies
  add column if not exists rejection_reason text;

alter table public.pharmacies
  add column if not exists verified_at timestamptz;

alter table public.pharmacies
  add column if not exists verified_by uuid references public.profiles(id);

alter table public.pharmacies
  add column if not exists opening_hours jsonb default '{}'::jsonb;

-- Colonne géographique PostGIS
alter table public.pharmacies
  add column if not exists location geography(POINT, 4326);

create index if not exists pharmacies_location_gix
  on public.pharmacies using gist (location);

create or replace function public.sync_pharmacy_location()
returns trigger
language plpgsql
as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.location := ST_SetSRID(
      ST_MakePoint(new.longitude, new.latitude),
      4326
    )::geography;
  end if;
  return new;
end;
$$;

drop trigger if exists pharmacies_sync_location on public.pharmacies;
create trigger pharmacies_sync_location
  before insert or update of latitude, longitude on public.pharmacies
  for each row execute procedure public.sync_pharmacy_location();

-- Backfill
update public.pharmacies
set location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
where latitude is not null
  and longitude is not null
  and location is null;

-- Pharmacies plateforme existantes → VERIFIED
update public.pharmacies
set platform_status = 'VERIFIED',
    is_verified = true,
    verified_at = coalesce(verified_at, now())
where is_platform = true
  and platform_status = 'VERIFIED';

-- -----------------------------------------------------------------------------
-- 3. MÉDICAMENTS — désactivation référentiel
-- -----------------------------------------------------------------------------
alter table public.medicines
  add column if not exists is_active boolean not null default true;

alter table public.medicines
  add column if not exists updated_at timestamptz not null default now();

-- -----------------------------------------------------------------------------
-- 4. LIVREURS — activation
-- -----------------------------------------------------------------------------
alter table public.couriers
  add column if not exists is_active boolean not null default true;

alter table public.couriers
  add column if not exists created_at timestamptz not null default now();

-- -----------------------------------------------------------------------------
-- 5. SIGNALEMENTS / AUDIT / SETTINGS — déjà créés en tête de script
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, label, category) values
  ('app.info', '{"name":"InstaPharm","support_email":"support@instapharm.cm","locale":"fr_CM"}'::jsonb, 'Informations application', 'general'),
  ('delivery.fees', '{"base_xaf":1500,"express_xaf":2500,"free_above_xaf":25000}'::jsonb, 'Frais de livraison', 'delivery'),
  ('delivery.radius_km', '{"default":8,"max":25}'::jsonb, 'Rayon de livraison', 'delivery'),
  ('notifications.defaults', '{"order_updates":true,"promo":false,"stock_alerts":true}'::jsonb, 'Notifications', 'notifications'),
  ('search.defaults', '{"radius_km":10,"max_results":40}'::jsonb, 'Recherche', 'search'),
  ('pharmacy.rules', '{"require_verification":true,"low_stock_threshold":5,"stale_hours":24}'::jsonb, 'Règles pharmacies', 'pharmacies'),
  ('security.session', '{"idle_minutes":60,"require_email":true}'::jsonb, 'Sécurité session', 'security'),
  ('ops.hours', '{"support_start":"08:00","support_end":"20:00","timezone":"Africa/Douala"}'::jsonb, 'Horaires opérationnels', 'ops')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- 8. DASHBOARD STATS (fonction admin)
-- -----------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_staff_admin() then
    return jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
  end if;

  select jsonb_build_object(
    'ok', true,
    'users_total', (select count(*) from public.profiles),
    'users_active', (select count(*) from public.profiles where is_active),
    'users_by_role', (
      select coalesce(jsonb_object_agg(role, c), '{}'::jsonb)
      from (select role, count(*)::int as c from public.profiles group by role) t
    ),
    'pharmacies_total', (select count(*) from public.pharmacies where is_platform),
    'pharmacies_verified', (
      select count(*) from public.pharmacies
      where is_platform and platform_status = 'VERIFIED' and is_active
    ),
    'pharmacies_pending', (
      select count(*) from public.pharmacies
      where is_platform and platform_status = 'PENDING'
    ),
    'pharmacies_rejected', (
      select count(*) from public.pharmacies
      where is_platform and platform_status = 'REJECTED'
    ),
    'pharmacies_suspended', (
      select count(*) from public.pharmacies
      where is_platform and platform_status = 'SUSPENDED'
    ),
    'medicines_total', (select count(*) from public.medicines),
    'medicines_active', (select count(*) from public.medicines where is_active),
    'orders_total', (select count(*) from public.orders),
    'orders_active', (
      select count(*) from public.orders
      where status not in ('delivered', 'cancelled')
    ),
    'orders_delivered', (
      select count(*) from public.orders where status = 'delivered'
    ),
    'orders_cancelled', (
      select count(*) from public.orders where status = 'cancelled'
    ),
    'deliveries_in_progress', (
      select count(*) from public.orders
      where fulfillment = 'delivery' and status = 'out_for_delivery'
    ),
    'couriers_total', (select count(*) from public.couriers),
    'couriers_available', (
      select count(*) from public.couriers where is_available and is_active
    ),
    'reports_open', (
      select count(*) from public.reports where status in ('OPEN', 'IN_PROGRESS')
    ),
    'orders_by_status', (
      select coalesce(jsonb_object_agg(status, c), '{}'::jsonb)
      from (select status, count(*)::int as c from public.orders group by status) t
    ),
    'generated_at', now()
  ) into result;

  return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. RLS
-- -----------------------------------------------------------------------------
alter table public.reports enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;

drop policy if exists "reports_insert_auth" on public.reports;
create policy "reports_insert_auth" on public.reports
  for insert with check (auth.uid() = reporter_id);

drop policy if exists "reports_select_own_or_admin" on public.reports;
create policy "reports_select_own_or_admin" on public.reports
  for select using (
    reporter_id = auth.uid() or public.is_staff_admin()
  );

drop policy if exists "reports_admin_update" on public.reports;
create policy "reports_admin_update" on public.reports
  for update using (public.is_staff_admin());

drop policy if exists "audit_admin_select" on public.audit_logs;
create policy "audit_admin_select" on public.audit_logs
  for select using (public.is_staff_admin());

drop policy if exists "audit_admin_insert" on public.audit_logs;
create policy "audit_admin_insert" on public.audit_logs
  for insert with check (public.is_staff_admin() or auth.uid() is not null);

drop policy if exists "settings_read_auth" on public.app_settings;
create policy "settings_read_auth" on public.app_settings
  for select using (auth.role() = 'authenticated');

drop policy if exists "settings_admin_write" on public.app_settings;
create policy "settings_admin_write" on public.app_settings
  for all using (public.is_staff_admin())
  with check (public.is_staff_admin());

-- Admin peut lire tous les profils
drop policy if exists "profiles_admin_select" on public.profiles;
create policy "profiles_admin_select" on public.profiles
  for select using (auth.uid() = id or public.is_staff_admin());

drop policy if exists "profiles_admin_update" on public.profiles;
create policy "profiles_admin_update" on public.profiles
  for update using (auth.uid() = id or public.is_staff_admin());

grant execute on function public.claim_bootstrap_admin() to authenticated;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;
grant execute on function public.admin_dashboard_stats() to authenticated;

-- -----------------------------------------------------------------------------
-- 10. PROMOUVOIR L'UTILISATEUR COURANT (à lancer connecté OU via email)
-- -----------------------------------------------------------------------------
-- Option A (recommandée depuis l'app) : SELECT public.claim_bootstrap_admin();
-- Option B : décommenter et renseigner l'email :
--
-- update public.profiles
-- set role = 'admin', updated_at = now()
-- where lower(email) = lower('VOTRE_EMAIL@exemple.com');

comment on function public.claim_bootstrap_admin is
  'Promouvoit le premier utilisateur connecté en ADMIN si aucun admin n''existe.';
