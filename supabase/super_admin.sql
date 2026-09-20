-- =============================================================================
-- Super-admin protégé : nicodevnico@gmail.com
-- Exécuter dans Supabase SQL Editor
-- =============================================================================

create or replace function public.super_admin_email()
returns text
language sql
immutable
as $$
  select 'nicodevnico@gmail.com'::text;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(p.email) = public.super_admin_email()
      and p.role = 'admin'
  );
$$;

create or replace function public.is_super_admin_profile(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_id
      and lower(p.email) = public.super_admin_email()
  );
$$;

-- Garantit le rôle admin + actif pour le super-admin
update public.profiles
set role = 'admin',
    is_active = true,
    approval_status = coalesce(approval_status, 'NONE'),
    updated_at = now()
where lower(email) = public.super_admin_email();

-- Trigger : personne (y compris autres admins / SQL client) ne peut
-- suspendre, supprimer ou rétrograder le super-admin.
create or replace function public.protect_super_admin_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if lower(old.email) = public.super_admin_email() then
      raise exception 'SUPER_ADMIN_PROTECTED: ce compte ne peut pas être supprimé';
    end if;
    return old;
  end if;

  if lower(old.email) = public.super_admin_email() then
    -- Interdit : changement d'email, rétrogradation, suspension
    if lower(coalesce(new.email, '')) is distinct from public.super_admin_email()
       or new.role is distinct from 'admin'
       or coalesce(new.is_active, true) = false then
      raise exception 'SUPER_ADMIN_PROTECTED: ce compte ne peut pas être modifié ainsi';
    end if;
    -- Force les valeurs critiques
    new.email := old.email;
    new.role := 'admin';
    new.is_active := true;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_protect_super_admin on public.profiles;
create trigger profiles_protect_super_admin
  before update or delete on public.profiles
  for each row execute procedure public.protect_super_admin_profile();

-- RPC admin_set_user_role : bloquer cible super-admin
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
  if public.is_super_admin_profile(p_user_id) then
    return jsonb_build_object('ok', false, 'error', 'SUPER_ADMIN_PROTECTED');
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

  return jsonb_build_object('ok', true, 'role', p_role);
end;
$$;
