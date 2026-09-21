-- =============================================================================
-- Nettoyage médicaments / inventaires fictifs (seeds)
-- Ne conserve que les médicaments liés à un stock de pharmacie plateforme active
-- Exécuter dans Supabase SQL Editor APRÈS déploiement de l’app
-- =============================================================================

-- Inventaires orphelins / hors pharmacies plateforme actives
delete from public.inventory i
where not exists (
  select 1 from public.pharmacies p
  where p.id = i.pharmacy_id
    and p.is_platform = true
    and coalesce(p.is_active, true) = true
);

-- Médicaments jamais en stock sur une pharmacie plateforme active
delete from public.medicines m
where not exists (
  select 1
  from public.inventory i
  join public.pharmacies p on p.id = i.pharmacy_id
  where i.medicine_id = m.id
    and p.is_platform = true
    and coalesce(p.is_active, true) = true
);

-- Variantes orphelines (si table présente)
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'medicine_variants'
  ) then
    delete from public.medicine_variants mv
    where not exists (
      select 1 from public.medicines m where m.id = mv.medicine_id
    );
  end if;
end $$;
