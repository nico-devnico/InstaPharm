const BaseStockAdapter = require('./baseStockAdapter');

/**
 * Intégration caisse / POS pharmacie.
 * Accepte des événements unitaires ou un snapshot de stock.
 *
 * {
 *   events: [
 *     { type: 'sale'|'restock'|'adjust', sku, delta?, quantity?, price? }
 *   ]
 * }
 */
class PosIntegrationAdapter extends BaseStockAdapter {
  get source() {
    return 'POS_INTEGRATION';
  }

  async normalize(payload) {
    const events = payload?.events || payload?.items || [];
    const syncedAt = payload?.syncedAt || new Date().toISOString();

    // Snapshot absolu prioritaire
    if (payload?.snapshot) {
      return this.validate(
        payload.snapshot.map((row) => ({
          medicineVariantId: row.medicineVariantId || row.medicine_id,
          externalRef: row.sku || row.barcode || row.external_ref,
          quantity: Number(row.quantity ?? row.qty ?? 0),
          price: row.price != null ? Number(row.price) : undefined,
          stockStatus: row.status,
          syncedAt,
        })),
      );
    }

    // Événements → quantité absolue attendue dans `quantity` si fournie,
    // sinon le StockService devra résoudre via external_ref (delta).
    return this.validate(
      events.map((ev) => ({
        medicineVariantId: ev.medicineVariantId || ev.medicine_id,
        externalRef: ev.sku || ev.barcode || ev.external_ref,
        quantity: ev.quantity != null
          ? Number(ev.quantity)
          : Number(ev.absolute_quantity ?? 0),
        quantityDelta: ev.delta != null ? Number(ev.delta) : undefined,
        price: ev.price != null ? Number(ev.price) : undefined,
        stockStatus: ev.status,
        eventType: ev.type || 'adjust',
        syncedAt,
      })),
    );
  }
}

module.exports = PosIntegrationAdapter;
