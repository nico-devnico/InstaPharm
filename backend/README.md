# InstaPharm — API Stock (Node.js)

Backend centralisé pour la gestion transactionnelle des stocks multi-pharmacies.

## Architecture

```
Pharmacie (manuel / API / CSV / POS)
        │
        ▼
   StockService ── adaptateurs
        │
   PostgreSQL (Supabase) + PostGIS
        │
   Flutter / Clients
```

### Adaptateurs

| Source | Adapter | Usage |
|--------|---------|--------|
| `MANUAL` | ManualStockAdapter | Espace pharmacien MVP |
| `API` | ApiStockAdapter | Sync logiciel pharmacie |
| `IMPORT_CSV` | CsvStockAdapter | Import fichier |
| `POS_INTEGRATION` | PosIntegrationAdapter | Caisse / POS |

Ajouter une source = nouvel adaptateur dans `src/adapters/`, sans modifier le cœur.

## Prérequis

1. Exécuter dans Supabase SQL Editor :
   - `supabase/schema.sql`
   - `supabase/platform_pharmacies.sql`
   - `supabase/stock_system.sql`
2. Copier `.env.example` → `.env` et renseigner `DATABASE_URL` + clés Supabase.

## Démarrage

```bash
cd backend
npm install
npm run dev
```

## Endpoints clés

- `GET /api/stock/search?q=paracetamol` — recherche centrale
- `GET /api/stock/pharmacy/:id` — catalogue pharmacien
- `PUT /api/stock/pharmacy/:id/item` — mise à jour unitaire
- `POST /api/stock/pharmacy/:id/bulk` — mise à jour masse / CSV
- `POST /api/stock/pharmacy/:id/sync` — sync API/POS
- `POST /api/orders` — commande + réservation atomique

Les réservations utilisent `SELECT … FOR UPDATE` via les fonctions SQL `reserve_stock` / `release_*` / `confirm_*`.
