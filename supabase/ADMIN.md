# Administration InstaPharm

## Déploiement SQL (ordre)

1. `schema.sql`
2. `platform_pharmacies.sql`
3. `stock_system.sql`
4. **`admin_system.sql`** ← rôles, PostGIS, signalements, audit, settings, dashboard

## Devenir administrateur

### Automatique (recommandé)
Au démarrage, si **aucun** admin n’existe, l’utilisateur connecté est promu via `claim_bootstrap_admin()`.

### Manuel (SQL Editor)
```sql
update public.profiles
set role = 'admin', updated_at = now()
where lower(email) = lower('VOTRE_EMAIL@exemple.com');
```

### Profil app
« Choisir mon espace » → **Devenir administrateur** (uniquement si aucun admin).

L’auto-attribution du rôle `admin` via simple update profil est **bloquée** (trigger + API).

## Backend

```bash
cd backend
npm install
# .env : DATABASE_URL + SUPABASE_* 
npm run dev
```

Endpoints protégés : ` /api/admin/* ` — JWT + `profiles.role = admin`.

Flutter peut fonctionner sans API Node (RPC / RLS Supabase), mais l’API reste la couche de sécurité recommandée.

Dans `.env` Flutter :
```
STOCK_API_BASE_URL=http://localhost:3001
```

## Modules UI

Dashboard · Utilisateurs · Pharmacies · Carte · Médicaments · Stocks ·
Commandes · Livraisons · Livreurs · Signalements · Paramètres · Audit
