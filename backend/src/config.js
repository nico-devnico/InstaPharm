require('dotenv').config();

const num = (v, fallback) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

module.exports = {
  port: num(process.env.PORT, 3001),
  nodeEnv: process.env.NODE_ENV || 'development',
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseAnonKey: process.env.SUPABASE_ANON_KEY,
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  databaseUrl: process.env.DATABASE_URL,
  corsOrigins: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()),
  stockStaleMinutesManual: num(process.env.STOCK_STALE_MINUTES_MANUAL, 1440),
  stockStaleMinutesSync: num(process.env.STOCK_STALE_MINUTES_SYNC, 360),
  stockReservationMinutes: num(process.env.STOCK_RESERVATION_MINUTES, 20),
};
