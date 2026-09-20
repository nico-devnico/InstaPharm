-- =============================================================================
-- InstaPharm — Système de stock centralisé, transactionnel et extensible
-- Exécuter APRÈS schema.sql et platform_pharmacies.sql
-- =============================================================================
-- Modèle :
--   Medicine  →  MedicineVariant  →  PharmacyInventory
-- Réservations atomiques (FOR UPDATE) + sources MANUAL | API | IMPORT_CSV | POS
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "postgis";

-- -----------------------------------------------------------------------------
-- 1. VARIANTS DE MÉDICAMENTS (dosage / forme / marque)
-- -----------------------------------------------------------------------------
create table if not exists public.medicine_variants (
  id uuid primary key default gen_random_uuid(),
  medicine_id uuid not null references public.medicines(id) on delete cascade,
  brand text,
  dosage text,
  form text,
  barcode text,
  sku text,
  default_price_xaf int default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists medicine_variants_medicine_idx
  on public.medicine_variants(medicine_id);

create index if not exists medicine_variants_search_idx
  on public.medicine_variants
  using gin (
    to_tsvector(
      'french',
      coalesce(brand, '') || ' ' || coalesce(dosage, '') || ' ' || coalesce(form, '')
    )
  );

-- Migration 1:1 depuis le catalogue plat existant
insert into public.medicine_variants (
  id, medicine_id, brand, dosage, form, default_price_xaf
)
select
  m.id,
  m.id,
  m.brand,
  m.dosage,
  m.form,
  coalesce(m.price_xaf, 0)
from public.medicines m
where not exists (
  select 1 from public.medicine_variants mv where mv.id = m.id
);

-- -----------------------------------------------------------------------------
-- 2. ÉVOLUTION inventory → pharmacy_inventory
-- -----------------------------------------------------------------------------
alter table public.inventory
  add column if not exists medicine_variant_id uuid
    references public.medicine_variants(id) on delete cascade;

alter table public.inventory
  add column if not exists stock_source text not null default 'MANUAL'
    check (stock_source in (
      'MANUAL', 'API', 'IMPORT_CSV', 'POS_INTEGRATION'
    ));

alter table public.inventory
  add column if not exists reserved_quantity int not null default 0
    check (reserved_quantity >= 0);

alter table public.inventory
  add column if not exists low_stock_threshold int not null default 5
    check (low_stock_threshold >= 0);

alter table public.inventory
  add column if not exists last_synced_at timestamptz;

alter table public.inventory
  add column if not exists external_ref text;

-- Lier les lignes existantes aux variants (id = medicine_id en migration 1:1)
update public.inventory i
set medicine_variant_id = i.medicine_id
where i.medicine_variant_id is null
  and exists (
    select 1 from public.medicine_variants mv where mv.id = i.medicine_id
  );

-- Table physique = inventory (écritures Flutter / PostgREST).
-- Vue sémantique pharmacy_inventory = modèle métier PharmacyInventory.
create or replace view public.pharmacy_inventory as
select
  i.id,
  i.pharmacy_id,
  i.medicine_id,
  i.medicine_variant_id,
  i.quantity,
  greatest(coalesce(i.quantity, 0) - coalesce(i.reserved_quantity, 0), 0)
    as available_quantity,
  i.reserved_quantity,
  i.unit_price_xaf as price,
  i.unit_price_xaf,
  upper(i.status) as stock_status,
  i.status,
  i.stock_source,
  i.low_stock_threshold,
  i.updated_at as last_updated,
  i.updated_at,
  i.last_synced_at,
  i.external_ref
from public.inventory i;

create unique index if not exists inventory_pharmacy_variant_uidx
  on public.inventory (pharmacy_id, medicine_variant_id)
  where medicine_variant_id is not null;

create index if not exists inventory_status_idx
  on public.inventory (pharmacy_id, status);

create index if not exists inventory_source_idx
  on public.inventory (stock_source);

-- -----------------------------------------------------------------------------
-- 3. RÉSERVATIONS DE STOCK
-- -----------------------------------------------------------------------------
create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete set null,
  pharmacy_inventory_id uuid not null
    references public.inventory(id) on delete cascade,
  pharmacy_id text not null references public.pharmacies(id) on delete cascade,
  medicine_variant_id uuid not null
    references public.medicine_variants(id) on delete cascade,
  quantity int not null check (quantity > 0),
  status text not null default 'ACTIVE'
    check (status in ('ACTIVE', 'CONFIRMED', 'RELEASED', 'EXPIRED')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stock_reservations_order_idx
  on public.stock_reservations(order_id);

create index if not exists stock_reservations_active_idx
  on public.stock_reservations(status, expires_at)
  where status = 'ACTIVE';

-- -----------------------------------------------------------------------------
-- 4. JOURNAL DES MOUVEMENTS (audit / sync)
-- -----------------------------------------------------------------------------
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  pharmacy_inventory_id uuid not null
    references public.inventory(id) on delete cascade,
  pharmacy_id text not null,
  medicine_variant_id uuid not null,
  movement_type text not null
    check (movement_type in (
      'ADJUSTMENT', 'RESERVE', 'RELEASE', 'CONFIRM',
      'SYNC', 'IMPORT', 'EXPIRE'
    )),
  quantity_delta int not null,
  reserved_delta int not null default 0,
  stock_source text not null default 'MANUAL',
  reference_id uuid,
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists stock_movements_inventory_idx
  on public.stock_movements(pharmacy_inventory_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 5. HELPERS — statut dérivé de la quantité disponible
-- -----------------------------------------------------------------------------
create or replace function public.derive_stock_status(
  p_available int,
  p_threshold int,
  p_current text default null
)
returns text
language plpgsql
immutable
as $$
begin
  -- Ne jamais "réparer" un UNKNOWN en AVAILABLE automatiquement
  if p_current = 'unknown' then
    return 'unknown';
  end if;
  if p_available is null then
    return coalesce(nullif(p_current, ''), 'unknown');
  end if;
  if p_available <= 0 then
    return 'out_of_stock';
  end if;
  if p_available <= greatest(coalesce(p_threshold, 5), 0) then
    return 'low_stock';
  end if;
  return 'available';
end;
$$;

create or replace function public.inventory_available_qty(
  p_quantity int,
  p_reserved int
)
returns int
language sql
immutable
as $$
  select greatest(coalesce(p_quantity, 0) - coalesce(p_reserved, 0), 0);
$$;

-- -----------------------------------------------------------------------------
-- 6. RÉSERVATION ATOMIQUE (verrou ligne FOR UPDATE)
-- -----------------------------------------------------------------------------
create or replace function public.reserve_stock(
  p_pharmacy_id text,
  p_medicine_variant_id uuid,
  p_quantity int,
  p_order_id uuid default null,
  p_expires_minutes int default 15
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  inv public.inventory%rowtype;
  available int;
  reservation_id uuid;
  expires timestamptz;
begin
  if p_quantity is null or p_quantity <= 0 then
    return jsonb_build_object('ok', false, 'error', 'INVALID_QUANTITY');
  end if;

  select * into inv
  from public.inventory
  where pharmacy_id = p_pharmacy_id
    and (
      medicine_variant_id = p_medicine_variant_id
      or medicine_id = p_medicine_variant_id
    )
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  end if;

  -- UNKNOWN n'est jamais traitable comme disponible
  if inv.status = 'unknown' then
    return jsonb_build_object('ok', false, 'error', 'UNKNOWN_STOCK');
  end if;

  if inv.status = 'out_of_stock' then
    return jsonb_build_object('ok', false, 'error', 'OUT_OF_STOCK', 'available', 0);
  end if;

  available := public.inventory_available_qty(inv.quantity, inv.reserved_quantity);

  if available < p_quantity then
    return jsonb_build_object(
      'ok', false,
      'error', 'INSUFFICIENT_STOCK',
      'available', available,
      'requested', p_quantity
    );
  end if;

  expires := now() + make_interval(mins => greatest(coalesce(p_expires_minutes, 15), 1));

  update public.inventory
  set
    reserved_quantity = coalesce(reserved_quantity, 0) + p_quantity,
    status = public.derive_stock_status(
      public.inventory_available_qty(quantity, coalesce(reserved_quantity, 0) + p_quantity),
      low_stock_threshold,
      status
    ),
    updated_at = now()
  where id = inv.id;

  insert into public.stock_reservations (
    order_id, pharmacy_inventory_id, pharmacy_id,
    medicine_variant_id, quantity, status, expires_at
  ) values (
    p_order_id,
    inv.id,
    p_pharmacy_id,
    coalesce(inv.medicine_variant_id, p_medicine_variant_id),
    p_quantity,
    'ACTIVE',
    expires
  )
  returning id into reservation_id;

  insert into public.stock_movements (
    pharmacy_inventory_id, pharmacy_id, medicine_variant_id,
    movement_type, quantity_delta, reserved_delta, stock_source,
    reference_id, note
  ) values (
    inv.id, p_pharmacy_id, coalesce(inv.medicine_variant_id, p_medicine_variant_id),
    'RESERVE', 0, p_quantity, inv.stock_source,
    reservation_id, 'Réservation commande'
  );

  return jsonb_build_object(
    'ok', true,
    'reservation_id', reservation_id,
    'available_after', available - p_quantity,
    'expires_at', expires
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. LIBÉRATION (annulation / échec / expiration)
-- -----------------------------------------------------------------------------
create or replace function public.release_stock_reservation(
  p_reservation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  res public.stock_reservations%rowtype;
  inv public.inventory%rowtype;
begin
  select * into res
  from public.stock_reservations
  where id = p_reservation_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'RESERVATION_NOT_FOUND');
  end if;

  if res.status <> 'ACTIVE' then
    return jsonb_build_object('ok', true, 'already', res.status);
  end if;

  select * into inv
  from public.inventory
  where id = res.pharmacy_inventory_id
  for update;

  update public.inventory
  set
    reserved_quantity = greatest(coalesce(reserved_quantity, 0) - res.quantity, 0),
    status = public.derive_stock_status(
      public.inventory_available_qty(
        quantity,
        greatest(coalesce(reserved_quantity, 0) - res.quantity, 0)
      ),
      low_stock_threshold,
      case when status = 'unknown' then 'unknown' else null end
    ),
    updated_at = now()
  where id = inv.id;

  update public.stock_reservations
  set status = 'RELEASED', updated_at = now()
  where id = res.id;

  insert into public.stock_movements (
    pharmacy_inventory_id, pharmacy_id, medicine_variant_id,
    movement_type, quantity_delta, reserved_delta, stock_source, reference_id
  ) values (
    res.pharmacy_inventory_id, res.pharmacy_id, res.medicine_variant_id,
    'RELEASE', 0, -res.quantity, coalesce(inv.stock_source, 'MANUAL'), res.id
  );

  return jsonb_build_object('ok', true, 'reservation_id', res.id);
end;
$$;

create or replace function public.release_order_reservations(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  released int := 0;
begin
  for r in
    select id from public.stock_reservations
    where order_id = p_order_id and status = 'ACTIVE'
  loop
    perform public.release_stock_reservation(r.id);
    released := released + 1;
  end loop;
  return jsonb_build_object('ok', true, 'released', released);
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. CONFIRMATION (déduction définitive après validation commande)
-- -----------------------------------------------------------------------------
create or replace function public.confirm_stock_reservation(
  p_reservation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  res public.stock_reservations%rowtype;
  inv public.inventory%rowtype;
  new_qty int;
begin
  select * into res
  from public.stock_reservations
  where id = p_reservation_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'RESERVATION_NOT_FOUND');
  end if;

  if res.status = 'CONFIRMED' then
    return jsonb_build_object('ok', true, 'already', 'CONFIRMED');
  end if;

  if res.status <> 'ACTIVE' then
    return jsonb_build_object('ok', false, 'error', 'INVALID_STATUS', 'status', res.status);
  end if;

  select * into inv
  from public.inventory
  where id = res.pharmacy_inventory_id
  for update;

  new_qty := greatest(coalesce(inv.quantity, 0) - res.quantity, 0);

  update public.inventory
  set
    quantity = new_qty,
    reserved_quantity = greatest(coalesce(reserved_quantity, 0) - res.quantity, 0),
    status = public.derive_stock_status(
      public.inventory_available_qty(
        new_qty,
        greatest(coalesce(reserved_quantity, 0) - res.quantity, 0)
      ),
      low_stock_threshold,
      case when status = 'unknown' then 'unknown' else null end
    ),
    updated_at = now()
  where id = inv.id;

  update public.stock_reservations
  set status = 'CONFIRMED', updated_at = now()
  where id = res.id;

  insert into public.stock_movements (
    pharmacy_inventory_id, pharmacy_id, medicine_variant_id,
    movement_type, quantity_delta, reserved_delta, stock_source, reference_id
  ) values (
    res.pharmacy_inventory_id, res.pharmacy_id, res.medicine_variant_id,
    'CONFIRM', -res.quantity, -res.quantity,
    coalesce(inv.stock_source, 'MANUAL'), res.id
  );

  return jsonb_build_object('ok', true, 'quantity_after', new_qty);
end;
$$;

create or replace function public.confirm_order_reservations(
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  confirmed int := 0;
begin
  for r in
    select id from public.stock_reservations
    where order_id = p_order_id and status = 'ACTIVE'
  loop
    perform public.confirm_stock_reservation(r.id);
    confirmed := confirmed + 1;
  end loop;
  return jsonb_build_object('ok', true, 'confirmed', confirmed);
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. EXPIRATION DES RÉSERVATIONS PÉRIMÉES
-- -----------------------------------------------------------------------------
create or replace function public.expire_stale_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id from public.stock_reservations
    where status = 'ACTIVE' and expires_at < now()
  loop
    perform public.release_stock_reservation(r.id);
    update public.stock_reservations
    set status = 'EXPIRED', updated_at = now()
    where id = r.id and status = 'RELEASED';
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'expired', n);
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. UPSERT MANUEL / SYNC (source tracée)
-- -----------------------------------------------------------------------------
create or replace function public.upsert_pharmacy_stock(
  p_pharmacy_id text,
  p_medicine_variant_id uuid,
  p_quantity int,
  p_price int default null,
  p_stock_status text default null,
  p_stock_source text default 'MANUAL',
  p_external_ref text default null,
  p_low_stock_threshold int default null,
  p_actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  inv_id uuid;
  final_status text;
  available int;
  src text;
begin
  src := upper(coalesce(p_stock_source, 'MANUAL'));
  if src not in ('MANUAL', 'API', 'IMPORT_CSV', 'POS_INTEGRATION') then
    src := 'MANUAL';
  end if;

  -- Interdire d'afficher AVAILABLE si on force UNKNOWN
  if lower(coalesce(p_stock_status, '')) = 'unknown' then
    final_status := 'unknown';
  elsif p_stock_status is not null then
    final_status := lower(p_stock_status);
  else
    final_status := null;
  end if;

  insert into public.inventory (
    pharmacy_id,
    medicine_id,
    medicine_variant_id,
    quantity,
    unit_price_xaf,
    status,
    stock_source,
    low_stock_threshold,
    external_ref,
    last_synced_at,
    updated_at
  ) values (
    p_pharmacy_id,
    p_medicine_variant_id,
    p_medicine_variant_id,
    coalesce(p_quantity, 0),
    p_price,
    coalesce(
      final_status,
      public.derive_stock_status(coalesce(p_quantity, 0), coalesce(p_low_stock_threshold, 5), null)
    ),
    src,
    coalesce(p_low_stock_threshold, 5),
    p_external_ref,
    case when src <> 'MANUAL' then now() else null end,
    now()
  )
  on conflict (pharmacy_id, medicine_id) do update set
    medicine_variant_id = excluded.medicine_variant_id,
    quantity = excluded.quantity,
    unit_price_xaf = coalesce(excluded.unit_price_xaf, public.inventory.unit_price_xaf),
    status = case
      when excluded.status = 'unknown' then 'unknown'
      when final_status is not null then final_status
      else public.derive_stock_status(
        public.inventory_available_qty(
          excluded.quantity,
          public.inventory.reserved_quantity
        ),
        coalesce(excluded.low_stock_threshold, public.inventory.low_stock_threshold),
        null
      )
    end,
    stock_source = excluded.stock_source,
    low_stock_threshold = coalesce(
      excluded.low_stock_threshold,
      public.inventory.low_stock_threshold
    ),
    external_ref = coalesce(excluded.external_ref, public.inventory.external_ref),
    last_synced_at = case
      when excluded.stock_source <> 'MANUAL' then now()
      else public.inventory.last_synced_at
    end,
    updated_at = now()
  returning id into inv_id;

  select public.inventory_available_qty(quantity, reserved_quantity)
  into available
  from public.inventory where id = inv_id;

  insert into public.stock_movements (
    pharmacy_inventory_id, pharmacy_id, medicine_variant_id,
    movement_type, quantity_delta, stock_source, created_by, note
  ) values (
    inv_id, p_pharmacy_id, p_medicine_variant_id,
    case when src = 'MANUAL' then 'ADJUSTMENT'
         when src = 'IMPORT_CSV' then 'IMPORT'
         else 'SYNC' end,
    coalesce(p_quantity, 0),
    src,
    p_actor,
    'Upsert stock source=' || src
  );

  return jsonb_build_object(
    'ok', true,
    'inventory_id', inv_id,
    'available_quantity', available,
    'stock_source', src
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. RECHERCHE CENTRALE (base plateforme uniquement)
-- -----------------------------------------------------------------------------
create or replace function public.search_medicine_stock(
  p_query text,
  p_lat double precision default null,
  p_lng double precision default null,
  p_limit int default 40
)
returns table (
  pharmacy_id text,
  pharmacy_name text,
  pharmacy_address text,
  pharmacy_city text,
  pharmacy_lat double precision,
  pharmacy_lng double precision,
  pharmacy_is_open boolean,
  pharmacy_is_duty boolean,
  medicine_id uuid,
  medicine_name text,
  medicine_brand text,
  medicine_dosage text,
  medicine_form text,
  medicine_variant_id uuid,
  inventory_id uuid,
  quantity int,
  available_quantity int,
  unit_price_xaf int,
  stock_status text,
  stock_source text,
  last_updated timestamptz,
  last_synced_at timestamptz,
  is_stale boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select trim(p_query) as term
  ),
  matched as (
    select
      m.id as medicine_id,
      m.name as medicine_name,
      mv.id as medicine_variant_id,
      coalesce(mv.brand, m.brand) as medicine_brand,
      coalesce(mv.dosage, m.dosage) as medicine_dosage,
      coalesce(mv.form, m.form) as medicine_form
    from public.medicines m
    join public.medicine_variants mv on mv.medicine_id = m.id and mv.is_active
    cross join q
    where q.term <> ''
      and (
        m.name ilike '%' || q.term || '%'
        or coalesce(m.brand, '') ilike '%' || q.term || '%'
        or coalesce(mv.brand, '') ilike '%' || q.term || '%'
        or coalesce(m.category, '') ilike '%' || q.term || '%'
        or coalesce(mv.dosage, '') ilike '%' || q.term || '%'
      )
    limit 24
  )
  select
    ph.id,
    ph.name,
    ph.address,
    ph.city,
    ph.latitude,
    ph.longitude,
    ph.is_open,
    ph.is_duty,
    matched.medicine_id,
    matched.medicine_name,
    matched.medicine_brand,
    matched.medicine_dosage,
    matched.medicine_form,
    matched.medicine_variant_id,
    pi.id,
    pi.quantity,
    public.inventory_available_qty(pi.quantity, pi.reserved_quantity),
    pi.unit_price_xaf,
    -- Ne jamais remonter AVAILABLE pour UNKNOWN
    case
      when pi.status = 'unknown' then 'unknown'
      else pi.status
    end,
    pi.stock_source,
    pi.updated_at,
    pi.last_synced_at,
    (pi.updated_at < now() - interval '24 hours')
      or (pi.stock_source <> 'MANUAL' and (
        pi.last_synced_at is null
        or pi.last_synced_at < now() - interval '6 hours'
      ))
  from matched
  join public.inventory pi
    on (pi.medicine_variant_id = matched.medicine_variant_id
        or pi.medicine_id = matched.medicine_id)
  join public.pharmacies ph
    on ph.id = pi.pharmacy_id and ph.is_platform = true
  order by
    case
      when pi.status = 'available' then 0
      when pi.status = 'low_stock' then 1
      when pi.status = 'out_of_stock' then 2
      else 3
    end,
    pi.updated_at desc
  limit greatest(coalesce(p_limit, 40), 1);
$$;

-- -----------------------------------------------------------------------------
-- 11b. COMMANDE + RÉSERVATION ATOMIQUE (transaction unique)
-- -----------------------------------------------------------------------------
create or replace function public.place_order_with_stock(
  p_pharmacy_id text,
  p_pharmacy_name text,
  p_fulfillment text,
  p_payment_method text,
  p_items jsonb,
  p_notes text default null,
  p_has_prescription boolean default false,
  p_delivery jsonb default null,
  p_delivery_fee_xaf int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  order_uuid uuid;
  public_code text;
  item jsonb;
  variant_id uuid;
  qty int;
  unit_price int;
  subtotal int := 0;
  reserve_result jsonb;
  reserved_ids uuid[] := '{}';
  rid uuid;
  medicine_name text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'UNAUTHENTICATED');
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('ok', false, 'error', 'EMPTY_CART');
  end if;

  -- Expire d'abord les réservations périmées (libère du stock)
  perform public.expire_stale_reservations();

  public_code := 'CMD-' || (extract(epoch from now())::bigint % 1000000)::text;

  insert into public.orders (
    public_code, user_id, pharmacy_id, pharmacy_name,
    fulfillment, payment_method, status,
    subtotal_xaf, delivery_fee_xaf, notes, has_prescription,
    recipient_name, recipient_phone, delivery_city, delivery_neighborhood,
    delivery_address, dest_lat, dest_lng, from_live_gps,
    route_geometry, route_distance_m, route_duration_s, eta_minutes
  ) values (
    public_code,
    uid,
    p_pharmacy_id,
    p_pharmacy_name,
    p_fulfillment,
    p_payment_method,
    'pending',
    0,
    coalesce(p_delivery_fee_xaf, 0),
    p_notes,
    coalesce(p_has_prescription, false),
    p_delivery->>'recipient_name',
    p_delivery->>'phone',
    p_delivery->>'city',
    p_delivery->>'neighborhood',
    p_delivery->>'address',
    nullif(p_delivery->>'dest_lat', '')::double precision,
    nullif(p_delivery->>'dest_lng', '')::double precision,
    coalesce((p_delivery->>'from_live_gps')::boolean, false),
    coalesce(p_delivery->'route_geometry', '[]'::jsonb),
    nullif(p_delivery->>'route_distance_m', '')::double precision,
    nullif(p_delivery->>'route_duration_s', '')::int,
    nullif(p_delivery->>'eta_minutes', '')::int
  )
  returning id into order_uuid;

  for item in select * from jsonb_array_elements(p_items)
  loop
    variant_id := coalesce(
      nullif(item->>'medicine_variant_id', '')::uuid,
      nullif(item->>'medicine_id', '')::uuid
    );
    qty := greatest(coalesce((item->>'quantity')::int, 1), 1);
    unit_price := coalesce((item->>'unit_price_xaf')::int, 0);
    medicine_name := coalesce(item->>'medicine_name', 'Médicament');
    subtotal := subtotal + (unit_price * qty);

    -- Quantité lue côté serveur — jamais confiance aveugle au seul frontend
    -- pour la disponibilité : reserve_stock verrouille et refuse si insuffisant
    reserve_result := public.reserve_stock(
      p_pharmacy_id, variant_id, qty, order_uuid, 20
    );

    if coalesce((reserve_result->>'ok')::boolean, false) is not true then
      -- Rollback : libérer ce qui a déjà été réservé + supprimer la commande
      foreach rid in array reserved_ids loop
        perform public.release_stock_reservation(rid);
      end loop;
      delete from public.orders where id = order_uuid;
      return jsonb_build_object(
        'ok', false,
        'error', coalesce(reserve_result->>'error', 'RESERVE_FAILED'),
        'available', reserve_result->'available',
        'medicine_variant_id', variant_id
      );
    end if;

    reserved_ids := array_append(
      reserved_ids,
      (reserve_result->>'reservation_id')::uuid
    );

    insert into public.order_items (
      order_id, medicine_id, medicine_name, brand, dosage,
      quantity, unit_price_xaf, requires_prescription
    ) values (
      order_uuid,
      variant_id::text,
      medicine_name,
      item->>'brand',
      item->>'dosage',
      qty,
      unit_price,
      coalesce((item->>'requires_prescription')::boolean, false)
    );
  end loop;

  update public.orders
  set subtotal_xaf = subtotal, status = 'confirmed', updated_at = now()
  where id = order_uuid;

  return jsonb_build_object(
    'ok', true,
    'order_id', order_uuid,
    'public_code', public_code,
    'subtotal_xaf', subtotal,
    'reservation_ids', to_jsonb(reserved_ids)
  );
exception
  when others then
    if order_uuid is not null then
      perform public.release_order_reservations(order_uuid);
      delete from public.orders where id = order_uuid;
    end if;
    return jsonb_build_object('ok', false, 'error', SQLERRM);
end;
$$;

grant execute on function public.place_order_with_stock(
  text, text, text, text, jsonb, text, boolean, jsonb, int
) to authenticated;

-- Pharmaciens : peuvent enrichir le catalogue (ajout médicament + variante)
drop policy if exists "medicines_pharmacist_insert" on public.medicines;
create policy "medicines_pharmacist_insert" on public.medicines
  for insert with check (public.is_pharmacist() or public.is_staff_admin());

drop policy if exists "medicines_pharmacist_update" on public.medicines;
create policy "medicines_pharmacist_update" on public.medicines
  for update using (public.is_pharmacist() or public.is_staff_admin());


-- -----------------------------------------------------------------------------
-- 12. TRIGGER — libération auto si commande annulée
-- -----------------------------------------------------------------------------
create or replace function public.on_order_status_stock_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform public.release_order_reservations(new.id);
  end if;

  -- Confirmation définitive du stock à la préparation
  if new.status in ('preparing', 'ready_for_pickup', 'out_for_delivery', 'delivered')
     and old.status in ('pending', 'confirmed') then
    perform public.confirm_order_reservations(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists orders_stock_side_effects on public.orders;
create trigger orders_stock_side_effects
  after update of status on public.orders
  for each row
  execute procedure public.on_order_status_stock_side_effects();

-- -----------------------------------------------------------------------------
-- 13. RLS
-- -----------------------------------------------------------------------------
alter table public.medicine_variants enable row level security;
alter table public.stock_reservations enable row level security;
alter table public.stock_movements enable row level security;

-- Si la table a été renommée, réactiver RLS
do $$
begin
  alter table public.inventory enable row level security;
exception when undefined_table then null;
end $$;

drop policy if exists "medicine_variants_read_all" on public.medicine_variants;
create policy "medicine_variants_read_all" on public.medicine_variants
  for select using (true);

drop policy if exists "medicine_variants_staff_write" on public.medicine_variants;
create policy "medicine_variants_staff_write" on public.medicine_variants
  for all using (
    public.is_staff_admin() or public.is_pharmacist()
  )
  with check (
    public.is_staff_admin() or public.is_pharmacist()
  );

-- Pharmacie : uniquement son propre stock
drop policy if exists "inventory_write_staff" on public.inventory;
drop policy if exists "pharmacy_inventory_read_all" on public.inventory;
drop policy if exists "pharmacy_inventory_write_own" on public.inventory;

create policy "pharmacy_inventory_read_all" on public.inventory
  for select using (true);

create policy "pharmacy_inventory_write_own" on public.inventory
  for all using (
    public.is_staff_admin()
    or exists (
      select 1 from public.pharmacies ph
      where ph.id = pharmacy_id
        and ph.is_platform = true
        and ph.owner_user_id = auth.uid()
    )
  )
  with check (
    public.is_staff_admin()
    or exists (
      select 1 from public.pharmacies ph
      where ph.id = pharmacy_id
        and ph.is_platform = true
        and ph.owner_user_id = auth.uid()
    )
  );

drop policy if exists "stock_reservations_select" on public.stock_reservations;
create policy "stock_reservations_select" on public.stock_reservations
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = order_id and o.user_id = auth.uid()
    )
    or public.is_staff_admin()
    or public.is_pharmacist()
  );

drop policy if exists "stock_movements_select" on public.stock_movements;
create policy "stock_movements_select" on public.stock_movements
  for select using (
    public.is_staff_admin()
    or exists (
      select 1 from public.pharmacies ph
      where ph.id = pharmacy_id and ph.owner_user_id = auth.uid()
    )
  );

-- RPC utilisables par clients authentifiés
grant execute on function public.reserve_stock(text, uuid, int, uuid, int) to authenticated;
grant execute on function public.release_stock_reservation(uuid) to authenticated;
grant execute on function public.release_order_reservations(uuid) to authenticated;
grant execute on function public.confirm_stock_reservation(uuid) to authenticated;
grant execute on function public.confirm_order_reservations(uuid) to authenticated;
grant execute on function public.expire_stale_reservations() to authenticated, service_role;
grant execute on function public.upsert_pharmacy_stock(text, uuid, int, int, text, text, text, int, uuid)
  to authenticated, service_role;
grant execute on function public.search_medicine_stock(text, double precision, double precision, int)
  to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 14. COMMENTAIRES
-- -----------------------------------------------------------------------------
comment on table public.medicine_variants is
  'Variantes (dosage/forme/marque) séparées du produit médicament.';
comment on table public.stock_reservations is
  'Réservations atomiques de stock liées aux commandes.';
comment on column public.inventory.stock_source is
  'MANUAL | API | IMPORT_CSV | POS_INTEGRATION — extensible via CHECK.';
comment on function public.reserve_stock is
  'Réserve du stock avec verrou FOR UPDATE. Refuse UNKNOWN et survente.';
