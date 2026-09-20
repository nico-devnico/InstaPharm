const { getPool, withTransaction } = require('../db');
const config = require('../config');

/**
 * Réservations transactionnelles.
 * Les quantités de réservation sont TOUJOURS relues / verrouillées en base —
 * jamais prises telles quelles depuis le frontend.
 */
class ReservationService {
  /**
   * Réserve une ligne de stock (FOR UPDATE via RPC SQL).
   */
  async reserve({ pharmacyId, medicineVariantId, quantity, orderId = null }) {
    const qty = Number(quantity);
    if (!pharmacyId || !medicineVariantId || !Number.isFinite(qty) || qty <= 0) {
      const err = new Error('INVALID_RESERVE_PARAMS');
      err.code = 'INVALID_RESERVE_PARAMS';
      throw err;
    }

    // Ne jamais faire confiance à une "quantité disponible" envoyée par le client :
    // on ne passe que la quantité DEMANDÉE ; la dispo est calculée côté SQL.
    const { rows } = await getPool().query(
      `select public.reserve_stock($1, $2::uuid, $3::int, $4::uuid, $5::int) as result`,
      [
        pharmacyId,
        medicineVariantId,
        qty,
        orderId,
        config.stockReservationMinutes,
      ],
    );

    const result = rows[0]?.result;
    if (!result?.ok) {
      const err = new Error(result?.error || 'RESERVE_FAILED');
      err.code = result?.error || 'RESERVE_FAILED';
      err.details = result;
      throw err;
    }
    return result;
  }

  async release(reservationId) {
    const { rows } = await getPool().query(
      `select public.release_stock_reservation($1::uuid) as result`,
      [reservationId],
    );
    return rows[0]?.result;
  }

  async releaseOrder(orderId) {
    const { rows } = await getPool().query(
      `select public.release_order_reservations($1::uuid) as result`,
      [orderId],
    );
    return rows[0]?.result;
  }

  async confirmOrder(orderId) {
    const { rows } = await getPool().query(
      `select public.confirm_order_reservations($1::uuid) as result`,
      [orderId],
    );
    return rows[0]?.result;
  }

  async expireStale() {
    const { rows } = await getPool().query(
      `select public.expire_stale_reservations() as result`,
    );
    return rows[0]?.result;
  }

  /**
   * Place une commande avec réservation multi-lignes atomique (RPC SQL).
   * Les prix unitaires affichés peuvent venir du client, mais la dispo est
   * revalidée en base ; on peut aussi recharger le prix depuis inventory.
   */
  async placeOrder({
    pharmacyId,
    pharmacyName,
    fulfillment,
    paymentMethod,
    items,
    notes,
    hasPrescription,
    delivery,
    deliveryFeeXaf,
    userId,
  }) {
    // Recharger les prix depuis la base centrale (anti-fraude prix)
    const safeItems = [];
    for (const item of items) {
      const variantId = item.medicineVariantId || item.medicine_id || item.medicineId;
      const qty = Number(item.quantity);
      if (!variantId || !Number.isFinite(qty) || qty <= 0) {
        const err = new Error('INVALID_ITEM');
        err.code = 'INVALID_ITEM';
        throw err;
      }

      const { rows } = await getPool().query(
        `select unit_price_xaf, status, quantity, reserved_quantity
         from public.inventory
         where pharmacy_id = $1
           and (medicine_variant_id = $2::uuid or medicine_id = $2::uuid)
         limit 1`,
        [pharmacyId, variantId],
      );
      const inv = rows[0];
      if (!inv) {
        const err = new Error('ITEM_NOT_IN_STOCK');
        err.code = 'ITEM_NOT_IN_STOCK';
        err.variantId = variantId;
        throw err;
      }
      if (inv.status === 'unknown') {
        const err = new Error('UNKNOWN_STOCK');
        err.code = 'UNKNOWN_STOCK';
        throw err;
      }

      safeItems.push({
        medicine_variant_id: variantId,
        medicine_id: variantId,
        medicine_name: item.medicineName || item.medicine_name || 'Médicament',
        brand: item.brand || null,
        dosage: item.dosage || null,
        quantity: qty,
        unit_price_xaf: inv.unit_price_xaf ?? item.unitPriceXaf ?? 0,
        requires_prescription: !!item.requiresPrescription,
      });
    }

    // place_order_with_stock utilise auth.uid() — on passe via set_config en transaction
    return withTransaction(async (client) => {
      await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId]);
      // Fallback : certaines installs lisent auth.uid() via jwt claims JSON
      await client.query(
        `select set_config('request.jwt.claims', $1, true)`,
        [JSON.stringify({ sub: userId, role: 'authenticated' })],
      );

      // Appel direct des étapes si auth.uid() n'est pas disponible hors PostgREST
      const publicCode = `CMD-${Date.now() % 1000000}`;
      const deliveryJson = delivery || null;

      const orderInsert = await client.query(
        `insert into public.orders (
          public_code, user_id, pharmacy_id, pharmacy_name,
          fulfillment, payment_method, status,
          subtotal_xaf, delivery_fee_xaf, notes, has_prescription,
          recipient_name, recipient_phone, delivery_city, delivery_neighborhood,
          delivery_address, dest_lat, dest_lng, from_live_gps, eta_minutes
        ) values (
          $1,$2,$3,$4,$5,$6,'pending',0,$7,$8,$9,
          $10,$11,$12,$13,$14,$15,$16,$17,$18
        ) returning id, public_code`,
        [
          publicCode,
          userId,
          pharmacyId,
          pharmacyName,
          fulfillment,
          paymentMethod,
          deliveryFeeXaf || 0,
          notes || null,
          !!hasPrescription,
          deliveryJson?.recipientName || deliveryJson?.recipient_name || null,
          deliveryJson?.phone || null,
          deliveryJson?.city || null,
          deliveryJson?.neighborhood || null,
          deliveryJson?.address || deliveryJson?.addressDetail || null,
          deliveryJson?.destLat || deliveryJson?.dest_lat || null,
          deliveryJson?.destLng || deliveryJson?.dest_lng || null,
          !!(deliveryJson?.fromLiveGps || deliveryJson?.from_live_gps),
          deliveryJson?.estimatedMinutes || deliveryJson?.eta_minutes || null,
        ],
      );

      const orderId = orderInsert.rows[0].id;
      const reservedIds = [];
      let subtotal = 0;

      try {
        for (const item of safeItems) {
          const reserve = await client.query(
            `select public.reserve_stock($1, $2::uuid, $3::int, $4::uuid, $5::int) as result`,
            [
              pharmacyId,
              item.medicine_variant_id,
              item.quantity,
              orderId,
              config.stockReservationMinutes,
            ],
          );
          const result = reserve.rows[0].result;
          if (!result?.ok) {
            const err = new Error(result?.error || 'RESERVE_FAILED');
            err.code = result?.error || 'RESERVE_FAILED';
            err.details = result;
            throw err;
          }
          reservedIds.push(result.reservation_id);
          subtotal += item.unit_price_xaf * item.quantity;

          await client.query(
            `insert into public.order_items (
              order_id, medicine_id, medicine_name, brand, dosage,
              quantity, unit_price_xaf, requires_prescription
            ) values ($1,$2,$3,$4,$5,$6,$7,$8)`,
            [
              orderId,
              String(item.medicine_id),
              item.medicine_name,
              item.brand,
              item.dosage,
              item.quantity,
              item.unit_price_xaf,
              item.requires_prescription,
            ],
          );
        }

        await client.query(
          `update public.orders
           set subtotal_xaf = $1, status = 'confirmed', updated_at = now()
           where id = $2`,
          [subtotal, orderId],
        );

        return {
          ok: true,
          orderId,
          publicCode: orderInsert.rows[0].public_code,
          subtotalXaf: subtotal,
          reservationIds: reservedIds,
        };
      } catch (err) {
        for (const rid of reservedIds) {
          await client.query(
            `select public.release_stock_reservation($1::uuid)`,
            [rid],
          );
        }
        await client.query(`delete from public.orders where id = $1`, [orderId]);
        throw err;
      }
    });
  }
}

module.exports = new ReservationService();
