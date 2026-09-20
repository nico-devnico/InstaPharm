const BaseStockAdapter = require('./baseStockAdapter');

/**
 * Synchronisation depuis une API tierce (logiciel pharmacie).
 * Payload flexible — mapping configurable via payload.mapping.
 */
class ApiStockAdapter extends BaseStockAdapter {
  get source() {
    return 'API';
  }

  async normalize(payload) {
    const mapping = {
      id: 'id',
      externalRef: 'external_ref',
      quantity: 'quantity',
      price: 'price',
      status: 'status',
      name: 'name',
      brand: 'brand',
      dosage: 'dosage',
      form: 'form',
      ...(payload?.mapping || {}),
    };

    const list = payload?.products || payload?.items || payload?.data || [];
    const syncedAt = payload?.syncedAt || payload?.synced_at || new Date().toISOString();

    return this.validate(
      list.map((raw) => {
        const statusRaw = getPath(raw, mapping.status);
        return {
          medicineVariantId: getPath(raw, mapping.id),
          externalRef: getPath(raw, mapping.externalRef) || getPath(raw, mapping.id),
          quantity: Number(getPath(raw, mapping.quantity) ?? 0),
          price: numOrUndef(getPath(raw, mapping.price)),
          stockStatus: mapExternalStatus(statusRaw),
          name: getPath(raw, mapping.name),
          brand: getPath(raw, mapping.brand),
          dosage: getPath(raw, mapping.dosage),
          form: getPath(raw, mapping.form),
          syncedAt,
        };
      }),
    );
  }
}

function getPath(obj, path) {
  if (!path || obj == null) return undefined;
  return String(path).split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), obj);
}

function numOrUndef(v) {
  if (v == null || v === '') return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

function mapExternalStatus(v) {
  if (v == null || v === '') return undefined;
  const s = String(v).toLowerCase();
  if (['available', 'in_stock', 'ok', '1', 'true'].includes(s)) return 'available';
  if (['low', 'low_stock', 'faible'].includes(s)) return 'low_stock';
  if (['out', 'out_of_stock', 'rupture', '0', 'false'].includes(s)) return 'out_of_stock';
  return 'unknown';
}

module.exports = ApiStockAdapter;
