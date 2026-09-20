const express = require('express');
const reservationService = require('../services/reservationService');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

/**
 * Création commande + réservation stock atomique.
 * Les quantités disponibles ne sont PAS lues depuis le body client.
 */
router.post('/', requireAuth, async (req, res) => {
  try {
    const {
      pharmacyId,
      pharmacyName,
      fulfillment,
      paymentMethod,
      items,
      notes,
      hasPrescription,
      delivery,
      deliveryFeeXaf,
    } = req.body || {};

    if (!pharmacyId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ ok: false, error: 'INVALID_ORDER' });
    }

    const result = await reservationService.placeOrder({
      pharmacyId,
      pharmacyName: pharmacyName || 'Pharmacie',
      fulfillment: fulfillment || 'pickup',
      paymentMethod: paymentMethod || 'cash',
      items,
      notes,
      hasPrescription,
      delivery,
      deliveryFeeXaf,
      userId: req.user.id,
    });

    return res.status(201).json(result);
  } catch (err) {
    const code = err.code || 'ORDER_FAILED';
    const status = ['INSUFFICIENT_STOCK', 'OUT_OF_STOCK', 'UNKNOWN_STOCK', 'ITEM_NOT_IN_STOCK']
      .includes(code)
      ? 409
      : 400;
    return res.status(status).json({
      ok: false,
      error: code,
      message: err.message,
      details: err.details || null,
    });
  }
});

/** Libération manuelle (annulation avant confirmation) */
router.post('/:orderId/release-stock', requireAuth, async (req, res) => {
  try {
    const result = await reservationService.releaseOrder(req.params.orderId);
    return res.json(result);
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

/** Confirmation définitive du stock */
router.post('/:orderId/confirm-stock', requireAuth, async (req, res) => {
  try {
    const result = await reservationService.confirmOrder(req.params.orderId);
    return res.json(result);
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

module.exports = router;
