/**
 * Contrat commun des adaptateurs de stock.
 * Une nouvelle source = un nouvel adaptateur, sans toucher au StockService.
 *
 * Sources supportées : MANUAL | API | IMPORT_CSV | POS_INTEGRATION
 */
class BaseStockAdapter {
  /** @returns {string} */
  get source() {
    throw new Error('source() non implémenté');
  }

  /**
   * Normalise un payload externe vers le format plateforme.
   * @param {object} payload
   * @returns {Promise<Array<{
   *   medicineVariantId?: string,
   *   externalRef?: string,
   *   name?: string,
   *   brand?: string,
   *   dosage?: string,
   *   form?: string,
   *   quantity: number,
   *   price?: number,
   *   stockStatus?: string,
   *   syncedAt?: string,
   * }>>}
   */
  async normalize(payload) {
    throw new Error('normalize() non implémenté');
  }

  /**
   * Validation légère avant écriture.
   * @param {object[]} rows
   */
  validate(rows) {
    if (!Array.isArray(rows) || rows.length === 0) {
      const err = new Error('EMPTY_PAYLOAD');
      err.code = 'EMPTY_PAYLOAD';
      throw err;
    }
    for (const row of rows) {
      if (row.quantity == null || Number.isNaN(Number(row.quantity))) {
        const err = new Error('INVALID_QUANTITY');
        err.code = 'INVALID_QUANTITY';
        throw err;
      }
      if (row.stockStatus && String(row.stockStatus).toUpperCase() === 'AVAILABLE'
          && Number(row.quantity) < 0) {
        const err = new Error('INCONSISTENT_STATUS');
        err.code = 'INCONSISTENT_STATUS';
        throw err;
      }
    }
    return rows;
  }
}

module.exports = BaseStockAdapter;
