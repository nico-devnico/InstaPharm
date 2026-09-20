import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pharmacy.dart';
import 'supabase_service.dart';

class SearchHistoryItem {
  final String id;
  final String query;
  final DateTime searchedAt;

  const SearchHistoryItem({
    required this.id,
    required this.query,
    required this.searchedAt,
  });
}

class PharmacyViewItem {
  final String id;
  final String pharmacyId;
  final String pharmacyName;
  final String? address;
  final DateTime viewedAt;

  const PharmacyViewItem({
    required this.id,
    required this.pharmacyId,
    required this.pharmacyName,
    this.address,
    required this.viewedAt,
  });
}

/// Historique recherches / consultations + préférences notifications.
class UserActivityRepository {
  UserActivityRepository._();
  static final UserActivityRepository instance = UserActivityRepository._();

  SupabaseClient get _db => SupabaseService.client;
  static const _notifKey = 'notifications_enabled';

  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifKey, enabled);
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _db.from('profiles').update({
          'notifications_enabled': enabled,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', uid);
      } catch (_) {}
    }
  }

  String? _lastLoggedQuery;

  Future<void> logSearch(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    if (_lastLoggedQuery == q) return;
    _lastLoggedQuery = q;
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      await _db.from('search_history').insert({
        'user_id': user.id,
        'query': q,
      });
    } catch (_) {}
  }

  Future<void> logPharmacyView(Pharmacy pharmacy) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      await _db.from('pharmacy_views').insert({
        'user_id': user.id,
        'pharmacy_id': pharmacy.id,
        'pharmacy_name': pharmacy.name,
        'address': pharmacy.fullAddress.isEmpty ? pharmacy.address : pharmacy.fullAddress,
      });
    } catch (_) {}
  }

  Future<List<SearchHistoryItem>> getSearches({int limit = 50}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('search_history')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return SearchHistoryItem(
        id: m['id']?.toString() ?? '',
        query: m['query']?.toString() ?? '',
        searchedAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  Future<List<PharmacyViewItem>> getViews({int limit = 50}) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('pharmacy_views')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return PharmacyViewItem(
        id: m['id']?.toString() ?? '',
        pharmacyId: m['pharmacy_id']?.toString() ?? '',
        pharmacyName: m['pharmacy_name']?.toString() ?? '',
        address: m['address']?.toString(),
        viewedAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  Future<void> clearSearches() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('search_history').delete().eq('user_id', user.id);
  }

  Future<void> clearViews() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('pharmacy_views').delete().eq('user_id', user.id);
  }

  Future<void> clearAll() async {
    await Future.wait([clearSearches(), clearViews()]);
  }
}
