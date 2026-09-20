const { createClient } = require('@supabase/supabase-js');
const config = require('../config');

/**
 * Authentifie via JWT Supabase (Authorization: Bearer …).
 * Attache req.user = { id, email, role } et req.accessToken.
 */
async function requireAuth(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) {
      return res.status(401).json({ ok: false, error: 'UNAUTHENTICATED' });
    }

    const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data?.user) {
      return res.status(401).json({ ok: false, error: 'INVALID_TOKEN' });
    }

    const { data: profile } = await supabase
      .from('profiles')
      .select('role, full_name, is_active')
      .eq('id', data.user.id)
      .maybeSingle();

    req.accessToken = token;
    req.user = {
      id: data.user.id,
      email: data.user.email,
      role: profile?.role || 'patient',
      fullName: profile?.full_name,
      isActive: profile?.is_active !== false,
    };
    return next();
  } catch (err) {
    return res.status(401).json({ ok: false, error: 'AUTH_FAILED', message: err.message });
  }
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ ok: false, error: 'FORBIDDEN' });
    }
    if (req.user.isActive === false) {
      return res.status(403).json({ ok: false, error: 'ACCOUNT_DISABLED' });
    }
    return next();
  };
}

module.exports = { requireAuth, requireRole };
