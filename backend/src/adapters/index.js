const ManualStockAdapter = require('./manualStockAdapter');
const ApiStockAdapter = require('./apiStockAdapter');
const CsvStockAdapter = require('./csvStockAdapter');
const PosIntegrationAdapter = require('./posIntegrationAdapter');

const adapters = {
  MANUAL: new ManualStockAdapter(),
  API: new ApiStockAdapter(),
  IMPORT_CSV: new CsvStockAdapter(),
  POS_INTEGRATION: new PosIntegrationAdapter(),
};

/**
 * @param {string} source
 * @returns {import('./baseStockAdapter')}
 */
function getAdapter(source) {
  const key = String(source || 'MANUAL').toUpperCase();
  const adapter = adapters[key];
  if (!adapter) {
    const err = new Error(`UNKNOWN_STOCK_SOURCE:${key}`);
    err.code = 'UNKNOWN_STOCK_SOURCE';
    throw err;
  }
  return adapter;
}

function listSources() {
  return Object.keys(adapters);
}

module.exports = {
  getAdapter,
  listSources,
  adapters,
};
