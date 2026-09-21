-- Suppression réelle d'un utilisateur (profil + auth) par un admin
-- + auto-suppression de compte (non-admin)
-- Exécuter dans Supabase SQL Editor

create or replace function public.admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_email text;
begin
  if not public.is_staff_admin() then
    return jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
  end if;

  if public.is_super_admin_profile(p_user_id) then
    return jsonb_build_object('ok', false, 'error', 'SUPER_ADMIN_PROTECTED');
  end if;

  select email into target_email from public.profiles where id = p_user_id;
  if target_email is null then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- Empêche un admin de se supprimer lui-même via cette RPC
  if p_user_id = auth.uid() then
    return jsonb_build_object('ok', false, 'error', 'CANNOT_DELETE_SELF');
  end if;

  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;

  insert into public.audit_logs (actor_id, action, resource_type, resource_id, meta)
  values (
    auth.uid(),
    'DELETE_USER',
    'profile',
    p_user_id::text,
    jsonb_build_object('email', target_email, 'hard', true)
  );

  return jsonb_build_object('ok', true, 'deleted', p_user_id);
end;
$$;

grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Un utilisateur non-admin peut supprimer son propre compte
create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  end if;

  if public.is_super_admin() or public.is_staff_admin() then
    return jsonb_build_object(
      'ok', false,
      'error', 'ADMIN_CANNOT_SELF_DELETE',
      'message', 'Un administrateur ne peut pas supprimer son compte depuis l''app.'
    );
  end if;

  delete from public.profiles where id = uid;
  delete from auth.users where id = uid;

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.delete_my_account() to authenticated;

-- Interdit le self-service de changement de rôle (patient ↔ pharmacien ↔ livreur)
create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.role is distinct from old.role
     and auth.uid() = new.id
     and not public.is_staff_admin() then
    raise exception 'FORBIDDEN_SELF_ROLE_CHANGE';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_prevent_self_role_change on public.profiles;
create trigger profiles_prevent_self_role_change
  before update on public.profiles
  for each row execute procedure public.prevent_self_role_change();
