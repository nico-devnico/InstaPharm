import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/cameroon.dart';
import '../core/constants/super_admin.dart';
import 'supabase_service.dart';
import 'verification_docs_service.dart';

/// Accès admin : préfère l'API Node (contrôle rôle serveur),
/// sinon bascule sur les RPC / tables Supabase (RLS admin).
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  SupabaseClient get _db => SupabaseService.client;

  String? get _apiBase {
    final v = dotenv.env['STOCK_API_BASE_URL']?.trim();
    if (v == null || v.isEmpty) return null;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  Future<String?> _token() async {
    return _db.auth.currentSession?.accessToken;
  }

  Future<Map<String, dynamic>?> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final base = _apiBase;
    if (base == null) return null;
    final token = await _token();
    if (token == null) throw Exception('Non authentifié');

    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers);
        break;
      case 'POST':
        res = await http.post(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: jsonEncode(body));
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      default:
        throw Exception('Méthode HTTP inconnue');
    }
    final map = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (map is! Map) throw Exception('Réponse invalide');
    final data = Map<String, dynamic>.from(map);
    if (res.statusCode >= 400) {
      throw Exception(data['error']?.toString() ?? 'Erreur ${res.statusCode}');
    }
    return data;
  }

  Future<Map<String, dynamic>> claimBootstrap() async {
    final api = await _api('POST', '/api/admin/bootstrap');
    if (api != null) return api;
    final rpc = await _db.rpc('claim_bootstrap_admin');
    return Map<String, dynamic>.from(rpc as Map? ?? {'ok': true});
  }

  Future<Map<String, dynamic>> dashboard() async {
    final api = await _api('GET', '/api/admin/dashboard');
    if (api != null) return api;
    try {
      final rpc = await _db.rpc('admin_dashboard_stats');
      if (rpc is Map && rpc['ok'] == true) {
        return Map<String, dynamic>.from(rpc);
      }
    } catch (_) {}
    return _dashboardFromTables();
  }

  Future<Map<String, dynamic>> _dashboardFromTables() async {
    final profiles = await _db.from('profiles').select('id, role, is_active');
    final pharmacies =
        await _db.from('pharmacies').select('id, platform_status, is_platform, is_active').eq('is_platform', true);
    final medicines = await _db.from('medicines').select('id, is_active');
    final orders = await _db.from('orders').select('id, status, fulfillment');
    final couriers = await _db.from('couriers').select('id, is_available, is_active');
    int reportsOpen = 0;
    try {
      final reports = await _db
          .from('reports')
          .select('id, status')
          .or('status.eq.OPEN,status.eq.IN_PROGRESS');
      reportsOpen = (reports as List).length;
    } catch (_) {}

    final pList = profiles as List;
    final phList = pharmacies as List;
    final mList = medicines as List;
    final oList = orders as List;
    final cList = couriers as List;

    final byRole = <String, int>{};
    for (final p in pList) {
      final r = (p as Map)['role']?.toString() ?? 'patient';
      byRole[r] = (byRole[r] ?? 0) + 1;
    }
    final byStatus = <String, int>{};
    for (final o in oList) {
      final s = (o as Map)['status']?.toString() ?? '';
      byStatus[s] = (byStatus[s] ?? 0) + 1;
    }

    int phStatus(String st) => phList
        .where((e) =>
            ((e as Map)['platform_status']?.toString() ?? 'VERIFIED') == st)
        .length;

    return {
      'ok': true,
      'users_total': pList.length,
      'users_active': pList
          .where((e) => (e as Map)['is_active'] != false)
          .length,
      'users_by_role': byRole,
      'pharmacies_total': phList.length,
      'pharmacies_verified': phStatus('VERIFIED'),
      'pharmacies_pending': phStatus('PENDING'),
      'pharmacies_rejected': phStatus('REJECTED'),
      'pharmacies_suspended': phStatus('SUSPENDED'),
      'medicines_total': mList.length,
      'medicines_active':
          mList.where((e) => (e as Map)['is_active'] != false).length,
      'orders_total': oList.length,
      'orders_active': oList
          .where((e) {
            final s = (e as Map)['status'];
            return s != 'delivered' && s != 'cancelled';
          })
          .length,
      'orders_delivered': byStatus['delivered'] ?? 0,
      'orders_cancelled': byStatus['cancelled'] ?? 0,
      'deliveries_in_progress': oList
          .where((e) =>
              (e as Map)['fulfillment'] == 'delivery' &&
              e['status'] == 'out_for_delivery')
          .length,
      'couriers_total': cList.length,
      'couriers_available': cList
          .where((e) =>
              (e as Map)['is_available'] == true && e['is_active'] != false)
          .length,
      'reports_open': reportsOpen,
      'orders_by_status': byStatus,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> listUsers({
    String? q,
    String? role,
    String? active,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/users', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (role != null) 'role': role,
      if (active != null) 'active': active,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;

    var query = _db.from('profiles').select();
    if (role != null) query = query.eq('role', role);
    if (active == 'true') query = query.eq('is_active', true);
    if (active == 'false') query = query.eq('is_active', false);
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or('full_name.ilike.%$t%,email.ilike.%$t%,phone.ilike.%$t%');
    }
    final from = (page - 1) * pageSize;
    final rows = await query
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<Map<String, dynamic>> getUser(String id) async {
    final api = await _api('GET', '/api/admin/users/$id');
    if (api != null) return api;
    final user = await _db.from('profiles').select().eq('id', id).single();
    final orders = await _db
        .from('orders')
        .select('id, public_code, status, pharmacy_name, subtotal_xaf, created_at')
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .limit(20);
    return {'ok': true, 'user': user, 'recentOrders': orders, 'recentSearches': []};
  }

  Future<void> updateUser(String id, Map<String, dynamic> patch) async {
    await _ensureNotSuperAdminTarget(id, patch);
    final api = await _api('PATCH', '/api/admin/users/$id', body: patch);
    if (api != null) {
      await _audit('UPDATE_USER', 'profile', id, patch);
      return;
    }
    await _db.from('profiles').update({
      ...patch,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit('UPDATE_USER', 'profile', id, patch);
  }

  Future<void> _ensureNotSuperAdminTarget(
    String id,
    Map<String, dynamic>? patch,
  ) async {
    final row =
        await _db.from('profiles').select('email, role').eq('id', id).maybeSingle();
    final email = row?['email']?.toString();
    if (!SuperAdmin.isSuperAdminEmail(email)) return;

    final suspends = patch != null &&
        (patch['is_active'] == false ||
            patch.containsKey('disabled_reason') ||
            (patch['role'] != null && patch['role'] != 'admin'));
    if (patch == null || suspends || patch.isEmpty) {
      throw Exception(
        'Compte super-admin protégé : impossible de suspendre, '
        'supprimer ou rétrograder ${SuperAdmin.email}.',
      );
    }
  }

  Future<bool> isSuperAdminUser(String id) async {
    final row =
        await _db.from('profiles').select('email').eq('id', id).maybeSingle();
    return SuperAdmin.isSuperAdminEmail(row?['email']?.toString());
  }

  Future<void> createUserProfile({
    required String email,
    required String fullName,
    String? phone,
    String role = 'patient',
  }) async {
    final api = await _api('POST', '/api/admin/users', body: {
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'role': role,
    });
    if (api != null) {
      await _audit('CREATE_USER', 'profile', api['id']?.toString() ?? email, {
        'email': email,
        'role': role,
      });
      return;
    }
    throw Exception(
      'Création directe indisponible. Demandez à la personne de s’inscrire '
      'dans l’app ; vous pourrez ensuite modifier / suspendre son compte.',
    );
  }

  Future<String> uploadVerificationDoc({
    required String applicationId,
    required String fileName,
    required List<int> bytes,
    required String contentType,
  }) async {
    // Dossier = user courant (policy storage) ; admin a aussi accès.
    final folder = _db.auth.currentUser?.id ?? applicationId;
    final url = await VerificationDocsService.instance.upload(
      folder: folder,
      doc: PickedVerificationDoc(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
      ),
    );
    return url;
  }

  Future<void> suspendUser(String id, {String? reason}) async {
    if (await isSuperAdminUser(id)) {
      throw Exception(
        'Compte super-admin protégé : suspension interdite.',
      );
    }
    await updateUser(id, {
      'is_active': false,
      if (reason != null) 'disabled_reason': reason,
    });
    await _audit('SUSPEND_USER', 'profile', id, {'reason': reason});
  }

  Future<void> activateUser(String id) async {
    await updateUser(id, {
      'is_active': true,
      'disabled_reason': null,
    });
    await _audit('ACTIVATE_USER', 'profile', id, {});
  }

  Future<void> deleteUser(String id) async {
    if (await isSuperAdminUser(id)) {
      throw Exception(
        'Compte super-admin protégé : suppression interdite.',
      );
    }
    final api = await _api('DELETE', '/api/admin/users/$id');
    if (api != null) {
      await _audit('DELETE_USER', 'profile', id, {'via': 'api'});
      return;
    }
    await suspendUser(id, reason: 'Supprimé par admin');
    await _audit('DELETE_USER', 'profile', id, {'soft': true});
  }

  Future<void> deleteCourier(String id) async {
    final api = await _api('DELETE', '/api/admin/couriers/$id');
    if (api != null) {
      await _audit('DELETE_COURIER', 'courier', id, {});
      return;
    }
    await _db.from('couriers').update({
      'is_active': false,
      'is_available': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit('DELETE_COURIER', 'courier', id, {'soft': true});
  }

  Future<void> attachApplicationDocuments(
    String applicationId, {
    String? idDocumentUrl,
    String? professionalDocumentUrl,
    String? licenseNumber,
    String? adminNotes,
    Map<String, dynamic>? extraInfo,
  }) async {
    final patch = <String, dynamic>{
      if (idDocumentUrl != null) 'id_document_url': idDocumentUrl,
      if (professionalDocumentUrl != null)
        'professional_document_url': professionalDocumentUrl,
      if (licenseNumber != null) 'license_number': licenseNumber,
      if (adminNotes != null) 'admin_notes': adminNotes,
      if (extraInfo != null) 'notes': extraInfo['notes'] ?? extraInfo.toString(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db.from('account_applications').update(patch).eq('id', applicationId);
    await _audit('ATTACH_APPLICATION_DOCS', 'account_application', applicationId, patch);
  }

  Future<Map<String, dynamic>> listPharmacies({
    String? q,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/pharmacies', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (status != null) 'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;

    var query = _db.from('pharmacies').select().eq('is_platform', true);
    if (status != null) query = query.eq('platform_status', status);
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or('name.ilike.%$t%,city.ilike.%$t%,address.ilike.%$t%');
    }
    final from = (page - 1) * pageSize;
    final rows = await query.order('name').range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<Map<String, dynamic>> pharmacyDetail(String id) async {
    final api = await _api('GET', '/api/admin/pharmacies/$id');
    if (api != null) return api;
    final pharmacy = await _db.from('pharmacies').select().eq('id', id).single();
    final stock = await _db
        .from('inventory')
        .select('*, medicines(name, brand, dosage)')
        .eq('pharmacy_id', id)
        .limit(50);
    final orders = await _db
        .from('orders')
        .select('id, public_code, status, subtotal_xaf, user_id, created_at')
        .eq('pharmacy_id', id)
        .order('created_at', ascending: false)
        .limit(30);
    return {'ok': true, 'pharmacy': pharmacy, 'stock': stock, 'orders': orders};
  }

  Future<String> upsertPharmacy(Map<String, dynamic> data) async {
    final api = data['id'] != null
        ? await _api('PUT', '/api/admin/pharmacies/${data['id']}', body: data)
        : await _api('POST', '/api/admin/pharmacies', body: data);
    if (api != null) return api['id']?.toString() ?? data['id']?.toString() ?? '';

    final id = data['id']?.toString() ??
        'plat-${DateTime.now().millisecondsSinceEpoch}-${(data['name'] ?? '').hashCode.abs()}';
    final row = {
      'id': id,
      'name': data['name'],
      'address': data['address'],
      'city': data['city'],
      'latitude': data['latitude'] ?? CameroonDefaults.douala.latitude,
      'longitude': data['longitude'] ?? CameroonDefaults.douala.longitude,
      'phone': data['phone'],
      'email': data['email'],
      'is_duty': data['is_duty'] ?? false,
      'is_open': data['is_open'] ?? true,
      'is_verified': (data['platform_status'] ?? 'VERIFIED') == 'VERIFIED',
      'is_platform': true,
      'services': data['services'] ?? ['Livraison'],
      'platform_status': data['platform_status'] ?? 'VERIFIED',
      'is_active': data['is_active'] ?? true,
      'opening_hours': data['opening_hours'] ?? {},
      'owner_user_id': data['owner_user_id'],
      'registered_by': _db.auth.currentUser?.id,
    };
    await _db.from('pharmacies').upsert(row);
    await _audit(
      data['id'] != null ? 'UPDATE_PHARMACY' : 'CREATE_PHARMACY',
      'pharmacy',
      id,
      {'name': data['name'], 'latitude': data['latitude'], 'longitude': data['longitude']},
    );
    return id;
  }

  Future<void> updatePharmacyLocation(
    String id, {
    required double latitude,
    required double longitude,
  }) async {
    final api = await _api(
      'PATCH',
      '/api/admin/pharmacies/$id/location',
      body: {'latitude': latitude, 'longitude': longitude},
    );
    if (api != null) return;
    await _db.from('pharmacies').update({
      'latitude': latitude,
      'longitude': longitude,
    }).eq('id', id);
    await _audit('UPDATE_PHARMACY_LOCATION', 'pharmacy', id, {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<void> setPharmacyStatus(String id, String status, {String? reason}) async {
    final api = await _api(
      'PATCH',
      '/api/admin/pharmacies/$id/status',
      body: {'status': status, 'reason': reason},
    );
    if (api != null) return;
    await _db.from('pharmacies').update({
      'platform_status': status,
      'is_verified': status == 'VERIFIED',
      'is_active': status != 'REJECTED' && status != 'SUSPENDED',
      'rejection_reason': status == 'REJECTED' ? reason : null,
      if (status == 'VERIFIED') 'verified_at': DateTime.now().toIso8601String(),
      if (status == 'VERIFIED') 'verified_by': _db.auth.currentUser?.id,
    }).eq('id', id);
    await _audit('SET_PHARMACY_STATUS', 'pharmacy', id, {'status': status});
  }

  Future<void> deactivatePharmacy(String id) async {
    final api = await _api('DELETE', '/api/admin/pharmacies/$id');
    if (api != null) {
      await _audit('DEACTIVATE_PHARMACY', 'pharmacy', id, {'via': 'api'});
      return;
    }
    await setPharmacyStatus(id, 'SUSPENDED');
    await _audit('DEACTIVATE_PHARMACY', 'pharmacy', id, {'soft': true});
  }

  Future<void> setMedicineActive(String id, bool active) async {
    final api = await _api(
      'PUT',
      '/api/admin/medicines/$id',
      body: {'is_active': active},
    );
    if (api != null) {
      await _audit(
        active ? 'ACTIVATE_MEDICINE' : 'DEACTIVATE_MEDICINE',
        'medicine',
        id,
        {'is_active': active},
      );
      return;
    }
    await _db.from('medicines').update({
      'is_active': active,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit(
      active ? 'ACTIVATE_MEDICINE' : 'DEACTIVATE_MEDICINE',
      'medicine',
      id,
      {'is_active': active},
    );
  }

  Future<void> setCourierActive(String id, bool active) async {
    final api = await _api(
      'PUT',
      '/api/admin/couriers/$id',
      body: {'is_active': active},
    );
    if (api != null) {
      await _audit(
        active ? 'ACTIVATE_COURIER' : 'DEACTIVATE_COURIER',
        'courier',
        id,
        {'is_active': active},
      );
      return;
    }
    await _db.from('couriers').update({
      'is_active': active,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit(
      active ? 'ACTIVATE_COURIER' : 'DEACTIVATE_COURIER',
      'courier',
      id,
      {'is_active': active},
    );
  }

  Future<void> updateOrderStatus(String id, String status) async {
    final api = await _api(
      'PATCH',
      '/api/admin/orders/$id/status',
      body: {'status': status},
    );
    if (api != null) {
      await _audit('UPDATE_ORDER_STATUS', 'order', id, {'status': status});
      return;
    }
    await _db.from('orders').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit('UPDATE_ORDER_STATUS', 'order', id, {'status': status});
  }

  Future<void> updateStock({
    required String inventoryId,
    int? quantity,
    String? status,
    int? priceXaf,
  }) async {
    final body = <String, dynamic>{
      if (quantity != null) 'quantity': quantity,
      if (status != null) 'status': status,
      if (priceXaf != null) 'price_xaf': priceXaf,
    };
    final api = await _api(
      'PATCH',
      '/api/admin/stocks/$inventoryId',
      body: body,
    );
    if (api != null) {
      await _audit('UPDATE_STOCK', 'inventory', inventoryId, body);
      return;
    }
    await _db.from('inventory').update({
      ...body,
      'updated_at': DateTime.now().toIso8601String(),
      'source': 'admin_manual',
    }).eq('id', inventoryId);
    await _audit('UPDATE_STOCK', 'inventory', inventoryId, body);
  }

  Future<Map<String, dynamic>> listMedicines({
    String? q,
    String? active,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/medicines', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (active != null) 'active': active,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db.from('medicines').select();
    if (active == 'true') query = query.eq('is_active', true);
    if (active == 'false') query = query.eq('is_active', false);
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or(
        'name.ilike.%$t%,brand.ilike.%$t%,category.ilike.%$t%,dosage.ilike.%$t%',
      );
    }
    final from = (page - 1) * pageSize;
    final rows = await query.order('name').range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<void> upsertMedicine(Map<String, dynamic> data) async {
    final api = data['id'] != null
        ? await _api('PUT', '/api/admin/medicines/${data['id']}', body: data)
        : await _api('POST', '/api/admin/medicines', body: data);
    if (api != null) return;
    if (data['id'] != null) {
      await _db.from('medicines').update({
        'name': data['name'],
        'brand': data['brand'],
        'dosage': data['dosage'],
        'form': data['form'],
        'category': data['category'],
        'description': data['description'],
        'requires_prescription': data['requires_prescription'] ?? false,
        'price_xaf': data['price_xaf'] ?? 0,
        'is_active': data['is_active'] ?? true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', data['id']);
      await _audit('UPDATE_MEDICINE', 'medicine', data['id'].toString(), data);
    } else {
      final row = await _db.from('medicines').insert({
        'name': data['name'],
        'brand': data['brand'],
        'dosage': data['dosage'],
        'form': data['form'],
        'category': data['category'],
        'description': data['description'],
        'requires_prescription': data['requires_prescription'] ?? false,
        'price_xaf': data['price_xaf'] ?? 0,
        'is_active': data['is_active'] ?? true,
      }).select().single();
      await _audit('CREATE_MEDICINE', 'medicine', row['id'].toString(), data);
    }
  }

  Future<Map<String, dynamic>> listOrders({
    String? q,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/orders', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (status != null) 'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db
        .from('orders')
        .select('*, profiles(full_name, email), couriers(full_name)');
    if (status != null) query = query.eq('status', status);
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or('public_code.ilike.%$t%,pharmacy_name.ilike.%$t%');
    }
    final from = (page - 1) * pageSize;
    final rows = await query
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<Map<String, dynamic>> getOrder(String id) async {
    final api = await _api('GET', '/api/admin/orders/$id');
    if (api != null) return api;
    final order = await _db
        .from('orders')
        .select('*, order_items(*), profiles(full_name, email, phone), couriers(full_name, phone)')
        .eq('id', id)
        .maybeSingle();
    if (order == null) throw Exception('Commande introuvable');
    return {
      'ok': true,
      'order': order,
      'items': order['order_items'] ?? [],
    };
  }

  Future<Map<String, dynamic>> listCouriers({
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/couriers', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db.from('couriers').select();
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or('full_name.ilike.%$t%,phone.ilike.%$t%');
    }
    final from = (page - 1) * pageSize;
    final rows = await query.order('full_name').range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<void> upsertCourier(Map<String, dynamic> data) async {
    final api = data['id'] != null
        ? await _api('PUT', '/api/admin/couriers/${data['id']}', body: data)
        : await _api('POST', '/api/admin/couriers', body: data);
    if (api != null) return;
    if (data['id'] != null) {
      await _db.from('couriers').update({
        'full_name': data['full_name'],
        'phone': data['phone'],
        'is_available': data['is_available'] ?? true,
        'is_active': data['is_active'] ?? true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', data['id']);
    } else {
      await _db.from('couriers').insert({
        'full_name': data['full_name'],
        'phone': data['phone'],
        'is_available': data['is_available'] ?? true,
        'is_active': data['is_active'] ?? true,
      });
    }
    await _audit(
      data['id'] != null ? 'UPDATE_COURIER' : 'CREATE_COURIER',
      'courier',
      data['id']?.toString() ?? '',
      data,
    );
  }

  Future<Map<String, dynamic>> listReports({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final api = await _api('GET', '/api/admin/reports', query: {
      if (status != null) 'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db.from('reports').select('*, profiles(full_name, email)');
    if (status != null) query = query.eq('status', status);
    final from = (page - 1) * pageSize;
    final rows = await query
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<void> updateReport(
    String id, {
    String? status,
    String? adminNotes,
  }) async {
    final api = await _api('PATCH', '/api/admin/reports/$id', body: {
      if (status != null) 'status': status,
      if (adminNotes != null) 'admin_notes': adminNotes,
    });
    if (api != null) return;
    await _db.from('reports').update({
      if (status != null) 'status': status,
      if (adminNotes != null) 'admin_notes': adminNotes,
      if (status == 'RESOLVED' || status == 'CLOSED') ...{
        'resolved_by': _db.auth.currentUser?.id,
        'resolved_at': DateTime.now().toIso8601String(),
      },
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await _audit('UPDATE_REPORT', 'report', id, {'status': status});
  }

  Future<Map<String, dynamic>> listSettings() async {
    final api = await _api('GET', '/api/admin/settings');
    if (api != null) return api;
    final rows = await _db.from('app_settings').select().order('category');
    return {'ok': true, 'items': rows};
  }

  Future<void> updateSetting(String key, dynamic value) async {
    final api = await _api('PUT', '/api/admin/settings/$key', body: {'value': value});
    if (api != null) return;
    await _db.from('app_settings').upsert({
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': _db.auth.currentUser?.id,
    });
    await _audit('UPDATE_SETTING', 'setting', key, {'value': value});
  }

  Future<Map<String, dynamic>> listAuditLogs({
    String? q,
    String? resourceType,
    String? action,
    int page = 1,
    int pageSize = 30,
  }) async {
    final api = await _api('GET', '/api/admin/audit-logs', query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (resourceType != null && resourceType.isNotEmpty)
        'resourceType': resourceType,
      if (action != null && action.isNotEmpty) 'action': action,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db.from('audit_logs').select('*, profiles(full_name, email)');
    if (resourceType != null && resourceType.trim().isNotEmpty) {
      query = query.eq('resource_type', resourceType.trim());
    }
    if (action != null && action.trim().isNotEmpty) {
      query = query.ilike('action', '%${action.trim()}%');
    }
    if (q != null && q.trim().isNotEmpty) {
      final t = q.trim();
      query = query.or(
        'action.ilike.%$t%,resource_type.ilike.%$t%,resource_id.ilike.%$t%',
      );
    }
    final from = (page - 1) * pageSize;
    final rows = await query
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<Map<String, dynamic>> listStocks({
    String? pharmacyId,
    String? status,
    int page = 1,
    int pageSize = 30,
  }) async {
    final api = await _api('GET', '/api/admin/stocks', query: {
      if (pharmacyId != null) 'pharmacyId': pharmacyId,
      if (status != null) 'status': status,
      'page': '$page',
      'pageSize': '$pageSize',
    });
    if (api != null) return api;
    var query = _db
        .from('inventory')
        .select('*, medicines(name), pharmacies(name)');
    if (pharmacyId != null) query = query.eq('pharmacy_id', pharmacyId);
    if (status != null) query = query.eq('status', status);
    final from = (page - 1) * pageSize;
    final rows = await query
        .order('updated_at', ascending: false)
        .range(from, from + pageSize - 1);
    return {
      'ok': true,
      'total': (rows as List).length,
      'page': page,
      'pageSize': pageSize,
      'items': rows,
    };
  }

  Future<void> _audit(
    String action,
    String resourceType,
    String resourceId,
    Map<String, dynamic> meta,
  ) async {
    try {
      await _db.from('audit_logs').insert({
        'actor_id': _db.auth.currentUser?.id,
        'action': action,
        'resource_type': resourceType,
        'resource_id': resourceId,
        'meta': meta,
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listApplications({String? status}) async {
    dynamic q = _db.from('account_applications').select();
    if (status != null) {
      q = q.eq('status', status);
    }
    final rows = await q.order('created_at', ascending: false).limit(100);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> reviewApplication(
    String id, {
    required String status,
    String? adminNotes,
  }) async {
    final rpc = await _db.rpc(
      'admin_review_application',
      params: {
        'p_application_id': id,
        'p_status': status,
        'p_admin_notes': adminNotes,
      },
    );
    if (rpc is Map) {
      final map = Map<String, dynamic>.from(rpc);
      if (map['ok'] == false) {
        throw Exception(
          map['message']?.toString() ??
              map['error']?.toString() ??
              'Échec validation',
        );
      }
    }
    await _audit('REVIEW_APPLICATION', 'account_application', id, {
      'status': status,
      'notes': adminNotes,
    });
  }
}
