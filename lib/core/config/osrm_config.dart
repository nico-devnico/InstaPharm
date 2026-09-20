import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration du moteur OSRM MLD (Multi-Level Dijkstra) avec trafic.
///
/// Pipeline serveur (une fois) :
///   OSM → osrm-extract → osrm-partition
/// Puis périodiquement :
///   flux trafic → osrm-customize → osrm-routed (--algorithm mld)
class OsrmConfig {
  OsrmConfig._();

  /// URL de base du moteur OSRM (sans /route/v1).
  /// Ex. http://localhost:5000  ou  https://router.project-osrm.org
  static String get baseUrl {
    final fromEnv = dotenv.env['OSRM_BASE_URL']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv.replaceAll(RegExp(r'/+$'), '');
    }
    return 'https://router.project-osrm.org';
  }

  /// true si un moteur MLD auto-hébergé (customize) est configuré.
  static bool get usesCustomMldEngine {
    final u = baseUrl.toLowerCase();
    if (u.isEmpty) return false;
    if (u.contains('router.project-osrm.org')) return false;
    if (u.contains('routing.openstreetmap.de')) return false;
    return true;
  }

  /// Intervalle de rafraîchissement trafic côté client (minutes).
  static int get trafficRefreshMinutes {
    final raw = dotenv.env['OSRM_TRAFFIC_REFRESH_MINUTES']?.trim();
    return int.tryParse(raw ?? '')?.clamp(1, 60) ?? 5;
  }

  static String routeUrl({
    required String profile,
    required String coordinates,
  }) =>
      '$baseUrl/route/v1/$profile/$coordinates';
}
