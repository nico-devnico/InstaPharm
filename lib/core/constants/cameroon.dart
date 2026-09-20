import 'package:latlong2/latlong.dart';
import '../../models/coordinates.dart';

/// Contexte géo et métier Cameroun / Afrique centrale.
class CameroonDefaults {
  CameroonDefaults._();

  /// Douala — centre-ville (Akwa)
  static const LatLng douala = LatLng(4.0511, 9.7679);

  /// Yaoundé — centre (Nlongkak / Boulevard de l’URSS)
  static const LatLng yaounde = LatLng(3.8480, 11.5021);

  /// Fallback GPS de l’application
  static const LatLng defaultLocation = douala;

  static const String countryCode = 'CM';
  static const String phonePrefix = '+237';
  static const String currencyCode = 'XAF';
  static const String currencyLabel = 'FCFA';

  /// Frais de livraison de base (FCFA) — zone urbaine
  static const int baseDeliveryFeeXaf = 1500;
  static const int expressDeliveryFeeXaf = 2500;

  static const List<String> cities = [
    'Douala',
    'Yaoundé',
    'Bafoussam',
    'Garoua',
    'Bamenda',
    'Maroua',
    'Ngaoundéré',
    'Kribi',
  ];

  static const List<String> doualaNeighborhoods = [
    'Akwa',
    'Bonanjo',
    'Bonapriso',
    'Deido',
    'Bali',
    'New Bell',
    'Pk 8',
    'Makepe',
    'Logpom',
    'Bonamoussadi',
    'Kotto',
    'Bepanda',
  ];

  static const List<String> yaoundeNeighborhoods = [
    'Bastos',
    'Nlongkak',
    'Mvog-Ada',
    'Essos',
    'Melen',
    'Omnisport',
    'Ekounou',
    'Emana',
    'Nkolbisson',
    'Elig-Edzoa',
  ];

  /// Centroïdes approximatifs des quartiers (pour géocodage livraison).
  static const Map<String, LatLng> neighborhoodCoords = {
    // Douala
    'Akwa': LatLng(4.0511, 9.7679),
    'Bonanjo': LatLng(4.0430, 9.6885),
    'Bonapriso': LatLng(4.0275, 9.7020),
    'Deido': LatLng(4.0665, 9.7200),
    'Bali': LatLng(4.0480, 9.7050),
    'New Bell': LatLng(4.0380, 9.7150),
    'Pk 8': LatLng(4.0850, 9.7600),
    'Makepe': LatLng(4.0780, 9.7450),
    'Logpom': LatLng(4.0920, 9.7550),
    'Bonamoussadi': LatLng(4.0700, 9.7800),
    'Kotto': LatLng(4.0550, 9.7900),
    'Bepanda': LatLng(4.0600, 9.7300),
    // Yaoundé
    'Bastos': LatLng(3.8930, 11.5100),
    'Nlongkak': LatLng(3.8720, 11.5105),
    'Mvog-Ada': LatLng(3.8550, 11.5200),
    'Essos': LatLng(3.8750, 11.5400),
    'Melen': LatLng(3.8450, 11.4850),
    'Omnisport': LatLng(3.8650, 11.5350),
    'Ekounou': LatLng(3.8300, 11.5300),
    'Emana': LatLng(3.9100, 11.5200),
    'Nkolbisson': LatLng(3.8700, 11.4600),
    'Elig-Edzoa': LatLng(3.8800, 11.5000),
  };

  static Coordinates resolveDestination({
    required String city,
    required String neighborhood,
  }) {
    final hit = neighborhoodCoords[neighborhood];
    if (hit != null) {
      return Coordinates(latitude: hit.latitude, longitude: hit.longitude);
    }
    final fallback = city.toLowerCase().contains('yaound') ? yaounde : douala;
    return Coordinates(
      latitude: fallback.latitude,
      longitude: fallback.longitude,
    );
  }
}
