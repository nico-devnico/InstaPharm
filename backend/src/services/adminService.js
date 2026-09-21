const { getPool, getServiceSupabase } = require('../db');

async function writeAudit(clientOrNull, {
  actorId,
  action,
  resourceType,
  resourceId = null,
  meta = {},
  ip = null,
}) {
  const sql = `
    insert into public.audit_logs (actor_id, action, resource_type, resource_id, meta, ip)
    values ($1, $2, $3, $4, $5::jsonb, $6)
  `;
  const params = [
    actorId,
    action,
    resourceType,
    resourceId,
    JSON.stringify(meta || {}),
    ip,
  ];
  if (clientOrNull) {
    await clientOrNull.query(sql, params);
  } else {
    await getPool().query(sql, params);
  }
}

class AdminService {
  async assertAdmin(userId) {
    const { rows } = await getPool().query(
      `select role, is_active from public.profiles where id = $1`,
      [userId],
    );
    const p = rows[0];
    if (!p || p.role !== 'admin' || p.is_active === false) {
      const err = new Error('FORBIDDEN');
      err.code = 'FORBIDDEN';
      throw err;
    }
    return true;
  }

  async claimBootstrapAdmin(userId, ip) {
    const { rows } = await getPool().query(
      `select count(*)::int as c from public.profiles where role = 'admin'`,
    );
    if (rows[0].c > 0) {
      const me = await getPool().query(
        `select role from public.profiles where id = $1`,
        [userId],
      );
      if (me.rows[0]?.role === 'admin') {
        return { ok: true, already: true };
      }
      const err = new Error('ADMIN_EXISTS');
      err.code = 'ADMIN_EXISTS';
      throw err;
    }
    await getPool().query(
      `update public.profiles set role = 'admin', updated_at = now() where id = $1`,
      [userId],
    );
    await writeAudit(null, {
      actorId: userId,
      action: 'BOOTSTRAP_ADMIN',
      resourceType: 'profile',
      resourceId: userId,
      meta: { note: 'Premier administrateur (API)' },
      ip,
    });
    return { ok: true, promoted: true, userId };
  }

  async forcePromoteUser(targetUserId, actorId, ip) {
    await this.assertAdmin(actorId);
    await getPool().query(
      `update public.profiles set role = 'admin', updated_at = now() where id = $1`,
      [targetUserId],
    );
    await writeAudit(null, {
      actorId,
      action: 'FORCE_PROMOTE_ADMIN',
      resourceType: 'profile',
      resourceId: targetUserId,
      ip,
    });
    return { ok: true };
  }

  async dashboard(actorId) {
    await this.assertAdmin(actorId);
    const { rows } = await getPool().query(
      `select public.admin_dashboard_stats() as stats`,
    );
    // Si RPC dépend de auth.uid(), recalculer en SQL direct
    const stats = rows[0]?.stats;
    if (stats?.ok) return stats;

    const q = async (sql) => (await getPool().query(sql)).rows[0];
    const users = await q(`select count(*)::int as n from public.profiles`);
    const usersActive = await q(
      `select count(*)::int as n from public.profiles where coalesce(is_active,true)`,
    );
    const roles = await getPool().query(
      `select role, count(*)::int as c from public.profiles group by role`,
    );
    const ph = await q(
      `select
        count(*) filter (where is_platform)::int as total,
        count(*) filter (where is_platform and coalesce(platform_status,'VERIFIED')='VERIFIED' and coalesce(is_active,true))::int as verified,
        count(*) filter (where is_platform and platform_status='PENDING')::int as pending,
        count(*) filter (where is_platform and platform_status='REJECTED')::int as rejected,
        count(*) filter (where is_platform and platform_status='SUSPENDED')::int as suspended
       from public.pharmacies`,
    );
    const meds = await q(
      `select count(*)::int as total,
              count(*) filter (where coalesce(is_active,true))::int as active
       from public.medicines`,
    );
    const orders = await q(
      `select
        count(*)::int as total,
        count(*) filter (where status not in ('delivered','cancelled'))::int as active,
        count(*) filter (where status='delivered')::int as delivered,
        count(*) filter (where status='cancelled')::int as cancelled,
        count(*) filter (where fulfillment='delivery' and status='out_for_delivery')::int as deliveries
       from public.orders`,
    );
    const couriers = await q(
      `select count(*)::int as total,
              count(*) filter (where is_available and coalesce(is_active,true))::int as available
       from public.couriers`,
    );
    const reports = await q(
      `select count(*)::int as n from public.reports
       where status in ('OPEN','IN_PROGRESS')`,
    ).catch(() => ({ n: 0 }));
    const byStatus = await getPool().query(
      `select status, count(*)::int as c from public.orders group by status`,
    );

    const usersByRole = {};
    for (const r of roles.rows) usersByRole[r.role] = r.c;
    const ordersByStatus = {};
    for (const r of byStatus.rows) ordersByStatus[r.status] = r.c;

    return {
      ok: true,
      users_total: users.n,
      users_active: usersActive.n,
      users_by_role: usersByRole,
      pharmacies_total: ph.total,
      pharmacies_verified: ph.verified,
      pharmacies_pending: ph.pending,
      pharmacies_rejected: ph.rejected,
      pharmacies_suspended: ph.suspended,
      medicines_total: meds.total,
      medicines_active: meds.active,
      orders_total: orders.total,
      orders_active: orders.active,
      orders_delivered: orders.delivered,
      orders_cancelled: orders.cancelled,
      deliveries_in_progress: orders.deliveries,
      couriers_total: couriers.total,
      couriers_available: couriers.available,
      reports_open: reports.n || 0,
      orders_by_status: ordersByStatus,
      generated_at: new Date().toISOString(),
    };
  }

  async listUsers(actorId, { q, role, active, page = 1, pageSize = 20 } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];

    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(
        `(full_name ilike $${params.length} or email ilike $${params.length} or phone ilike $${params.length})`,
      );
    }
    if (role) {
      params.push(role);
      where.push(`role = $${params.length}`);
    }
    if (active === 'true' || active === true) {
      where.push(`coalesce(is_active,true) = true`);
    } else if (active === 'false' || active === false) {
      where.push(`coalesce(is_active,true) = false`);
    }

    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.profiles ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select id, email, full_name, phone, role, avatar_url,
              coalesce(is_active,true) as is_active,
              disabled_reason, created_at, updated_at, last_seen_at
       from public.profiles
       ${whereSql}
       order by created_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );

    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async updateUser(actorId, userId, patch, ip) {
    await this.assertAdmin(actorId);
    const allowed = {};
    if (patch.full_name != null) allowed.full_name = patch.full_name;
    if (patch.phone != null) allowed.phone = patch.phone;
    if (patch.role != null) {
      if (!['patient', 'pharmacist', 'courier', 'admin'].includes(patch.role)) {
        const err = new Error('INVALID_ROLE');
        err.code = 'INVALID_ROLE';
        throw err;
      }
      allowed.role = patch.role;
    }
    if (patch.is_active != null) {
      allowed.is_active = !!patch.is_active;
      if (!patch.is_active) allowed.disabled_reason = patch.disabled_reason || null;
      else allowed.disabled_reason = null;
    }

    const keys = Object.keys(allowed);
    if (!keys.length) return { ok: true, unchanged: true };

    const sets = keys.map((k, i) => `${k} = $${i + 2}`);
    sets.push('updated_at = now()');
    const values = keys.map((k) => allowed[k]);
    await getPool().query(
      `update public.profiles set ${sets.join(', ')} where id = $1`,
      [userId, ...values],
    );

    // Suspension / réactivation : ban Auth pour empêcher toute session active
    if (Object.prototype.hasOwnProperty.call(allowed, 'is_active')) {
      try {
        const sb = getServiceSupabase();
        if (allowed.is_active === false) {
          await sb.auth.admin.updateUserById(userId, {
            ban_duration: '876000h',
          });
        } else {
          await sb.auth.admin.updateUserById(userId, {
            ban_duration: 'none',
          });
        }
      } catch (_) {
        /* service role optionnel — is_active reste la source de vérité app */
      }
    }

    await writeAudit(null, {
      actorId,
      action: 'UPDATE_USER',
      resourceType: 'profile',
      resourceId: userId,
      meta: allowed,
      ip,
    });
    return { ok: true };
  }

  /** Suppression réelle (profil + auth.users) — jamais soft-delete. */
  async deleteUser(actorId, userId, ip) {
    await this.assertAdmin(actorId);
    if (actorId === userId) {
      const err = new Error('CANNOT_DELETE_SELF');
      err.code = 'CANNOT_DELETE_SELF';
      throw err;
    }

    const { rows } = await getPool().query(
      `select id, email, role from public.profiles where id = $1`,
      [userId],
    );
    const target = rows[0];
    if (!target) {
      const err = new Error('NOT_FOUND');
      err.code = 'NOT_FOUND';
      throw err;
    }
    if (
      String(target.email || '').trim().toLowerCase() === 'nicodevnico@gmail.com'
    ) {
      const err = new Error('SUPER_ADMIN_PROTECTED');
      err.code = 'SUPER_ADMIN_PROTECTED';
      throw err;
    }

    // 1) Auth Admin API (hard delete)
    let authDeleted = false;
    try {
      const sb = getServiceSupabase();
      const { error } = await sb.auth.admin.deleteUser(userId);
      if (!error) authDeleted = true;
    } catch (_) {
      authDeleted = false;
    }

    // 2) Profil + auth.users via SQL (si Auth API indispo ou profil orphelin)
    await getPool().query(`delete from public.profiles where id = $1`, [userId]);
    if (!authDeleted) {
      try {
        await getPool().query(`delete from auth.users where id = $1`, [userId]);
      } catch (_) {
        /* rôle DB peut ne pas avoir accès à auth.users */
      }
    }

    await writeAudit(null, {
      actorId,
      action: 'DELETE_USER',
      resourceType: 'profile',
      resourceId: userId,
      meta: { email: target.email, hard: true, via_auth_api: authDeleted },
      ip,
    });
    return { ok: true, deleted: userId };
  }

  async getUserDetail(actorId, userId) {
    await this.assertAdmin(actorId);
    const { rows } = await getPool().query(
      `select * from public.profiles where id = $1`,
      [userId],
    );
    if (!rows[0]) {
      const err = new Error('NOT_FOUND');
      err.code = 'NOT_FOUND';
      throw err;
    }
    const orders = await getPool().query(
      `select id, public_code, status, pharmacy_name, subtotal_xaf, created_at
       from public.orders where user_id = $1
       order by created_at desc limit 20`,
      [userId],
    );
    const searches = await getPool().query(
      `select query, created_at from public.search_history
       where user_id = $1 order by created_at desc limit 15`,
      [userId],
    ).catch(() => ({ rows: [] }));

    return {
      ok: true,
      user: rows[0],
      recentOrders: orders.rows,
      recentSearches: searches.rows,
    };
  }

  async listPharmacies(actorId, {
    q, status, page = 1, pageSize = 20,
  } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = ['is_platform = true'];

    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(
        `(name ilike $${params.length} or city ilike $${params.length} or address ilike $${params.length})`,
      );
    }
    if (status) {
      params.push(status);
      where.push(`coalesce(platform_status,'VERIFIED') = $${params.length}`);
    }

    const whereSql = `where ${where.join(' and ')}`;
    const countRes = await getPool().query(
      `select count(*)::int as n from public.pharmacies ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select id, name, address, city, latitude, longitude, phone, email,
              is_open, is_duty, is_verified, is_platform, owner_user_id,
              coalesce(platform_status,'VERIFIED') as platform_status,
              coalesce(is_active,true) as is_active,
              rejection_reason, verified_at, opening_hours, services,
              created_at
       from public.pharmacies
       ${whereSql}
       order by created_at desc nulls last, name
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async upsertPharmacy(actorId, data, ip) {
    await this.assertAdmin(actorId);
    const id = data.id || `plat-${Date.now()}-${Math.abs(hashCode(data.name || 'p'))}`;
    const lat = data.latitude != null && data.latitude !== ''
      ? Number(data.latitude)
      : 4.0511; // Douala défaut
    const lng = data.longitude != null && data.longitude !== ''
      ? Number(data.longitude)
      : 9.7679;

    await getPool().query(
      `insert into public.pharmacies (
        id, name, address, city, latitude, longitude, phone, email,
        is_duty, is_open, is_verified, is_platform, services,
        platform_status, is_active, opening_hours, owner_user_id, registered_by
      ) values (
        $1,$2,$3,$4,$5,$6,$7,$8,
        $9,$10,$11,true,$12,
        $13,$14,$15::jsonb,$16,$17
      )
      on conflict (id) do update set
        name = excluded.name,
        address = excluded.address,
        city = excluded.city,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        phone = excluded.phone,
        email = excluded.email,
        is_duty = excluded.is_duty,
        is_open = excluded.is_open,
        is_verified = excluded.is_verified,
        services = excluded.services,
        platform_status = excluded.platform_status,
        is_active = excluded.is_active,
        opening_hours = excluded.opening_hours,
        owner_user_id = coalesce(excluded.owner_user_id, public.pharmacies.owner_user_id)`,
      [
        id,
        String(data.name || '').trim(),
        data.address || null,
        data.city || null,
        lat,
        lng,
        data.phone || null,
        data.email || null,
        !!data.is_duty,
        data.is_open !== false,
        data.platform_status === 'VERIFIED',
        data.services || ['Livraison'],
        data.platform_status || 'VERIFIED',
        data.is_active !== false,
        JSON.stringify(data.opening_hours || {}),
        data.owner_user_id || null,
        actorId,
      ],
    );

    await writeAudit(null, {
      actorId,
      action: data.id ? 'UPDATE_PHARMACY' : 'CREATE_PHARMACY',
      resourceType: 'pharmacy',
      resourceId: id,
      meta: { name: data.name, latitude: lat, longitude: lng },
      ip,
    });

    return { ok: true, id };
  }

  async updatePharmacyLocation(actorId, pharmacyId, { latitude, longitude }, ip) {
    await this.assertAdmin(actorId);
    await getPool().query(
      `update public.pharmacies
       set latitude = $2, longitude = $3
       where id = $1 and is_platform = true`,
      [pharmacyId, Number(latitude), Number(longitude)],
    );
    await writeAudit(null, {
      actorId,
      action: 'UPDATE_PHARMACY_LOCATION',
      resourceType: 'pharmacy',
      resourceId: pharmacyId,
      meta: { latitude, longitude },
      ip,
    });
    return { ok: true };
  }

  async setPharmacyStatus(actorId, pharmacyId, status, reason, ip) {
    await this.assertAdmin(actorId);
    if (!['PENDING', 'VERIFIED', 'REJECTED', 'SUSPENDED'].includes(status)) {
      const err = new Error('INVALID_STATUS');
      err.code = 'INVALID_STATUS';
      throw err;
    }
    await getPool().query(
      `update public.pharmacies set
        platform_status = $2,
        is_verified = ($2 = 'VERIFIED'),
        is_active = case when $2 in ('REJECTED','SUSPENDED') then false else coalesce(is_active,true) end,
        rejection_reason = case when $2 = 'REJECTED' then $3 else null end,
        verified_at = case when $2 = 'VERIFIED' then now() else verified_at end,
        verified_by = case when $2 = 'VERIFIED' then $4 else verified_by end
       where id = $1`,
      [pharmacyId, status, reason || null, actorId],
    );
    await writeAudit(null, {
      actorId,
      action: 'SET_PHARMACY_STATUS',
      resourceType: 'pharmacy',
      resourceId: pharmacyId,
      meta: { status, reason },
      ip,
    });
    return { ok: true };
  }

  async deletePharmacy(actorId, pharmacyId, ip) {
    await this.assertAdmin(actorId);
    await getPool().query(
      `update public.pharmacies
       set is_active = false, platform_status = 'SUSPENDED'
       where id = $1`,
      [pharmacyId],
    );
    await writeAudit(null, {
      actorId,
      action: 'DEACTIVATE_PHARMACY',
      resourceType: 'pharmacy',
      resourceId: pharmacyId,
      ip,
    });
    return { ok: true };
  }

  async pharmacyDetail(actorId, pharmacyId) {
    await this.assertAdmin(actorId);
    const { rows } = await getPool().query(
      `select * from public.pharmacies where id = $1`,
      [pharmacyId],
    );
    if (!rows[0]) {
      const err = new Error('NOT_FOUND');
      err.code = 'NOT_FOUND';
      throw err;
    }
    const stock = await getPool().query(
      `select i.*, m.name as medicine_name, m.brand, m.dosage
       from public.inventory i
       left join public.medicines m on m.id = i.medicine_id
       where i.pharmacy_id = $1
       order by i.updated_at desc limit 50`,
      [pharmacyId],
    );
    const orders = await getPool().query(
      `select id, public_code, status, subtotal_xaf, user_id, created_at
       from public.orders where pharmacy_id = $1
       order by created_at desc limit 30`,
      [pharmacyId],
    );
    return {
      ok: true,
      pharmacy: rows[0],
      stock: stock.rows,
      orders: orders.rows,
    };
  }

  async listMedicines(actorId, { q, active, page = 1, pageSize = 20 } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(
        `(name ilike $${params.length} or brand ilike $${params.length} or category ilike $${params.length} or dosage ilike $${params.length})`,
      );
    }
    if (active === 'true' || active === true) where.push(`coalesce(is_active,true)`);
    if (active === 'false' || active === false) where.push(`not coalesce(is_active,true)`);
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.medicines ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select * from public.medicines ${whereSql}
       order by name
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async upsertMedicine(actorId, data, ip) {
    await this.assertAdmin(actorId);
    let id = data.id;
    if (id) {
      await getPool().query(
        `update public.medicines set
          name = $2, brand = $3, dosage = $4, form = $5, category = $6,
          description = $7, requires_prescription = $8, price_xaf = $9,
          is_active = $10, updated_at = now()
         where id = $1`,
        [
          id,
          data.name,
          data.brand || null,
          data.dosage || null,
          data.form || null,
          data.category || null,
          data.description || null,
          !!data.requires_prescription,
          data.price_xaf || 0,
          data.is_active !== false,
        ],
      );
    } else {
      const res = await getPool().query(
        `insert into public.medicines (
          name, brand, dosage, form, category, description,
          requires_prescription, price_xaf, is_active
        ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9) returning id`,
        [
          data.name,
          data.brand || null,
          data.dosage || null,
          data.form || null,
          data.category || null,
          data.description || null,
          !!data.requires_prescription,
          data.price_xaf || 0,
          data.is_active !== false,
        ],
      );
      id = res.rows[0].id;
      // Variante 1:1
      await getPool().query(
        `insert into public.medicine_variants (
          id, medicine_id, brand, dosage, form, default_price_xaf
        ) values ($1,$1,$2,$3,$4,$5)
        on conflict (id) do nothing`,
        [id, data.brand || null, data.dosage || null, data.form || null, data.price_xaf || 0],
      ).catch(() => {});
    }
    await writeAudit(null, {
      actorId,
      action: data.id ? 'UPDATE_MEDICINE' : 'CREATE_MEDICINE',
      resourceType: 'medicine',
      resourceId: id,
      meta: { name: data.name },
      ip,
    });
    return { ok: true, id };
  }

  async listOrders(actorId, {
    q, status, page = 1, pageSize = 20,
  } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(
        `(public_code ilike $${params.length} or pharmacy_name ilike $${params.length})`,
      );
    }
    if (status) {
      params.push(status);
      where.push(`status = $${params.length}`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.orders ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select o.*,
              p.full_name as customer_name, p.email as customer_email,
              c.full_name as courier_name
       from public.orders o
       left join public.profiles p on p.id = o.user_id
       left join public.couriers c on c.id = o.courier_id
       ${whereSql.replace(/status/g, 'o.status').replace(/public_code/g, 'o.public_code').replace(/pharmacy_name/g, 'o.pharmacy_name')}
       order by o.created_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async getOrder(actorId, orderId) {
    await this.assertAdmin(actorId);
    const { rows } = await getPool().query(
      `select o.*,
              p.full_name as customer_name, p.email as customer_email, p.phone as customer_phone,
              c.full_name as courier_name, c.phone as courier_phone
       from public.orders o
       left join public.profiles p on p.id = o.user_id
       left join public.couriers c on c.id = o.courier_id
       where o.id = $1 or o.public_code = $1`,
      [orderId],
    );
    if (!rows[0]) {
      const err = new Error('NOT_FOUND');
      err.code = 'NOT_FOUND';
      throw err;
    }
    const items = await getPool().query(
      `select * from public.order_items where order_id = $1`,
      [rows[0].id],
    );
    return { ok: true, order: rows[0], items: items.rows };
  }

  async listCouriers(actorId, { q, page = 1, pageSize = 20 } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(`(full_name ilike $${params.length} or phone ilike $${params.length})`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.couriers ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select * from public.couriers ${whereSql}
       order by full_name
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async upsertCourier(actorId, data, ip) {
    await this.assertAdmin(actorId);
    let id = data.id;
    if (id) {
      await getPool().query(
        `update public.couriers set
          full_name = $2, phone = $3, is_available = $4,
          is_active = $5, user_id = coalesce($6, user_id), updated_at = now()
         where id = $1`,
        [
          id,
          data.full_name,
          data.phone,
          data.is_available !== false,
          data.is_active !== false,
          data.user_id || null,
        ],
      );
    } else {
      const res = await getPool().query(
        `insert into public.couriers (full_name, phone, is_available, is_active, user_id)
         values ($1,$2,$3,$4,$5) returning id`,
        [
          data.full_name,
          data.phone,
          data.is_available !== false,
          data.is_active !== false,
          data.user_id || null,
        ],
      );
      id = res.rows[0].id;
    }
    await writeAudit(null, {
      actorId,
      action: data.id ? 'UPDATE_COURIER' : 'CREATE_COURIER',
      resourceType: 'courier',
      resourceId: id,
      meta: { name: data.full_name },
      ip,
    });
    return { ok: true, id };
  }

  async listReports(actorId, { status, page = 1, pageSize = 20 } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (status) {
      params.push(status);
      where.push(`status = $${params.length}`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.reports ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select r.*, p.full_name as reporter_name, p.email as reporter_email
       from public.reports r
       left join public.profiles p on p.id = r.reporter_id
       ${whereSql.replace('status', 'r.status')}
       order by r.created_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async updateReport(actorId, reportId, { status, admin_notes }, ip) {
    await this.assertAdmin(actorId);
    if (status && !['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'].includes(status)) {
      const err = new Error('INVALID_STATUS');
      err.code = 'INVALID_STATUS';
      throw err;
    }
    await getPool().query(
      `update public.reports set
        status = coalesce($2, status),
        admin_notes = coalesce($3, admin_notes),
        resolved_by = case when $2 in ('RESOLVED','CLOSED') then $4 else resolved_by end,
        resolved_at = case when $2 in ('RESOLVED','CLOSED') then now() else resolved_at end,
        updated_at = now()
       where id = $1`,
      [reportId, status || null, admin_notes || null, actorId],
    );
    await writeAudit(null, {
      actorId,
      action: 'UPDATE_REPORT',
      resourceType: 'report',
      resourceId: reportId,
      meta: { status, admin_notes },
      ip,
    });
    return { ok: true };
  }

  async listSettings(actorId) {
    await this.assertAdmin(actorId);
    const { rows } = await getPool().query(
      `select key, value, label, category, updated_at from public.app_settings order by category, key`,
    );
    return { ok: true, items: rows };
  }

  async updateSetting(actorId, key, value, ip) {
    await this.assertAdmin(actorId);
    // Ne jamais accepter de clés secrètes
    const forbidden = ['secret', 'password', 'api_key', 'service_role', 'private'];
    const lower = String(key).toLowerCase();
    if (forbidden.some((f) => lower.includes(f))) {
      const err = new Error('SECRET_NOT_ALLOWED');
      err.code = 'SECRET_NOT_ALLOWED';
      throw err;
    }
    await getPool().query(
      `insert into public.app_settings (key, value, updated_at, updated_by)
       values ($1, $2::jsonb, now(), $3)
       on conflict (key) do update set
         value = excluded.value,
         updated_at = now(),
         updated_by = excluded.updated_by`,
      [key, JSON.stringify(value), actorId],
    );
    await writeAudit(null, {
      actorId,
      action: 'UPDATE_SETTING',
      resourceType: 'setting',
      resourceId: key,
      meta: { value },
      ip,
    });
    return { ok: true };
  }

  async listAuditLogs(actorId, { page = 1, pageSize = 30, q, resourceType, action } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 30, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(
        `(a.action ilike $${params.length} or a.resource_type ilike $${params.length} or a.resource_id ilike $${params.length} or coalesce(a.meta::text,'') ilike $${params.length})`,
      );
    }
    if (resourceType && String(resourceType).trim()) {
      params.push(String(resourceType).trim());
      where.push(`a.resource_type = $${params.length}`);
    }
    if (action && String(action).trim()) {
      params.push(`%${String(action).trim()}%`);
      where.push(`a.action ilike $${params.length}`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.audit_logs a ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select a.*, p.full_name as actor_name, p.email as actor_email
       from public.audit_logs a
       left join public.profiles p on p.id = a.actor_id
       ${whereSql}
       order by a.created_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }

  async updateOrderStatus(actorId, orderId, status, ip) {
    await this.assertAdmin(actorId);
    if (!status) {
      const err = new Error('STATUS_REQUIRED');
      err.code = 'BAD_REQUEST';
      throw err;
    }
    await getPool().query(
      `update public.orders set status = $2, updated_at = now() where id = $1`,
      [orderId, status],
    );
    await writeAudit(null, {
      actorId,
      action: 'UPDATE_ORDER_STATUS',
      resourceType: 'order',
      resourceId: orderId,
      meta: { status },
      ip,
    });
    return { ok: true };
  }

  async updateStock(actorId, inventoryId, patch, ip) {
    await this.assertAdmin(actorId);
    const sets = [];
    const params = [inventoryId];
    if (patch.quantity != null) {
      params.push(Number(patch.quantity));
      sets.push(`quantity = $${params.length}`);
    }
    if (patch.status) {
      params.push(String(patch.status));
      sets.push(`status = $${params.length}`);
    }
    if (patch.price_xaf != null) {
      params.push(Number(patch.price_xaf));
      sets.push(`price_xaf = $${params.length}`);
    }
    if (!sets.length) {
      const err = new Error('NO_PATCH');
      err.code = 'BAD_REQUEST';
      throw err;
    }
    sets.push(`updated_at = now()`);
    sets.push(`source = 'admin_manual'`);
    await getPool().query(
      `update public.inventory set ${sets.join(', ')} where id = $1`,
      params,
    );
    await writeAudit(null, {
      actorId,
      action: 'UPDATE_STOCK',
      resourceType: 'inventory',
      resourceId: inventoryId,
      meta: patch,
      ip,
    });
    return { ok: true };
  }

  async listStocks(actorId, { pharmacyId, status, page = 1, pageSize = 30 } = {}) {
    await this.assertAdmin(actorId);
    const limit = Math.min(Math.max(Number(pageSize) || 30, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    const params = [];
    const where = [];
    if (pharmacyId) {
      params.push(pharmacyId);
      where.push(`i.pharmacy_id = $${params.length}`);
    }
    if (status) {
      params.push(status);
      where.push(`i.status = $${params.length}`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.inventory i ${whereSql}`,
      params,
    );
    params.push(limit, offset);
    const { rows } = await getPool().query(
      `select i.*, m.name as medicine_name, ph.name as pharmacy_name
       from public.inventory i
       left join public.medicines m on m.id = i.medicine_id
       left join public.pharmacies ph on ph.id = i.pharmacy_id
       ${whereSql}
       order by i.updated_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return {
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    };
  }
}

function hashCode(str) {
  let h = 0;
  for (let i = 0; i < str.length; i += 1) {
    h = (Math.imul(31, h) + str.charCodeAt(i)) | 0;
  }
  return h;
}

module.exports = new AdminService();
module.exports.writeAudit = writeAudit;
