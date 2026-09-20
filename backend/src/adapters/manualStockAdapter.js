const BaseStockAdapter = require('./baseStockAdapter');

/**
 * Saisie manuelle depuis l'espace pharmacien.
 * Payload attendu :
 * {
 *   items: [{ medicineVariantId, quantity, price, stockStatus?, lowStockThreshold? }]
 * }
 */
class ManualStockAdapter extends BaseStockAdapter {
  get source() {
    return 'MANUAL';
  }

  async normalize(payload) {
    const items = payload?.items || (Array.isArray(payload) ? payload : [payload]);
    return this.validate(
      items.map((item) => ({
        medicineVariantId: item.medicineVariantId || item.medicine_variant_id || item.medicineId,
        quantity: Number(item.quantity),
        price: item.price != null ? Number(item.price) : (item.unit_price_xaf != null ? Number(item.unit_price_xaf) : undefined),
        stockStatus: normalizeStatus(item.stockStatus || item.stock_status || item.status),
        lowStockThreshold: item.lowStockThreshold ?? item.low_stock_threshold,
        externalRef: item.externalRef || item.external_ref,
        name: item.name,
        brand: item.brand,
        dosage: item.dosage,
        form: item.form,
      })),
    );
  }
}

function normalizeStatus(status) {
  if (!status) return undefined;
  const s = String(status).toLowerCase().replace(/-/g, '_');
  const map = {
    available: 'available',
    low_stock: 'low_stock',
    out_of_stock: 'out_of_stock',
    unknown: 'unknown',
    available_status: 'available',
  };
  return map[s] || (['available', 'low_stock', 'out_of_stock', 'unknown'].includes(s) ? s : 'unknown');
}

module.exports = ManualStockAdapter;
