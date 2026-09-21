import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/enums.dart';
import '../models/order.dart';
import 'location_service.dart';
import 'order_repository.dart';
import 'supabase_service.dart';

/// Opérations pharmacie & livreur (mises à jour de commandes).
class StaffRepository {
  StaffRepository._();
  static final StaffRepository instance = StaffRepository._();

  SupabaseClient get _db => SupabaseService.client;

  Future<List<MedicineOrder>> getPharmacyOrders() async {
    final rows = await _db
        .from('orders')
        .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
        .order('created_at', ascending: false)
        .limit(80);
    return (rows as List)
        .map((e) => OrderRepository.instance.mapOrderRowPublic(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  Future<List<MedicineOrder>> getCourierJobs({bool availableOnly = false}) async {
    var query = _db
        .from('orders')
        .select('*, order_items(*), couriers(full_name, phone), pharmacies(*)')
        .eq('fulfillment', 'delivery')
        .order('created_at', ascending: false)
        .limit(60);

    final rows = await query;
    var list = (rows as List)
        .map((e) => OrderRepository.instance.mapOrderRowPublic(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();

    if (availableOnly) {
      list = list
          .where((o) =>
              o.status == OrderStatus.preparing ||
              o.status == OrderStatus.confirmed ||
              o.status == OrderStatus.outForDelivery)
          .toList();
    }
    return list;
  }

  Future<void> updateOrderStatus(String orderUuid, OrderStatus status) async {
    final map = <String, dynamic>{
      'status': _statusDb(status),
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (status == OrderStatus.outForDelivery) {
      map['departed_at'] = DateTime.now().toIso8601String();
    }
    if (status == OrderStatus.delivered) {
      map['delivered_at'] = DateTime.now().toIso8601String();
      map['courier_progress'] = 1;
    }
    await _db.from('orders').update(map).eq('id', orderUuid);
  }

  Future<void> updateCourierProgress({
    required String orderUuid,
    required double progress,
    required double lat,
    required double lng,
    int? etaMinutes,
  }) async {
    await _db.from('orders').update({
      'courier_progress': progress.clamp(0.0, 1.0),
      'courier_lat': lat,
      'courier_lng': lng,
      if (etaMinutes != null) 'eta_minutes': etaMinutes,
      'status': progress >= 0.98
          ? 'delivered'
          : 'out_for_delivery',
      if (progress >= 0.98)
        'delivered_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderUuid);
  }

  /// Publie la position GPS du livreur sur la commande active.
  Future<void> pushLiveLocation(String orderUuid) async {
    final loc = await LocationService.instance.getCurrentLocation();
    if (loc == null) return;
    await _db.from('orders').update({
      'courier_lat': loc.latitude,
      'courier_lng': loc.longitude,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderUuid);

    // Met aussi à jour la table couriers si liée au profil
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _db.from('couriers').update({
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('user_id', uid);
      } catch (_) {}
    }
  }

  Future<void> claimDelivery(String orderUuid) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');

    String? courierId;
    final existing = await _db
        .from('couriers')
        .select('id')
        .eq('user_id', uid)
        .maybeSingle();
    if (existing != null) {
      courierId = existing['id']?.toString();
    } else {
      final profile = await _db
          .from('profiles')
          .select('full_name, phone')
          .eq('id', uid)
          .maybeSingle();
      final inserted = await _db
          .from('couriers')
          .insert({
            'user_id': uid,
            'full_name': profile?['full_name'] ?? 'Livreur',
            'phone': profile?['phone'] ?? '',
            'is_available': true,
          })
          .select('id')
          .single();
      courierId = inserted['id']?.toString();
    }

    await _db.from('orders').update({
      'courier_id': courierId,
      'status': 'out_for_delivery',
      'departed_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', orderUuid);
  }

  Future<void> setRole(String role) async {
    throw Exception(
      'Le changement de rôle libre est désactivé. '
      'Pharmacien / livreur : inscription + validation admin.',
    );
  }

  /// Première promotion admin (si aucun admin n'existe encore).
  Future<Map<String, dynamic>> claimBootstrapAdmin() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Non connecté');
    final rpc = await _db.rpc('claim_bootstrap_admin');
    if (rpc is Map) return Map<String, dynamic>.from(rpc);
    return {'ok': true};
  }

  String _statusDb(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.outForDelivery:
        return 'out_for_delivery';
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }
}
