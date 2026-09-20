-- =============================================================================
-- InstaPharm — Approbation comptes pharmacie / livreur + nettoyage démos
-- Exécuter dans le SQL Editor Supabase après admin_system.sql
-- =============================================================================

-- Demandes d'inscription pro (pharmacien / livreur)
create table if not exists public.account_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_requested text not null check (role_requested in ('pharmacist', 'courier')),
  full_name text not null,
  phone text,
  email text,
  business_name text,
  business_address text,
  business_city text,
  license_number text,
  id_document_url text,
  professional_document_url text,
  notes text,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'REJECTED', 'NEEDS_INFO')),
  admin_notes text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists account_applications_status_idx
  on public.account_applications(status, created_at desc);
create index if not exists account_applications_user_idx
  on public.account_applications(user_id);

alter table public.account_applications enable row level security;

drop policy if exists "applications_own_select" on public.account_applications;
create policy "applications_own_select" on public.account_applications
  for select using (auth.uid() = user_id or public.is_staff_admin());

drop policy if exists "applications_own_insert" on public.account_applications;
create policy "applications_own_insert" on public.account_applications
  for insert with check (auth.uid() = user_id);

drop policy if exists "applications_own_update" on public.account_applications;
create policy "applications_own_update" on public.account_applications
  for update using (auth.uid() = user_id or public.is_staff_admin());

drop policy if exists "applications_admin_all" on public.account_applications;
create policy "applications_admin_all" on public.account_applications
  for all using (public.is_staff_admin());

-- Profils : statut d'approbation pour rôles pro
alter table public.profiles
  add column if not exists approval_status text not null default 'NONE'
    check (approval_status in ('NONE', 'PENDING', 'APPROVED', 'REJECTED'));

-- Les nouveaux pharmaciens/livreurs restent patient jusqu'à approbation
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta_role text := coalesce(new.raw_user_meta_data->>'role', 'patient');
  final_role text := 'patient';
  approval text := 'NONE';
begin
  if meta_role in ('pharmacist', 'courier') then
    final_role := 'patient'; -- rôle effectif après approbation admin
    approval := 'PENDING';
  elsif meta_role = 'admin' then
    final_role := 'patient'; -- jamais auto-admin
    approval := 'NONE';
  else
    final_role := 'patient';
  end if;

  insert into public.profiles (id, email, full_name, phone, role, approval_status)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    final_role,
    approval
  )
  on conflict (id) do nothing;

  if meta_role in ('pharmacist', 'courier') then
    insert into public.account_applications (
      user_id, role_requested, full_name, phone, email,
      business_name, business_address, business_city, license_number,
      notes, status
    ) values (
      new.id,
      meta_role,
      coalesce(new.raw_user_meta_data->>'full_name', 'Demandeur'),
      new.raw_user_meta_data->>'phone',
      new.email,
      new.raw_user_meta_data->>'business_name',
      new.raw_user_meta_data->>'business_address',
      new.raw_user_meta_data->>'business_city',
      new.raw_user_meta_data->>'license_number',
      new.raw_user_meta_data->>'application_notes',
      'PENDING'
    );
  end if;

  return new;
end;
$$;

-- Paramètres supplémentaires
insert into public.app_settings (key, value, label, category) values
  ('registration.approval', '{"enabled":true,"require_id_document":true,"require_professional_document":true}'::jsonb,
   'Approbation inscriptions pro', 'security'),
  ('search.map', '{"min_radius_km":1,"max_radius_km":15,"default_radius_km":3}'::jsonb,
   'Carte / recherche pharmacies', 'search'),
  ('ui.branding', '{"tagline":"Vos pharmacies à proximité","primary_cta":"Trouver une pharmacie"}'::jsonb,
   'Marque / textes UI', 'general'),
  ('orders.rules', '{"auto_cancel_minutes":120,"max_items":20}'::jsonb,
   'Règles commandes', 'ops')
on conflict (key) do nothing;

-- Mise à jour search.defaults pour cohérence
update public.app_settings
set value = jsonb_set(coalesce(value, '{}'::jsonb), '{radius_km}', '3'::jsonb)
where key = 'search.defaults';

-- ---------------------------------------------------------------------------
-- Nettoyage données fictives / démo (pharmacies seed + livreur seed)
-- ---------------------------------------------------------------------------
delete from public.inventory
where pharmacy_id in (
  'plat-douala-bonanjo', 'plat-douala-akwa',
  'plat-yaounde-bastos', 'plat-yaounde-mvog'
);

delete from public.pharmacies
where id in (
  'plat-douala-bonanjo', 'plat-douala-akwa',
  'plat-yaounde-bastos', 'plat-yaounde-mvog'
);

delete from public.couriers
where full_name = 'Jean Mbarga' and phone = '+237699123456';

-- RPC : approuver une demande
create or replace function public.admin_review_application(
  p_application_id uuid,
  p_status text,
  p_admin_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  app_row public.account_applications%rowtype;
begin
  if not public.is_staff_admin() then
    return jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
  end if;
  if p_status not in ('APPROVED', 'REJECTED', 'NEEDS_INFO') then
    return jsonb_build_object('ok', false, 'error', 'BAD_STATUS');
  end if;

  select * into app_row from public.account_applications where id = p_application_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- Avant approbation : pièce d'identité + document pro obligatoires
  if p_status = 'APPROVED' then
    if app_row.id_document_url is null or btrim(app_row.id_document_url) = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'MISSING_ID_DOCUMENT',
        'message', 'Joignez la pièce d''identité (image ou PDF) avant d''approuver.'
      );
    end if;
    if app_row.professional_document_url is null
       or btrim(app_row.professional_document_url) = '' then
      return jsonb_build_object(
        'ok', false,
        'error', 'MISSING_PROFESSIONAL_DOCUMENT',
        'message', 'Joignez le document professionnel avant d''approuver.'
      );
    end if;
  end if;

  update public.account_applications set
    status = p_status,
    admin_notes = p_admin_notes,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    updated_at = now()
  where id = p_application_id;

  if p_status = 'APPROVED' then
    update public.profiles set
      role = app_row.role_requested,
      approval_status = 'APPROVED',
      updated_at = now()
    where id = app_row.user_id;

    if app_row.role_requested = 'courier' then
      insert into public.couriers (full_name, phone, user_id, is_available, is_active)
      values (
        app_row.full_name,
        app_row.phone,
        app_row.user_id,
        true,
        true
      )
      on conflict do nothing;
      -- si pas de contrainte unique user_id, éviter doublons
      if not exists (select 1 from public.couriers where user_id = app_row.user_id) then
        insert into public.couriers (full_name, phone, user_id, is_available, is_active)
        values (app_row.full_name, app_row.phone, app_row.user_id, true, true);
      end if;
    end if;

    if app_row.role_requested = 'pharmacist' and app_row.business_name is not null then
      insert into public.pharmacies (
        id, name, address, city, phone, is_platform, is_verified,
        platform_status, is_active, owner_user_id, registered_by
      ) values (
        'plat-' || substr(replace(app_row.user_id::text, '-', ''), 1, 16),
        app_row.business_name,
        app_row.business_address,
        app_row.business_city,
        app_row.phone,
        true,
        true,
        'PENDING',
        true,
        app_row.user_id,
        auth.uid()
      )
      on conflict (id) do update set owner_user_id = excluded.owner_user_id;
    end if;
  elsif p_status = 'REJECTED' then
    update public.profiles set
      approval_status = 'REJECTED',
      updated_at = now()
    where id = app_row.user_id;
  else
    update public.profiles set
      approval_status = 'PENDING',
      updated_at = now()
    where id = app_row.user_id;
  end if;

  insert into public.audit_logs (actor_id, action, resource_type, resource_id, meta)
  values (
    auth.uid(),
    'REVIEW_APPLICATION',
    'account_application',
    p_application_id::text,
    jsonb_build_object('status', p_status, 'role', app_row.role_requested)
  );

  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;
