# Système de stock InstaPharm

## Déploiement SQL (ordre)

1. `schema.sql`
2. `platform_pharmacies.sql`
3. **`stock_system.sql`** ← variants, réservations atomiques, recherche centrale, sync

## Modèle

```
Medicine
   └── MedicineVariant   (dosage, forme, marque)
          └── inventory (= PharmacyInventory)
                 quantity, reserved_quantity, unit_price_xaf,
                 status, stock_source, last_updated, last_synced_at
```

### `stock_source`

- `MANUAL`
- `API`
- `IMPORT_CSV`
- `POS_INTEGRATION`

### Statuts

- `available` / `low_stock` / `out_of_stock` / `unknown`
- **`unknown` n’est jamais traité comme disponible** (recherche, réservation, affichage)

## RPC transactionnelles

| Fonction | Rôle |
|----------|------|
| `reserve_stock` | Verrou `FOR UPDATE`, refuse survente / UNKNOWN |
| `release_stock_reservation` / `release_order_reservations` | Annulation |
| `confirm_stock_reservation` / `confirm_order_reservations` | Déduction définitive |
| `expire_stale_reservations` | Libération auto des holds expirés |
| `place_order_with_stock` | Commande + réservation atomique |
| `upsert_pharmacy_stock` | Upsert manuel / sync avec source tracée |
| `search_medicine_stock` | Recherche centralisée multi-pharmacies |

Les triggers sur `orders.status` libèrent le stock à l’annulation et confirment à la préparation.

## Backend Node

Voir `backend/README.md` — adaptateurs + API REST pour sync future.
