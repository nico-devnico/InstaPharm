import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/cameroon.dart';
import '../models/coordinates.dart';
import '../models/enums.dart';
import '../models/medicine.dart';
import '../models/order.dart';
import '../models/pharmacy.dart';
import '../models/search_result.dart';
import 'audit_service.dart';
import 'routing_service.dart';
import 'supabase_service.dart';
import 'platform_pharmacy_repository.dart';

class OrderRepository {
  OrderRepository._();
  static final OrderRepository instance = OrderRepository._();

  SupabaseClient get _db => SupabaseService.client;

  String _publicCode() =>
      'CMD-${DateTime.now().millisecondsSinceEpoch % 1000000}';

  Future<void> upsertPharmacy(Pharmacy p) async {
    // Ne pas écraser une pharmacie plateforme avec un cache OSM.
    if (p.isPlatform || p.id.startsWith('plat-')) {
      await _db.from('pharmacies').upsert({
        'id': p.id,
        'name': p.name,
        'address': p.address,
        'city': p.city,
        'postal_code': p.postalCode,
        'latitude': p.coordinates?.latitude,
        'longitude': p.coordinates?.longitude,
        'phone': p.phone,
        'email': p.email,
        'website': p.website,
        'is_duty': p.isDuty ?? false,
        'is_open': p.isOpen ?? true,
        'is_verified': true,
        'is_platform': true,
        'services': p.services ?? [],
        'rating': p.rating,
        'review_count': p.reviewCount ?? 0,
        'owner_user_id': p.ownerUserId,
      });
      return;
    }
    await _db.from('pharmacies').upsert({
      'id': p.id,
      'name': p.name,
      'address': p.address,
      'city': p.city,
      'postal_code': p.postalCode,
      'latitude': p.coordinates?.latitude,
      'longitude': p.coordinates?.longitude,
      'phone': p.phone,
      'email': p.email,
      'website': p.website,
      'is_duty': p.isDuty ?? false,
      'is_open': p.isOpen ?? true,
      'is_verified': p.isVerified ?? false,
      'is_platform': false,
      'services': p.services ?? [],
      'rating': p.rating,
      'review_count': p.reviewCount ?? 0,
    });
  }

  Future<List<Medicine>> searchMedicines(String query) async {
    if (query.trim().isEmpty) {
      final rows = await _db.from('medicines').select().limit(40);
      return (rows as List)
          .map((e) => Medicine.fromJson(_medicineMap(e)))
          .toList();
    }
    final q = query.trim();
    final rows = await _db
        .from('medicines')
        .select()
        .or('name.ilike.%$q%,brand.ilike.%$q%,category.ilike.%$q%')
        .limit(30);
    return (rows as List)
        .map((e) => Medicine.fromJson(_medicineMap(e)))
        .toList();
  }

  Map<String, dynamic> _medicineMap(Map<String, dynamic> e) => {
        'id': e['id']?.toString() ?? '',
        'name': e['name'],
        'brand': e['brand'],
        'dosage': e['dosage'],
        'form': e['form'],
        'category': e['category'],
        'description': e['description'],
        'requires_prescription': e['requires_prescription'],
        'price_xaf': e['price_xaf'],
      };

  Future<SearchResults> searchMedicineNearby({
    required String query,
    required double latitude,
    required double longitude,
    List<Pharmacy>? nearbyPharmacies,
  }) {
    // Flux principal : interroge les inventaires des pharmacies enregistrées.
    return PlatformPharmacyRepository.instance.searchMedicineAcrossPharmacies(
      query: query,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<MedicineOrder> createOrder({
    required Pharmacy pharmacy,
    required List<OrderItem> items,
    required FulfillmentType fulfillment,
    required PaymentMethod paymentMethod,
    DeliveryInfo? delivery,
    String? notes,
    bool hasPrescription = false,
    bool express = false,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Connectez-vous pour commander');

    await upsertPharmacy(pharmacy);

    DeliveryInfo? deliveryInfo = delivery;
    int deliveryFee = 0;
    Map<String, dynamic>? deliveryPayload;

    if (fulfillment == FulfillmentType.delivery && deliveryInfo != null) {
      final hadGps =
          deliveryInfo.fromLiveGps || deliveryInfo.destination != null;
      final destination = deliveryInfo.destination ??
          CameroonDefaults.resolveDestination(
            city: deliveryInfo.city,
            neighborhood: deliveryInfo.neighborhood,
          );
      final from = pharmacy.coordinates ??
          Coordinates(
            latitude: CameroonDefaults.defaultLocation.latitude,
            longitude: CameroonDefaults.defaultLocation.longitude,
          );

      final route = await RoutingService.instance.getRoute(
        fromLat: from.latitude,
        fromLng: from.longitude,
        toLat: destination.latitude,
        toLng: destination.longitude,
        mode: express ? TravelMode.moto : TravelMode.driving,
      );

      String? courierName;
      String? courierPhone;
      String? courierId;
      try {
        final courier = await _db
            .from('couriers')
            .select()
            .eq('is_available', true)
            .limit(1)
            .maybeSingle();
        if (courier != null) {
          courierId = courier['id']?.toString();
          courierName = courier['full_name']?.toString();
          courierPhone = courier['phone']?.toString();
        }
      } catch (_) {}

      deliveryFee = express
          ? CameroonDefaults.expressDeliveryFeeXaf
          : CameroonDefaults.baseDeliveryFeeXaf;

      deliveryInfo = deliveryInfo.copyWith(
        courierName: courierName ?? 'Livreur InstaPharm',
        courierPhone: courierPhone,
        courierLocation: from,
        destination: destination,
        routeGeometry: route.geometry,
        routeDistanceMeters: route.distanceMeters,
        routeDurationSeconds: route.durationSeconds,
        progress: 0,
        estimatedMinutes: (route.durationSeconds / 60).ceil().clamp(5, 120),
        fromLiveGps: hadGps,
        liveEtaSeconds: route.durationSeconds,
        liveRemainingMeters: route.distanceMeters,
      );

      deliveryPayload = {
        'recipient_name': deliveryInfo.recipientName,
        'phone': deliveryInfo.phone,
        'city': deliveryInfo.city,
        'neighborhood': deliveryInfo.neighborhood,
        'address': deliveryInfo.addressDetail,
        'dest_lat': destination.latitude.toString(),
        'dest_lng': destination.longitude.toString(),
        'from_live_gps': hadGps,
        'route_geometry': deliveryInfo.routeGeometry
            .map((c) => {'lat': c.latitude, 'lng': c.longitude})
            .toList(),
        'route_distance_m': route.distanceMeters.toString(),
        'route_duration_s': route.durationSeconds.toString(),
        'eta_minutes': deliveryInfo.estimatedMinutes.toString(),
        'courier_id': courierId,
      };
    }

    // Réservation transactionnelle côté backend (RPC) — quantité revalidée en base
    try {
      final rpc = await _db.rpc('place_order_with_stock', params: {
        'p_pharmacy_id': pharmacy.id,
        'p_pharmacy_name': pharmacy.name,
        'p_fulfillment':
            fulfillment == FulfillmentType.delivery ? 'delivery' : 'pickup',
        'p_payment_method': _paymentDb(paymentMethod),
        'p_items': [
          for (final i in items)
            {
              'medicine_id': i.medicineId,
              'medicine_variant_id': i.medicineId,
              'medicine_name': i.medicineName,
              'brand': i.brand,
              'dosage': i.dosage,
              'quantity': i.quantity,
              'unit_price_xaf': i.unitPriceXaf,
              'requires_prescription': i.requiresPrescription,
            }
        ],
        'p_notes': notes,
        'p_has_prescription': hasPrescription,
        'p_delivery': deliveryPayload,
        'p_delivery_fee_xaf': deliveryFee,
      });

      final result = rpc is Map
          ? Map<String, dynamic>.from(rpc)
          : <String, dynamic>{};
      if (result['ok'] != true) {
        throw _stockOrderException(result);
      }

      final orderId = result['order_id']?.toString();
      if (orderId == null) {
        throw Exception('Commande créée sans identifiant');
      }

      // Compléter champs livraison (route / livreur) si besoin
      if (fulfillment == FulfillmentType.delivery && deliveryInfo != null) {
        await _db.from('orders').update({
          'route_geometry': deliveryInfo.routeGeometry
              .map((c) => {'lat': c.latitude, 'lng': c.longitude})
              .toList(),
          'route_distance_m': deliveryInfo.routeDistanceMeters,
          'route_duration_s': deliveryInfo.routeDurationSeconds,
          'courier_id': deliveryPayload?['courier_id'],
          'courier_lat': deliveryInfo.courierLocation?.latitude,
          'courier_lng': deliveryInfo.courierLocation?.longitude,
          'eta_minutes': deliveryInfo.estimatedMinutes,
        }).eq('id', orderId);
      }

      final row = await _db
          .from('orders')
          .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
          .eq('id', orderId)
          .single();
      await AuditService.instance.log(
        action: 'CREATE_ORDER',
        resourceType: 'order',
        resourceId: orderId,
        meta: {
          'pharmacy_id': pharmacy.id,
          'fulfillment': fulfillment.name,
          'items': items.length,
        },
      );
      return _mapOrderRow(row);
    } on PostgrestException catch (e) {
      // RPC absente tant que stock_system.sql n'est pas appliqué → fallback
      if (e.message.contains('place_order_with_stock') ||
          e.code == 'PGRST202') {
        return _createOrderLegacy(
          pharmacy: pharmacy,
          items: items,
          fulfillment: fulfillment,
          paymentMethod: paymentMethod,
          deliveryInfo: deliveryInfo,
          notes: notes,
          hasPrescription: hasPrescription,
          express: express,
          userId: user.id,
        );
      }
      rethrow;
    }
  }

  Exception _stockOrderException(Map<String, dynamic> result) {
    final code = result['error']?.toString() ?? 'ORDER_FAILED';
    switch (code) {
      case 'INSUFFICIENT_STOCK':
        final avail = result['available'];
        return Exception(
          avail != null
              ? 'Stock insuffisant (disponible : $avail).'
              : 'Stock insuffisant pour cette commande.',
        );
      case 'OUT_OF_STOCK':
        return Exception('Produit en rupture de stock.');
      case 'UNKNOWN_STOCK':
        return Exception(
          'Disponibilité inconnue — commande impossible pour ce produit.',
        );
      case 'NOT_FOUND':
        return Exception('Produit introuvable dans le stock de la pharmacie.');
      default:
        return Exception('Impossible de passer la commande ($code).');
    }
  }

  /// Ancien flux sans réservation (compat si migration SQL non appliquée).
  Future<MedicineOrder> _createOrderLegacy({
    required Pharmacy pharmacy,
    required List<OrderItem> items,
    required FulfillmentType fulfillment,
    required PaymentMethod paymentMethod,
    DeliveryInfo? deliveryInfo,
    String? notes,
    bool hasPrescription = false,
    bool express = false,
    required String userId,
  }) async {
    if (fulfillment == FulfillmentType.delivery && deliveryInfo != null) {
      final destination = deliveryInfo.destination!;
      final from = pharmacy.coordinates ??
          Coordinates(
            latitude: CameroonDefaults.defaultLocation.latitude,
            longitude: CameroonDefaults.defaultLocation.longitude,
          );
      final fee = express
          ? CameroonDefaults.expressDeliveryFeeXaf
          : CameroonDefaults.baseDeliveryFeeXaf;
      final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotalXaf);

      final orderRow = await _db
          .from('orders')
          .insert({
            'public_code': _publicCode(),
            'user_id': userId,
            'pharmacy_id': pharmacy.id,
            'pharmacy_name': pharmacy.name,
            'fulfillment': 'delivery',
            'payment_method': _paymentDb(paymentMethod),
            'status': 'confirmed',
            'subtotal_xaf': subtotal,
            'delivery_fee_xaf': fee,
            'notes': notes,
            'has_prescription': hasPrescription,
            'recipient_name': deliveryInfo.recipientName,
            'recipient_phone': deliveryInfo.phone,
            'delivery_city': deliveryInfo.city,
            'delivery_neighborhood': deliveryInfo.neighborhood,
            'delivery_address': deliveryInfo.addressDetail,
            'dest_lat': destination.latitude,
            'dest_lng': destination.longitude,
            'from_live_gps': deliveryInfo.fromLiveGps,
            'route_geometry': deliveryInfo.routeGeometry
                .map((c) => {'lat': c.latitude, 'lng': c.longitude})
                .toList(),
            'route_distance_m': deliveryInfo.routeDistanceMeters,
            'route_duration_s': deliveryInfo.routeDurationSeconds,
            'courier_lat': from.latitude,
            'courier_lng': from.longitude,
            'courier_progress': 0,
            'eta_minutes': deliveryInfo.estimatedMinutes,
          })
          .select()
          .single();

      await _insertItems(orderRow['id'].toString(), items);
      return _mapOrder(orderRow, items, pharmacy, deliveryInfo);
    }

    final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotalXaf);
    final orderRow = await _db
        .from('orders')
        .insert({
          'public_code': _publicCode(),
          'user_id': userId,
          'pharmacy_id': pharmacy.id,
          'pharmacy_name': pharmacy.name,
          'fulfillment': 'pickup',
          'payment_method': _paymentDb(paymentMethod),
          'status': 'confirmed',
          'subtotal_xaf': subtotal,
          'delivery_fee_xaf': 0,
          'notes': notes,
          'has_prescription': hasPrescription,
        })
        .select()
        .single();

    await _insertItems(orderRow['id'].toString(), items);
    return _mapOrder(orderRow, items, pharmacy, null);
  }

  Future<void> _insertItems(String orderId, List<OrderItem> items) async {
    await _db.from('order_items').insert([
      for (final i in items)
        {
          'order_id': orderId,
          'medicine_id': i.medicineId,
          'medicine_name': i.medicineName,
          'brand': i.brand,
          'dosage': i.dosage,
          'quantity': i.quantity,
          'unit_price_xaf': i.unitPriceXaf,
          'requires_prescription': i.requiresPrescription,
        }
    ]);
  }

  String _paymentDb(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.mtnMomo:
        return 'mtn_momo';
      case PaymentMethod.orangeMoney:
        return 'orange_money';
    }
  }

  Future<List<MedicineOrder>> getMyOrders() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('orders')
        .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => _mapOrderRow(e)).toList();
  }

  Future<MedicineOrder?> getOrder(String idOrCode) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    var row = await _db
        .from('orders')
        .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
        .eq('id', idOrCode)
        .eq('user_id', user.id)
        .maybeSingle();
    row ??= await _db
        .from('orders')
        .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
        .eq('public_code', idOrCode)
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return _mapOrderRow(row);
  }

  Stream<List<Map<String, dynamic>>> watchMyOrders() {
    final user = _db.auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
  }

  Stream<Map<String, dynamic>> watchOrder(String orderId) {
    return _db
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first);
  }

  MedicineOrder mapOrderRowPublic(Map<String, dynamic> row) =>
      _mapOrderRow(row);

  MedicineOrder _mapOrderRow(Map<String, dynamic> row) {
    final itemsRaw = row['order_items'] as List? ?? [];
    final items = itemsRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return OrderItem(
        medicineId: m['medicine_id']?.toString() ?? '',
        medicineName: m['medicine_name']?.toString() ?? '',
        brand: m['brand']?.toString(),
        dosage: m['dosage']?.toString(),
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        unitPriceXaf: (m['unit_price_xaf'] as num?)?.toInt() ?? 0,
        requiresPrescription: m['requires_prescription'] == true,
      );
    }).toList();

    DeliveryInfo? delivery;
    String? courierName;
    String? courierPhone;
    final cJoin = row['couriers'];
    if (cJoin is Map) {
      courierName = cJoin['full_name']?.toString();
      courierPhone = cJoin['phone']?.toString();
    }

    if (row['fulfillment'] == 'delivery') {
      final geo = <Coordinates>[];
      final rawGeo = row['route_geometry'];
      if (rawGeo is List) {
        for (final g in rawGeo) {
          if (g is Map) {
            geo.add(Coordinates(
              latitude: (g['lat'] as num).toDouble(),
              longitude: (g['lng'] as num).toDouble(),
            ));
          }
        }
      } else if (rawGeo is String) {
        try {
          final decoded = jsonDecode(rawGeo);
          if (decoded is List) {
            for (final g in decoded) {
              geo.add(Coordinates(
                latitude: (g['lat'] as num).toDouble(),
                longitude: (g['lng'] as num).toDouble(),
              ));
            }
          }
        } catch (_) {}
      }

      delivery = DeliveryInfo(
        recipientName: row['recipient_name']?.toString() ?? '',
        phone: row['recipient_phone']?.toString() ?? '',
        city: row['delivery_city']?.toString() ?? '',
        neighborhood: row['delivery_neighborhood']?.toString() ?? '',
        addressDetail: row['delivery_address']?.toString() ?? '',
        courierName: courierName,
        courierPhone: courierPhone,
        destination: row['dest_lat'] != null
            ? Coordinates(
                latitude: (row['dest_lat'] as num).toDouble(),
                longitude: (row['dest_lng'] as num).toDouble(),
              )
            : null,
        courierLocation: row['courier_lat'] != null
            ? Coordinates(
                latitude: (row['courier_lat'] as num).toDouble(),
                longitude: (row['courier_lng'] as num).toDouble(),
              )
            : null,
        routeGeometry: geo,
        routeDistanceMeters: (row['route_distance_m'] as num?)?.toDouble(),
        routeDurationSeconds: (row['route_duration_s'] as num?)?.toInt(),
        progress: (row['courier_progress'] as num?)?.toDouble() ?? 0,
        estimatedMinutes: (row['eta_minutes'] as num?)?.toInt() ?? 0,
        fromLiveGps: row['from_live_gps'] == true,
        departedAt: row['departed_at'] != null
            ? DateTime.tryParse(row['departed_at'].toString())
            : null,
        liveEtaSeconds: ((row['eta_minutes'] as num?)?.toInt() ?? 0) * 60,
        liveRemainingMeters: (row['route_distance_m'] as num?)?.toDouble(),
      );
    }

    Pharmacy? pharmacy;
    final ph = row['pharmacies'];
    if (ph is Map) {
      pharmacy = _pharmacyFromRow(Map<String, dynamic>.from(ph));
    }

    return MedicineOrder(
      id: row['public_code']?.toString() ?? row['id'].toString(),
      pharmacyId: row['pharmacy_id']?.toString() ?? '',
      pharmacyName: row['pharmacy_name']?.toString() ?? '',
      pharmacy: pharmacy,
      items: items,
      fulfillment: row['fulfillment'] == 'delivery'
          ? FulfillmentType.delivery
          : FulfillmentType.pickup,
      paymentMethod: _paymentFromDb(row['payment_method']?.toString()),
      status: _statusFromDb(row['status']?.toString()),
      subtotalXaf: (row['subtotal_xaf'] as num?)?.toInt() ?? 0,
      deliveryFeeXaf: (row['delivery_fee_xaf'] as num?)?.toInt() ?? 0,
      delivery: delivery,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: row['updated_at'] != null
          ? DateTime.tryParse(row['updated_at'].toString())
          : null,
      notes: row['notes']?.toString(),
      hasPrescription: row['has_prescription'] == true,
      supabaseId: row['id']?.toString(),
      courierName: courierName ?? delivery?.courierName,
    );
  }

  MedicineOrder _mapOrder(
    Map<String, dynamic> row,
    List<OrderItem> items,
    Pharmacy pharmacy,
    DeliveryInfo? delivery,
  ) {
    // Enrich courier name from delivery info
    final d = delivery;
    return MedicineOrder(
      id: row['public_code']?.toString() ?? row['id'].toString(),
      pharmacyId: pharmacy.id,
      pharmacyName: pharmacy.name,
      pharmacy: pharmacy,
      items: items,
      fulfillment: row['fulfillment'] == 'delivery'
          ? FulfillmentType.delivery
          : FulfillmentType.pickup,
      paymentMethod: _paymentFromDb(row['payment_method']?.toString()),
      status: _statusFromDb(row['status']?.toString()),
      subtotalXaf: (row['subtotal_xaf'] as num?)?.toInt() ?? 0,
      deliveryFeeXaf: (row['delivery_fee_xaf'] as num?)?.toInt() ?? 0,
      delivery: d,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      notes: row['notes']?.toString(),
      hasPrescription: row['has_prescription'] == true,
      supabaseId: row['id']?.toString(),
      courierName: d?.courierName,
    );
  }

  PaymentMethod _paymentFromDb(String? s) {
    switch (s) {
      case 'mtn_momo':
        return PaymentMethod.mtnMomo;
      case 'orange_money':
        return PaymentMethod.orangeMoney;
      default:
        return PaymentMethod.cash;
    }
  }

  OrderStatus _statusFromDb(String? s) {
    switch (s) {
      case 'pending':
        return OrderStatus.pending;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'preparing':
        return OrderStatus.preparing;
      case 'out_for_delivery':
        return OrderStatus.outForDelivery;
      case 'ready_for_pickup':
        return OrderStatus.readyForPickup;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending;
    }
  }

  Future<bool> hasRated(String orderUuid) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;
    final row = await _db
        .from('ratings')
        .select('id')
        .eq('order_id', orderUuid)
        .eq('user_id', user.id)
        .maybeSingle();
    return row != null;
  }

  Future<void> submitRating({
    required String orderUuid,
    required int deliveryRating,
    int? courierRating,
    int? pharmacyRating,
    String? comment,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Non connecté');
    await _db.from('ratings').upsert(
      {
        'order_id': orderUuid,
        'user_id': user.id,
        'delivery_rating': deliveryRating,
        'courier_rating': courierRating,
        'pharmacy_rating': pharmacyRating,
        'comment': comment,
      },
      onConflict: 'order_id,user_id',
    );
  }

  Future<bool> isFavorite(String pharmacyId) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;
    final row = await _db
        .from('favorites')
        .select('pharmacy_id')
        .eq('user_id', user.id)
        .eq('pharmacy_id', pharmacyId)
        .maybeSingle();
    return row != null;
  }

  Future<List<Pharmacy>> getFavorites() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('favorites')
        .select('pharmacy_id, pharmacies(*)')
        .eq('user_id', user.id);
    final list = <Pharmacy>[];
    for (final row in rows as List) {
      final m = Map<String, dynamic>.from(row as Map);
      final ph = m['pharmacies'];
      if (ph is Map) {
        list.add(_pharmacyFromRow(Map<String, dynamic>.from(ph)));
      }
    }
    return list;
  }

  Future<bool> addFavorite(Pharmacy pharmacy) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;
    await upsertPharmacy(pharmacy);
    await _db.from('favorites').upsert({
      'user_id': user.id,
      'pharmacy_id': pharmacy.id,
    });
    return true;
  }

  Future<bool> addFavoriteById(String pharmacyId) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;
    await _db.from('favorites').upsert({
      'user_id': user.id,
      'pharmacy_id': pharmacyId,
    });
    return true;
  }

  Future<bool> removeFavorite(String pharmacyId) async {
    final user = _db.auth.currentUser;
    if (user == null) return false;
    await _db
        .from('favorites')
        .delete()
        .eq('user_id', user.id)
        .eq('pharmacy_id', pharmacyId);
    return true;
  }

  Pharmacy _pharmacyFromRow(Map<String, dynamic> e) {
    return Pharmacy(
      id: e['id']?.toString() ?? '',
      name: e['name']?.toString() ?? '',
      address: e['address']?.toString(),
      city: e['city']?.toString(),
      postalCode: e['postal_code']?.toString(),
      coordinates: e['latitude'] != null
          ? Coordinates(
              latitude: (e['latitude'] as num).toDouble(),
              longitude: (e['longitude'] as num).toDouble(),
            )
          : null,
      phone: e['phone']?.toString(),
      email: e['email']?.toString(),
      website: e['website']?.toString(),
      isDuty: e['is_duty'] as bool?,
      isOpen: e['is_open'] as bool?,
      isVerified: e['is_verified'] as bool?,
      services: (e['services'] as List?)?.map((s) => s.toString()).toList(),
      rating: (e['rating'] as num?)?.toDouble(),
      reviewCount: (e['review_count'] as num?)?.toInt(),
    );
  }
}
