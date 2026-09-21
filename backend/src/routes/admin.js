const express = require('express');
const adminService = require('../services/adminService');
const { requireAuth, requireRole } = require('../middleware/auth');

const router = express.Router();

function clientIp(req) {
  return req.headers['x-forwarded-for']?.toString().split(',')[0]?.trim()
    || req.socket?.remoteAddress
    || null;
}

function handle(err, res) {
  const code = err.code || 'ERROR';
  const status = code === 'FORBIDDEN' ? 403
    : code === 'NOT_FOUND' ? 404
      : code === 'ADMIN_EXISTS' ? 409
        : 400;
  return res.status(status).json({ ok: false, error: code, message: err.message });
}

/** Bootstrap : premier utilisateur → ADMIN (si aucun admin) */
router.post('/bootstrap', requireAuth, async (req, res) => {
  try {
    const result = await adminService.claimBootstrapAdmin(req.user.id, clientIp(req));
    return res.json(result);
  } catch (err) {
    return handle(err, res);
  }
});

/** Toutes les routes suivantes : admin uniquement (contrôle backend) */
router.use(requireAuth, requireRole('admin'));

router.get('/dashboard', async (req, res) => {
  try {
    const stats = await adminService.dashboard(req.user.id);
    return res.json(stats);
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/users', async (req, res) => {
  try {
    const data = await adminService.listUsers(req.user.id, req.query);
    return res.json(data);
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/users/:id', async (req, res) => {
  try {
    const data = await adminService.getUserDetail(req.user.id, req.params.id);
    return res.json(data);
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/users/:id', async (req, res) => {
  try {
    const data = await adminService.updateUser(
      req.user.id,
      req.params.id,
      req.body || {},
      clientIp(req),
    );
    return res.json(data);
  } catch (err) {
    return handle(err, res);
  }
});

router.delete('/users/:id', async (req, res) => {
  try {
    const data = await adminService.deleteUser(
      req.user.id,
      req.params.id,
      clientIp(req),
    );
    return res.json(data);
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/pharmacies', async (req, res) => {
  try {
    return res.json(await adminService.listPharmacies(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/pharmacies/:id', async (req, res) => {
  try {
    return res.json(await adminService.pharmacyDetail(req.user.id, req.params.id));
  } catch (err) {
    return handle(err, res);
  }
});

router.post('/pharmacies', async (req, res) => {
  try {
    return res.status(201).json(
      await adminService.upsertPharmacy(req.user.id, req.body || {}, clientIp(req)),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.put('/pharmacies/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.upsertPharmacy(
        req.user.id,
        { ...(req.body || {}), id: req.params.id },
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/pharmacies/:id/location', async (req, res) => {
  try {
    return res.json(
      await adminService.updatePharmacyLocation(
        req.user.id,
        req.params.id,
        req.body || {},
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/pharmacies/:id/status', async (req, res) => {
  try {
    return res.json(
      await adminService.setPharmacyStatus(
        req.user.id,
        req.params.id,
        req.body?.status,
        req.body?.reason,
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.delete('/pharmacies/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.deletePharmacy(req.user.id, req.params.id, clientIp(req)),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/medicines', async (req, res) => {
  try {
    return res.json(await adminService.listMedicines(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

router.post('/medicines', async (req, res) => {
  try {
    return res.status(201).json(
      await adminService.upsertMedicine(req.user.id, req.body || {}, clientIp(req)),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.put('/medicines/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.upsertMedicine(
        req.user.id,
        { ...(req.body || {}), id: req.params.id },
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/stocks', async (req, res) => {
  try {
    return res.json(await adminService.listStocks(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/orders', async (req, res) => {
  try {
    // Fix requêtes filtrées avec alias
    const { q, status, page, pageSize } = req.query;
    const limit = Math.min(Math.max(Number(pageSize) || 20, 1), 100);
    const offset = (Math.max(Number(page) || 1, 1) - 1) * limit;
    await adminService.assertAdmin(req.user.id);

    const { getPool } = require('../db');
    const params = [];
    const where = [];
    if (q && String(q).trim()) {
      params.push(`%${String(q).trim()}%`);
      where.push(`(o.public_code ilike $${params.length} or o.pharmacy_name ilike $${params.length})`);
    }
    if (status) {
      params.push(status);
      where.push(`o.status = $${params.length}`);
    }
    const whereSql = where.length ? `where ${where.join(' and ')}` : '';
    const countRes = await getPool().query(
      `select count(*)::int as n from public.orders o ${whereSql}`,
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
       ${whereSql}
       order by o.created_at desc
       limit $${params.length - 1} offset $${params.length}`,
      params,
    );
    return res.json({
      ok: true,
      total: countRes.rows[0].n,
      page: Math.max(Number(page) || 1, 1),
      pageSize: limit,
      items: rows,
    });
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/orders/:id', async (req, res) => {
  try {
    return res.json(await adminService.getOrder(req.user.id, req.params.id));
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/orders/:id/status', async (req, res) => {
  try {
    return res.json(
      await adminService.updateOrderStatus(
        req.user.id,
        req.params.id,
        req.body?.status,
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/stocks/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.updateStock(
        req.user.id,
        req.params.id,
        req.body || {},
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/couriers', async (req, res) => {
  try {
    return res.json(await adminService.listCouriers(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

router.post('/couriers', async (req, res) => {
  try {
    return res.status(201).json(
      await adminService.upsertCourier(req.user.id, req.body || {}, clientIp(req)),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.put('/couriers/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.upsertCourier(
        req.user.id,
        { ...(req.body || {}), id: req.params.id },
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/reports', async (req, res) => {
  try {
    return res.json(await adminService.listReports(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

router.patch('/reports/:id', async (req, res) => {
  try {
    return res.json(
      await adminService.updateReport(
        req.user.id,
        req.params.id,
        req.body || {},
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/settings', async (req, res) => {
  try {
    return res.json(await adminService.listSettings(req.user.id));
  } catch (err) {
    return handle(err, res);
  }
});

router.put('/settings/:key', async (req, res) => {
  try {
    return res.json(
      await adminService.updateSetting(
        req.user.id,
        req.params.key,
        req.body?.value ?? req.body,
        clientIp(req),
      ),
    );
  } catch (err) {
    return handle(err, res);
  }
});

router.get('/audit-logs', async (req, res) => {
  try {
    return res.json(await adminService.listAuditLogs(req.user.id, req.query));
  } catch (err) {
    return handle(err, res);
  }
});

module.exports = router;
