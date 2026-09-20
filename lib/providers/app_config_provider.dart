import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import 'preferences_provider.dart';

/// Paramètres applicatifs lus depuis `app_settings` (admin → toute l’app).
class AppConfig {
  final String appName;
  final String supportEmail;
  final int deliveryBaseXaf;
  final int deliveryExpressXaf;
  final int deliveryFreeAboveXaf;
  final double deliveryRadiusKm;
  final double deliveryMaxRadiusKm;
  final double searchRadiusKm;
  final int searchMaxResults;
  final int lowStockThreshold;
  final bool requirePharmacyVerification;
  final bool requireStaffApproval;
  final bool orderUpdatesNotif;
  final bool promoNotif;
  final bool stockAlertsNotif;
  final int sessionIdleMinutes;
  final String supportStart;
  final String supportEnd;

  const AppConfig({
    this.appName = 'InstaPharm',
    this.supportEmail = 'support@instapharm.cm',
    this.deliveryBaseXaf = 1500,
    this.deliveryExpressXaf = 2500,
    this.deliveryFreeAboveXaf = 25000,
    this.deliveryRadiusKm = 8,
    this.deliveryMaxRadiusKm = 25,
    this.searchRadiusKm = 3,
    this.searchMaxResults = 40,
    this.lowStockThreshold = 5,
    this.requirePharmacyVerification = true,
    this.requireStaffApproval = true,
    this.orderUpdatesNotif = true,
    this.promoNotif = false,
    this.stockAlertsNotif = true,
    this.sessionIdleMinutes = 60,
    this.supportStart = '08:00',
    this.supportEnd = '20:00',
  });

  factory AppConfig.fromSettings(Map<String, dynamic> map) {
    Map<String, dynamic> obj(String key) {
      final v = map[key];
      if (v is Map) return Map<String, dynamic>.from(v);
      return const {};
    }

    final info = obj('app.info');
    final fees = obj('delivery.fees');
    final radius = obj('delivery.radius_km');
    final search = obj('search.defaults');
    final pharmacy = obj('pharmacy.rules');
    final notif = obj('notifications.defaults');
    final security = obj('security.session');
    final ops = obj('ops.hours');
    final approval = obj('registration.approval');

    return AppConfig(
      appName: info['name']?.toString() ?? 'InstaPharm',
      supportEmail: info['support_email']?.toString() ?? 'support@instapharm.cm',
      deliveryBaseXaf: (fees['base_xaf'] as num?)?.toInt() ?? 1500,
      deliveryExpressXaf: (fees['express_xaf'] as num?)?.toInt() ?? 2500,
      deliveryFreeAboveXaf: (fees['free_above_xaf'] as num?)?.toInt() ?? 25000,
      deliveryRadiusKm: (radius['default'] as num?)?.toDouble() ?? 8,
      deliveryMaxRadiusKm: (radius['max'] as num?)?.toDouble() ?? 25,
      searchRadiusKm: (search['radius_km'] as num?)?.toDouble() ?? 3,
      searchMaxResults: (search['max_results'] as num?)?.toInt() ?? 40,
      lowStockThreshold: (pharmacy['low_stock_threshold'] as num?)?.toInt() ?? 5,
      requirePharmacyVerification: pharmacy['require_verification'] != false,
      requireStaffApproval: approval['enabled'] != false,
      orderUpdatesNotif: notif['order_updates'] != false,
      promoNotif: notif['promo'] == true,
      stockAlertsNotif: notif['stock_alerts'] != false,
      sessionIdleMinutes: (security['idle_minutes'] as num?)?.toInt() ?? 60,
      supportStart: ops['support_start']?.toString() ?? '08:00',
      supportEnd: ops['support_end']?.toString() ?? '20:00',
    );
  }
}

final appConfigProvider = FutureProvider<AppConfig>((ref) async {
  try {
    final rows = await SupabaseService.client.from('app_settings').select();
    final map = <String, dynamic>{};
    for (final row in (rows as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      final key = m['key']?.toString();
      if (key != null) map[key] = m['value'];
    }
    final cfg = AppConfig.fromSettings(map);

    // Appliquer le rayon de recherche par défaut si l’utilisateur n’a pas encore
    // choisi (valeur initiale = défaut provider).
    final current = ref.read(searchRadiusKmProvider);
    if ((current - 3.0).abs() < 0.01 || (current - 1.0).abs() < 0.01) {
      final r = cfg.searchRadiusKm.clamp(1.0, 15.0);
      ref.read(searchRadiusKmProvider.notifier).state = r;
      ref.read(committedSearchRadiusKmProvider.notifier).state = r;
      ref.read(effectiveRadiusKmProvider.notifier).state = r;
    }
    return cfg;
  } catch (_) {
    return const AppConfig();
  }
});

/// Accès synchrone (fallback defaults si pas encore chargé).
final appConfigValueProvider = Provider<AppConfig>((ref) {
  return ref.watch(appConfigProvider).valueOrNull ?? const AppConfig();
});
