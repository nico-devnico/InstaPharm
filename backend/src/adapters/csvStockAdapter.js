const BaseStockAdapter = require('./baseStockAdapter');

/**
 * Import CSV — payload.text = contenu CSV, ou payload.rows = lignes déjà parsées.
 * Colonnes attendues (en-têtes souples) :
 * medicine_variant_id|sku|barcode, quantity|qty, price|prix, status, name, brand, dosage, form
 */
class CsvStockAdapter extends BaseStockAdapter {
  get source() {
    return 'IMPORT_CSV';
  }

  async normalize(payload) {
    let rows = payload?.rows;
    if (!rows && payload?.text) {
      rows = parseCsv(payload.text);
    }
    if (!rows) {
      const err = new Error('CSV_PAYLOAD_REQUIRED');
      err.code = 'CSV_PAYLOAD_REQUIRED';
      throw err;
    }

    return this.validate(
      rows.map((row) => ({
        medicineVariantId: pick(row, ['medicine_variant_id', 'variant_id', 'medicine_id', 'id']),
        externalRef: pick(row, ['sku', 'barcode', 'external_ref', 'code']),
        quantity: Number(pick(row, ['quantity', 'qty', 'stock', 'qte']) ?? 0),
        price: numOrUndef(pick(row, ['price', 'prix', 'unit_price', 'unit_price_xaf'])),
        stockStatus: mapStatus(pick(row, ['status', 'stock_status', 'disponibilite'])),
        name: pick(row, ['name', 'nom', 'medicine_name']),
        brand: pick(row, ['brand', 'marque']),
        dosage: pick(row, ['dosage', 'dose']),
        form: pick(row, ['form', 'forme']),
        syncedAt: new Date().toISOString(),
      })),
    );
  }
}

function parseCsv(text) {
  const lines = String(text).replace(/^\uFEFF/, '').split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) return [];
  const headers = splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase());
  return lines.slice(1).map((line) => {
    const cols = splitCsvLine(line);
    const obj = {};
    headers.forEach((h, i) => {
      obj[h] = (cols[i] || '').trim();
    });
    return obj;
  });
}

function splitCsvLine(line) {
  const result = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if ((ch === ',' || ch === ';') && !inQuotes) {
      result.push(cur);
      cur = '';
    } else {
      cur += ch;
    }
  }
  result.push(cur);
  return result;
}

function pick(row, keys) {
  for (const k of keys) {
    if (row[k] != null && row[k] !== '') return row[k];
  }
  return undefined;
}

function numOrUndef(v) {
  if (v == null || v === '') return undefined;
  const n = Number(String(v).replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : undefined;
}

function mapStatus(v) {
  if (v == null || v === '') return undefined;
  const s = String(v).toLowerCase();
  if (['available', 'disponible', 'ok'].includes(s)) return 'available';
  if (['low_stock', 'faible', 'low'].includes(s)) return 'low_stock';
  if (['out_of_stock', 'rupture', 'out'].includes(s)) return 'out_of_stock';
  return 'unknown';
}

module.exports = CsvStockAdapter;
