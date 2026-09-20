import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/coordinates.dart';
import '../models/pharmacy.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';

/// Pharmacies réelles OpenStreetMap via l’API Overpass.
class OsmPharmacyService {
  OsmPharmacyService._();
  static final OsmPharmacyService instance = OsmPharmacyService._();

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  List<Pharmacy>? _cache;
  double? _cacheLat;
  double? _cacheLng;
  double? _cacheRadiusM;
  DateTime? _cacheAt;

  /// Récupère les pharmacies autour d’un point GPS réel.
  Future<List<Pharmacy>> fetchNearby({
    required double latitude,
    required double longitude,
    double radiusMeters = 3000,
    bool forceRefresh = false,
  }) async {
    final canUseCache = !forceRefresh &&
        _cache != null &&
        _cacheLat != null &&
        _cacheLng != null &&
        _cacheRadiusM != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!).inSeconds < 600;

    if (canUseCache) {
      final moved = LocationService.distanceBetween(
        _cacheLat!,
        _cacheLng!,
        latitude,
        longitude,
      );
      if (moved < 300) {
        // Rayon demandé ≤ cache : filtre local (pas de nouvel appel réseau)
        if (radiusMeters <= _cacheRadiusM! + 80) {
          return _withDistances(_cache!, latitude, longitude)
              .where((p) => (p.distanceMeters ?? 0) <= radiusMeters)
              .toList();
        }
      }
    }

    // Timeout serveur raisonnable (évite de bloquer l’UI trop longtemps).
    final query = '''
[out:json][timeout:25];
(
  node["amenity"="pharmacy"](around:$radiusMeters,$latitude,$longitude);
  way["amenity"="pharmacy"](around:$radiusMeters,$latitude,$longitude);
  node["healthcare"="pharmacy"](around:$radiusMeters,$latitude,$longitude);
);
out center tags;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final list = await _query(endpoint, query, latitude, longitude);
        _cache = list;
        _cacheLat = latitude;
        _cacheLng = longitude;
        _cacheRadiusM = radiusMeters;
        _cacheAt = DateTime.now();
        return list;
      } catch (e) {
        lastError = e;
      }
    }
    if (_cache != null) {
      return _withDistances(_cache!, latitude, longitude)
          .where((p) => (p.distanceMeters ?? 0) <= radiusMeters)
          .toList();
    }
    throw lastError ?? Exception('Impossible de charger les pharmacies');
  }

  Future<List<Pharmacy>> _query(
    String endpoint,
    String query,
    double userLat,
    double userLng,
  ) async {
    final response = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Accept': 'application/json',
            'User-Agent': 'InstaPharm/1.0 (OpenStreetMap pharmacy finder)',
          },
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 28));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Overpass ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? [];
    final pharmacies = <Pharmacy>[];

    for (final el in elements) {
      final map = el as Map<String, dynamic>;
      final tags = (map['tags'] as Map<String, dynamic>?) ?? {};
      final name = tags['name']?.toString() ??
          tags['name:fr']?.toString() ??
          'Pharmacie';

      double? lat;
      double? lng;
      if (map['type'] == 'node') {
        lat = (map['lat'] as num?)?.toDouble();
        lng = (map['lon'] as num?)?.toDouble();
      } else {
        final center = map['center'] as Map<String, dynamic>?;
        lat = (center?['lat'] as num?)?.toDouble();
        lng = (center?['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final id = 'osm-${map['type']}-${map['id']}';
      final phone = tags['phone']?.toString() ??
          tags['contact:phone']?.toString() ??
          tags['telephone']?.toString();
      final website = tags['website']?.toString() ??
          tags['contact:website']?.toString();
      final opening = tags['opening_hours']?.toString();
      final street = tags['addr:street']?.toString();
      final housenumber = tags['addr:housenumber']?.toString();
      final city = tags['addr:city']?.toString() ??
          tags['addr:town']?.toString() ??
          tags['addr:suburb']?.toString();
      final postcode = tags['addr:postcode']?.toString();

      final addressParts = <String>[];
      if (housenumber != null) addressParts.add(housenumber);
      if (street != null) addressParts.add(street);
      final address = addressParts.isEmpty
          ? (tags['addr:full']?.toString())
          : addressParts.join(' ');

      final distance = LocationService.distanceBetween(
        userLat,
        userLng,
        lat,
        lng,
      );

      final is24h = opening != null &&
          (opening.toLowerCase().contains('24/7') ||
              opening.contains('24 heures'));
      final dispensing = tags['dispensing']?.toString() == 'yes';

      pharmacies.add(Pharmacy(
        id: id,
        name: name,
        address: address,
        city: city,
        postalCode: postcode,
        coordinates: Coordinates(latitude: lat, longitude: lng),
        phone: phone,
        website: website,
        rating: null,
        reviewCount: null,
        isDuty: is24h,
        isOpen: _guessOpen(opening),
        distanceMeters: distance,
        travelTimeSeconds: RoutingService.estimateUrbanTravelSeconds(distance),
        services: [
          'Livraison',
          if (dispensing) 'Dispensation',
          if (is24h) '24h/24',
        ],
        isVerified: tags['name'] != null,
      ));
    }

    pharmacies.sort(
      (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
    );
    return pharmacies;
  }

  List<Pharmacy> _withDistances(
    List<Pharmacy> source,
    double lat,
    double lng,
  ) {
    return source
        .map((p) {
          if (p.coordinates == null) return p;
          final d = LocationService.distanceBetween(
            lat,
            lng,
            p.coordinates!.latitude,
            p.coordinates!.longitude,
          );
          return p.copyWith(
            distanceMeters: d,
            travelTimeSeconds: RoutingService.estimateUrbanTravelSeconds(d),
          );
        })
        .toList()
      ..sort(
        (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
      );
  }

  bool? _guessOpen(String? openingHours) {
    if (openingHours == null || openingHours.isEmpty) return null;
    final o = openingHours.trim();
    final lower = o.toLowerCase();
    if (lower.contains('24/7') ||
        lower.contains('24 heures') ||
        lower == '24/24') {
      return true;
    }

    final now = DateTime.now().toUtc().add(const Duration(hours: 1));
    final dayKeys = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'];
    final dayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final dayIdx = now.weekday - 1;
    final dayKey = dayKeys[dayIdx];
    final minutesNow = now.hour * 60 + now.minute;

    final segments = o.split(';');
    for (final rawSeg in segments) {
      final seg = rawSeg.trim();
      if (seg.isEmpty) continue;
      final lowerSeg = seg.toLowerCase();

      final onlyTime = RegExp(r'^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$')
          .firstMatch(seg);
      if (onlyTime != null) {
        final start = int.parse(onlyTime.group(1)!) * 60 +
            int.parse(onlyTime.group(2)!);
        final end = int.parse(onlyTime.group(3)!) * 60 +
            int.parse(onlyTime.group(4)!);
        return _inRange(minutesNow, start, end);
      }

      final appliesToday = lowerSeg.contains(dayKey) ||
          lowerSeg.contains(dayNames[dayIdx]) ||
          (dayIdx <= 4 &&
              (lowerSeg.contains('mo-fr') ||
                  lowerSeg.contains('mo-sa') ||
                  lowerSeg.contains('week'))) ||
          (dayIdx == 5 &&
              (lowerSeg.contains('mo-sa') || lowerSeg.contains('sa'))) ||
          (dayIdx == 6 && lowerSeg.contains('su'));

      if (!appliesToday &&
          !RegExp(r'^\d').hasMatch(seg) &&
          !lowerSeg.contains('-')) {
        continue;
      }

      final times = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})')
          .allMatches(seg);
      for (final m in times) {
        if (!appliesToday && times.length == 1 && !lowerSeg.contains(dayKey)) {
          final hasAnyDay = dayKeys.any((d) => lowerSeg.contains(d));
          if (hasAnyDay) continue;
        }
        if (appliesToday || !dayKeys.any((d) => lowerSeg.contains(d))) {
          final start =
              int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
          final end = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
          if (_inRange(minutesNow, start, end)) return true;
          if (appliesToday) return false;
        }
      }
    }

    return null;
  }

  bool _inRange(int now, int start, int end) {
    if (end < start) {
      return now >= start || now <= end;
    }
    return now >= start && now <= end;
  }
}
