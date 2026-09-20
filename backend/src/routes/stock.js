const express = require('express');
const stockService = require('../services/stockService');
const { requireAuth, requireRole } = require('../middleware/auth');

const router = express.Router();

/** Sources d'intégration disponibles */
router.get('/sources', (_req, res) => {
  res.json({ ok: true, sources: stockService.listSources() });
});

/**
 * Recherche médicament — base centrale plateforme.
 * GET /api/stock/search?q=paracetamol&lat=&lng=
 */
router.get('/search', async (req, res) => {
  try {
    const q = String(req.query.q || req.query.query || '').trim();
    if (!q) {
      return res.status(400).json({ ok: false, error: 'QUERY_REQUIRED' });
    }
    const lat = req.query.lat != null ? Number(req.query.lat) : null;
    const lng = req.query.lng != null ? Number(req.query.lng) : null;
    const results = await stockService.searchMedicine(q, { lat, lng });
    const availableCount = results.filter(
      (r) => ['AVAILABLE', 'LOW_STOCK'].includes(r.inventory.stockStatus),
    ).length;
    return res.json({
      ok: true,
      query: q,
      totalCount: results.length,
      availableCount,
      results,
    });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err.message });
  }
});

/**
 * Catalogue stock d'une pharmacie (pharmacien propriétaire ou admin).
 */
router.get(
  '/pharmacy/:pharmacyId',
  requireAuth,
  requireRole('pharmacist', 'admin'),
  async (req, res) => {
    try {
      await stockService.assertPharmacyOwner(
        req.params.pharmacyId,
        req.user.id,
        req.user.role,
      );
      const items = await stockService.listPharmacyInventory(req.params.pharmacyId, {
        query: req.query.q,
        statusFilter: req.query.status,
      });
      const summary = {
        total: items.length,
        lowStock: items.filter((i) => i.stockStatusRaw === 'low_stock').length,
        outOfStock: items.filter((i) => i.stockStatusRaw === 'out_of_stock').length,
        unknown: items.filter((i) => i.stockStatusRaw === 'unknown').length,
        stale: items.filter((i) => i.isStale).length,
      };
      return res.json({ ok: true, summary, items });
    } catch (err) {
      const status = err.code === 'PHARMACY_FORBIDDEN' ? 403 : 500;
      return res.status(status).json({ ok: false, error: err.code || err.message });
    }
  },
);

/**
 * Mise à jour manuelle individuelle.
 * PUT /api/stock/pharmacy/:pharmacyId/item
 */
router.put(
  '/pharmacy/:pharmacyId/item',
  requireAuth,
  requireRole('pharmacist', 'admin'),
  async (req, res) => {
    try {
      await stockService.assertPharmacyOwner(
        req.params.pharmacyId,
        req.user.id,
        req.user.role,
      );
      const result = await stockService.applySync({
        pharmacyId: req.params.pharmacyId,
        source: 'MANUAL',
        payload: { items: [req.body] },
        actorId: req.user.id,
      });
      return res.json(result);
    } catch (err) {
      const status = err.code === 'PHARMACY_FORBIDDEN' ? 403 : 400;
      return res.status(status).json({ ok: false, error: err.code || err.message });
    }
  },
);

/**
 * Mise à jour en masse (préparé pour CSV / lots).
 * POST /api/stock/pharmacy/:pharmacyId/bulk
 * body: { source: 'MANUAL'|'IMPORT_CSV', items?: [], text?: string }
 */
router.post(
  '/pharmacy/:pharmacyId/bulk',
  requireAuth,
  requireRole('pharmacist', 'admin'),
  async (req, res) => {
    try {
      await stockService.assertPharmacyOwner(
        req.params.pharmacyId,
        req.user.id,
        req.user.role,
      );
      const source = req.body.source || 'MANUAL';
      const result = await stockService.applySync({
        pharmacyId: req.params.pharmacyId,
        source,
        payload: req.body,
        actorId: req.user.id,
      });
      return res.json(result);
    } catch (err) {
      const status = err.code === 'PHARMACY_FORBIDDEN' ? 403 : 400;
      return res.status(status).json({ ok: false, error: err.code || err.message });
    }
  },
);

/**
 * Sync externe (API / POS) — future intégration logiciels pharmacies.
 * POST /api/stock/pharmacy/:pharmacyId/sync
 * body: { source: 'API'|'POS_INTEGRATION'|'IMPORT_CSV', ...payload }
 */
router.post(
  '/pharmacy/:pharmacyId/sync',
  requireAuth,
  requireRole('pharmacist', 'admin'),
  async (req, res) => {
    try {
      await stockService.assertPharmacyOwner(
        req.params.pharmacyId,
        req.user.id,
        req.user.role,
      );
      const source = req.body.source || 'API';
      if (!['API', 'IMPORT_CSV', 'POS_INTEGRATION'].includes(source)) {
        return res.status(400).json({ ok: false, error: 'INVALID_SYNC_SOURCE' });
      }
      const result = await stockService.applySync({
        pharmacyId: req.params.pharmacyId,
        source,
        payload: req.body,
        actorId: req.user.id,
      });
      return res.json(result);
    } catch (err) {
      const status = err.code === 'PHARMACY_FORBIDDEN' ? 403 : 400;
      return res.status(status).json({ ok: false, error: err.code || err.message });
    }
  },
);

module.exports = router;
