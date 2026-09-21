const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const config = require('./config');
const stockRoutes = require('./routes/stock');
const orderRoutes = require('./routes/orders');
const reservationService = require('./services/reservationService');

const app = express();

app.use(morgan(config.nodeEnv === 'production' ? 'combined' : 'dev'));
app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin || config.corsOrigins.includes('*')) return cb(null, true);
      const ok = config.corsOrigins.some((pattern) => {
        if (pattern.endsWith('*')) {
          return origin.startsWith(pattern.slice(0, -1));
        }
        return origin === pattern;
      });
      return cb(null, ok);
    },
  }),
);
app.use(express.json({ limit: '2mb' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'instapharm-stock-api',
    time: new Date().toISOString(),
  });
});

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    name: 'InstaPharm Stock API',
    architecture: {
      adapters: ['MANUAL', 'API', 'IMPORT_CSV', 'POS_INTEGRATION'],
      database: 'Supabase PostgreSQL (central)',
      geo: 'PostGIS',
    },
    endpoints: {
      search: 'GET /api/stock/search?q=',
      pharmacyStock: 'GET /api/stock/pharmacy/:id',
      updateItem: 'PUT /api/stock/pharmacy/:id/item',
      bulk: 'POST /api/stock/pharmacy/:id/bulk',
      sync: 'POST /api/stock/pharmacy/:id/sync',
      placeOrder: 'POST /api/orders',
      admin: 'GET|POST|PATCH /api/admin/* (role admin requis)',
    },
  });
});

app.use('/api/stock', stockRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/admin', require('./routes/admin'));

app.use((err, _req, res, _next) => {
  // eslint-disable-next-line no-console
  console.error(err);
  res.status(500).json({ ok: false, error: 'INTERNAL_ERROR', message: err.message });
});

const server = app.listen(config.port, () => {
  // eslint-disable-next-line no-console
  console.log(`InstaPharm stock API on :${config.port}`);
});

// Expiration périodique des réservations (toutes les 5 min)
const EXPIRE_MS = 5 * 60 * 1000;
let expireWarnOnce = false;
const expireTimer = setInterval(() => {
  reservationService.expireStale().catch((err) => {
    if (!expireWarnOnce) {
      expireWarnOnce = true;
      // eslint-disable-next-line no-console
      console.warn(
        'expire_stale_reservations:',
        err.message,
        '\n→ Vérifiez DATABASE_URL dans backend/.env (URI Pooler IPv4 depuis Supabase → Settings → Database).',
      );
    }
  });
}, EXPIRE_MS);

function shutdown() {
  clearInterval(expireTimer);
  server.close(() => process.exit(0));
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

module.exports = app;
