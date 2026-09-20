-- =============================================================================
-- Promouvoir un utilisateur en ADMIN (exécution manuelle)
-- Remplacer l'email ci-dessous, puis Run dans Supabase SQL Editor.
-- =============================================================================

update public.profiles
set role = 'admin',
    is_active = true,
    updated_at = now()
where lower(email) = lower('VOTRE_EMAIL@exemple.com');

-- Vérification
select id, email, full_name, role, is_active
from public.profiles
where role = 'admin';
