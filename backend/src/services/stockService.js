const { getPool, withTransaction, getServiceSupabase } = require('../db');
const { getAdapter, listSources } = require('../adapters');
const config = require('../config');

const STATUS_DISPLAY = {
  available: 'AVAILABLE',
  low_stock: 'LOW_STOCK',
  out_of_stock: 'OUT_OF_STOCK',
  unknown: 'UNKNOWN',
};

/**
 * Cœur métier stock — indépendant de la source (adaptateurs).
 * Toute lecture/écriture passe par la base centrale PostgreSQL.
 */
class StockService {
  listSources() {
    return listSources();
  }

  /**
   * Applique une mise à jour via l'adaptateur de la source donnée.
   * Ne fait jamais confiance à une quantité "client" pour une réservation :
   * cette méthode est réservée aux mises à jour de catalogue pharmacie.
   */
  async applySync({ pharmacyId, source = 'MANUAL', payload, actorId = null }) {
    if (!pharmacyId) {
      const err = new Error('PHARMACY_ID_REQUIRED');
      err.code = 'PHARMACY_ID_REQUIRED';
      throw err;
    }

    const adapter = getAdapter(source);
    const rows = await adapter.normalize(payload);
    const results = [];

    for (const row of rows) {
      let variantId = row.medicineVariantId;

      // Résolution par référence externe si pas d'id plateforme
      if (!variantId && row.externalRef) {
        variantId = await this.resolveVariantByExternalRef(pharmacyId, row.externalRef);
      }

      if (!variantId && row.name) {
        variantId = await this.ensureVariantFromProduct(row);
      }

      if (!variantId) {
        results.push({ ok: false, error: 'VARIANT_NOT_RESOLVED', row });
        continue;
      }

      let quantity = Number(row.quantity);
      if (row.quantityDelta != null) {
        const current = await this.getInventoryRow(pharmacyId, variantId);
        quantity = Math.max(0, (current?.quantity || 0) + Number(row.quantityDelta));
      }

      // UNKNOWN ne doit jamais être forcé en AVAILABLE
      let status = row.stockStatus;
      if (status && String(status).toLowerCase() === 'available' && quantity <= 0) {
        status = 'out_of_stock';
      }

      const { rows: rpcRows } = await getPool().query(
        `select public.upsert_pharmacy_stock(
          $1, $2::uuid, $3::int, $4::int, $5, $6, $7, $8::int, $9::uuid
        ) as result`,
        [
          pharmacyId,
          variantId,
          quantity,
          row.price ?? null,
          status ?? null,
          adapter.source,
          row.externalRef ?? null,
          row.lowStockThreshold ?? null,
          actorId,
        ],
      );

      results.push({ ok: true, variantId, result: rpcRows[0]?.result });
    }

    return {
      ok: true,
      source: adapter.source,
      pharmacyId,
      updated: results.filter((r) => r.ok).length,
      failed: results.filter((r) => !r.ok).length,
      results,
    };
  }

  async getInventoryRow(pharmacyId, variantId) {
    const { rows } = await getPool().query(
      `select * from public.inventory
       where pharmacy_id = $1
         and (medicine_variant_id = $2::uuid or medicine_id = $2::uuid)
       limit 1`,
      [pharmacyId, variantId],
    );
    return rows[0] || null;
  }

  async resolveVariantByExternalRef(pharmacyId, externalRef) {
    const { rows } = await getPool().query(
      `select medicine_variant_id from public.inventory
       where pharmacy_id = $1 and external_ref = $2
       limit 1`,
      [pharmacyId, String(externalRef)],
    );
    return rows[0]?.medicine_variant_id || null;
  }

  async ensureVariantFromProduct(row) {
    const supabase = getServiceSupabase();
    const name = String(row.name).trim();
    if (!name) return null;

    const { data: existing } = await supabase
      .from('medicines')
      .select('id')
      .ilike('name', name)
      .limit(1)
      .maybeSingle();

    let medicineId = existing?.id;
    if (!medicineId) {
      const { data: created, error } = await supabase
        .from('medicines')
        .insert({
          name,
          brand: row.brand || null,
          dosage: row.dosage || null,
          form: row.form || null,
          price_xaf: row.price || 0,
        })
        .select('id')
        .single();
      if (error) throw error;
      medicineId = created.id;
    }

    const { data: variant } = await supabase
      .from('medicine_variants')
      .select('id')
      .eq('medicine_id', medicineId)
      .eq('dosage', row.dosage || null)
      .eq('form', row.form || null)
      .limit(1)
      .maybeSingle();

    if (variant?.id) return variant.id;

    const { data: createdVariant, error: vErr } = await supabase
      .from('medicine_variants')
      .insert({
        medicine_id: medicineId,
        brand: row.brand || null,
        dosage: row.dosage || null,
        form: row.form || null,
        default_price_xaf: row.price || 0,
        barcode: row.externalRef || null,
      })
      .select('id')
      .single();
    if (vErr) throw vErr;
    return createdVariant.id;
  }

  /**
   * Catalogue stock d'une pharmacie (espace pro).
   */
  async listPharmacyInventory(pharmacyId, { query, statusFilter } = {}) {
    const params = [pharmacyId];
    let sql = `
      select
        i.id,
        i.pharmacy_id,
        i.medicine_id,
        i.medicine_variant_id,
        i.quantity,
        i.reserved_quantity,
        greatest(coalesce(i.quantity,0) - coalesce(i.reserved_quantity,0), 0) as available_quantity,
        i.unit_price_xaf,
        i.status,
        i.stock_source,
        i.low_stock_threshold,
        i.updated_at,
        i.last_synced_at,
        i.external_ref,
        m.name as medicine_name,
        coalesce(mv.brand, m.brand) as brand,
        coalesce(mv.dosage, m.dosage) as dosage,
        coalesce(mv.form, m.form) as form,
        m.category,
        m.requires_prescription
      from public.inventory i
      left join public.medicines m on m.id = i.medicine_id
      left join public.medicine_variants mv on mv.id = coalesce(i.medicine_variant_id, i.medicine_id)
      where i.pharmacy_id = $1
    `;

    if (statusFilter) {
      params.push(String(statusFilter).toLowerCase());
      sql += ` and i.status = $${params.length}`;
    }

    if (query && query.trim()) {
      params.push(`%${query.trim()}%`);
      sql += ` and (
        m.name ilike $${params.length}
        or coalesce(m.brand,'') ilike $${params.length}
        or coalesce(mv.brand,'') ilike $${params.length}
        or coalesce(mv.dosage,'') ilike $${params.length}
      )`;
    }

    sql += ' order by i.updated_at desc';

    const { rows } = await getPool().query(sql, params);
    return rows.map((r) => this.toInventoryDto(r));
  }

  /**
   * Recherche client — base centrale uniquement.
   */
  async searchMedicine(query, { lat = null, lng = null, limit = 40 } = {}) {
    const { rows } = await getPool().query(
      `select * from public.search_medicine_stock($1, $2, $3, $4)`,
      [query, lat, lng, limit],
    );

    return rows.map((r) => {
      const status = r.stock_status === 'unknown' ? 'unknown' : r.stock_status;
      return {
        pharmacy: {
          id: r.pharmacy_id,
          name: r.pharmacy_name,
          address: r.pharmacy_address,
          city: r.pharmacy_city,
          latitude: r.pharmacy_lat,
          longitude: r.pharmacy_lng,
          isOpen: r.pharmacy_is_open,
          isDuty: r.pharmacy_is_duty,
        },
        medicine: {
          id: r.medicine_id,
          name: r.medicine_name,
          brand: r.medicine_brand,
          dosage: r.medicine_dosage,
          form: r.medicine_form,
          variantId: r.medicine_variant_id,
        },
        inventory: {
          id: r.inventory_id,
          quantity: r.quantity,
          availableQuantity: r.available_quantity,
          // Ne jamais exposer une quantité comme dispo si UNKNOWN
          displayQuantity: status === 'unknown' ? null : r.available_quantity,
          unitPriceXaf: r.unit_price_xaf,
          stockStatus: STATUS_DISPLAY[status] || 'UNKNOWN',
          stockStatusRaw: status,
          stockSource: r.stock_source,
          lastUpdated: r.last_updated,
          lastSyncedAt: r.last_synced_at,
          isStale: r.is_stale,
          freshnessLabel: this.formatFreshness(r.last_updated, status),
        },
      };
    });
  }

  formatFreshness(lastUpdated, status) {
    const label = STATUS_DISPLAY[status] || 'UNKNOWN';
    const display =
      label === 'AVAILABLE' ? 'Disponible'
        : label === 'LOW_STOCK' ? 'Stock faible'
          : label === 'OUT_OF_STOCK' ? 'Rupture'
            : 'Disponibilité inconnue';

    if (!lastUpdated) return display;
    const diffMs = Date.now() - new Date(lastUpdated).getTime();
    const mins = Math.max(0, Math.floor(diffMs / 60000));
    let ago;
    if (mins < 1) ago = 'à l\'instant';
    else if (mins < 60) ago = `il y a ${mins} min`;
    else if (mins < 1440) ago = `il y a ${Math.floor(mins / 60)} h`;
    else ago = `il y a ${Math.floor(mins / 1440)} j`;

    return `${display} · Stock mis à jour ${ago}`;
  }

  toInventoryDto(r) {
    const available = Number(r.available_quantity ?? 0);
    const status = r.status === 'unknown' ? 'unknown' : r.status;
    return {
      id: r.id,
      pharmacyId: r.pharmacy_id,
      medicineId: r.medicine_id,
      medicineVariantId: r.medicine_variant_id,
      quantity: r.quantity,
      reservedQuantity: r.reserved_quantity,
      availableQuantity: available,
      unitPriceXaf: r.unit_price_xaf,
      stockStatus: STATUS_DISPLAY[status] || 'UNKNOWN',
      stockStatusRaw: status,
      stockSource: r.stock_source,
      lowStockThreshold: r.low_stock_threshold,
      lastUpdated: r.updated_at,
      lastSyncedAt: r.last_synced_at,
      externalRef: r.external_ref,
      isStale: this.isStale(r),
      freshnessLabel: this.formatFreshness(r.updated_at, status),
      medicine: {
        id: r.medicine_id,
        name: r.medicine_name,
        brand: r.brand,
        dosage: r.dosage,
        form: r.form,
        category: r.category,
        requiresPrescription: r.requires_prescription,
      },
    };
  }

  isStale(row) {
    const updated = row.updated_at ? new Date(row.updated_at).getTime() : 0;
    const synced = row.last_synced_at ? new Date(row.last_synced_at).getTime() : null;
    const now = Date.now();
    const manualLimit = config.stockStaleMinutesManual * 60 * 1000;
    const syncLimit = config.stockStaleMinutesSync * 60 * 1000;

    if (row.stock_source === 'MANUAL') {
      return now - updated > manualLimit;
    }
    if (!synced) return true;
    return now - synced > syncLimit;
  }

  /**
   * Vérifie que l'utilisateur possède la pharmacie.
   */
  async assertPharmacyOwner(pharmacyId, userId, role) {
    if (role === 'admin') return true;
    const { rows } = await getPool().query(
      `select id from public.pharmacies
       where id = $1 and is_platform = true and owner_user_id = $2`,
      [pharmacyId, userId],
    );
    if (!rows[0]) {
      const err = new Error('PHARMACY_FORBIDDEN');
      err.code = 'PHARMACY_FORBIDDEN';
      throw err;
    }
    return true;
  }
}

module.exports = new StockService();
