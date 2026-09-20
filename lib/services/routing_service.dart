import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../core/config/osrm_config.dart';
import '../models/coordinates.dart';
import '../models/enums.dart';
import '../models/route_result.dart';

/// Routage OSRM / FOSSGIS — géométrie routière réelle (pas de ligne droite).
class RoutingService {
  RoutingService._();
  static final RoutingService instance = RoutingService._();

  final Map<String, ({RouteBundle bundle, DateTime at})> _routeCache = {};
  static const _routeCacheTtl = Duration(minutes: 8);
  static const _routeCacheMax = 24;

  /// Vitesses urbaines Cameroun (km/h) : [min, typique, max].
  static ({double min, double typical, double max}) speedBounds(
    TravelMode mode,
  ) {
    switch (mode) {
      case TravelMode.walking:
        return (min: 3.2, typical: 4.5, max: 5.5);
      case TravelMode.cycling:
        return (min: 10.0, typical: 14.0, max: 18.0);
      case TravelMode.driving:
        return (min: 10.0, typical: 16.0, max: 28.0);
      case TravelMode.moto:
        return (min: 14.0, typical: 24.0, max: 35.0);
    }
  }

  static int estimateUrbanTravelSeconds(
    double straightDistanceMeters, {
    TravelMode mode = TravelMode.driving,
  }) {
    final roadMeters = straightDistanceMeters * 1.35;
    final speed = speedBounds(mode).typical;
    final seconds = (roadMeters / 1000) / speed * 3600;
    return seconds.round().clamp(60, 7200);
  }

  static int normalizeDurationSeconds({
    required double distanceMeters,
    required int rawSeconds,
    required TravelMode mode,
  }) {
    if (distanceMeters <= 1) return rawSeconds.clamp(60, 86400);
    final b = speedBounds(mode);
    final minSeconds = ((distanceMeters / 1000) / b.max * 3600).round();
    final maxSeconds = ((distanceMeters / 1000) / b.min * 3600).round();
    final typical = ((distanceMeters / 1000) / b.typical * 3600).round();

    if (rawSeconds < minSeconds * 0.85) return minSeconds.clamp(60, 86400);
    if (rawSeconds > maxSeconds * 1.15) {
      return ((rawSeconds + typical) / 2).round().clamp(minSeconds, maxSeconds);
    }
    return rawSeconds.clamp(minSeconds, maxSeconds).clamp(60, 86400);
  }

  void _putRouteCache(String key, RouteBundle bundle) {
    if (_routeCache.length >= _routeCacheMax) {
      final oldest = _routeCache.entries
          .reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b);
      _routeCache.remove(oldest.key);
    }
    _routeCache[key] = (bundle: bundle, at: DateTime.now());
  }

  String _profile(TravelMode mode) {
    switch (mode) {
      case TravelMode.walking:
        return 'foot';
      case TravelMode.cycling:
        return 'bike';
      case TravelMode.driving:
      case TravelMode.moto:
        return 'driving';
    }
  }

  /// Profil attendu par chaque backend (FOSSGIS ≠ project-osrm pour le vélo).
  String _profileForBase(String base, TravelMode mode) {
    final b = base.toLowerCase();
    if (b.contains('routed-bike')) return 'cycling';
    if (b.contains('routed-foot')) return 'foot';
    if (b.contains('routed-car')) return 'driving';
    return _profile(mode);
  }

  /// Backends OSRM-compatibles — FOSSGIS en premier (CORS web + routes réelles).
  List<String> _endpointBases(TravelMode mode) {
    final fossgis = switch (mode) {
      TravelMode.walking => 'https://routing.openstreetmap.de/routed-foot',
      TravelMode.cycling => 'https://routing.openstreetmap.de/routed-bike',
      _ => 'https://routing.openstreetmap.de/routed-car',
    };
    final configured = OsrmConfig.baseUrl;
    final list = <String>[fossgis];

    if (OsrmConfig.usesCustomMldEngine) {
      list.insert(0, configured);
    } else if (configured.isNotEmpty &&
        !configured.contains('routing.openstreetmap.de')) {
      list.add(configured);
    }
    list.add('https://router.project-osrm.org');

    final seen = <String>{};
    return list.where((u) => seen.add(u)).toList();
  }

  Future<RouteResult> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required TravelMode mode,
  }) async {
    final bundle = await getRouteBundle(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
      mode: mode,
    );
    return bundle.primary;
  }

  Future<RouteBundle> getRouteBundle({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required TravelMode mode,
  }) async {
    final cacheKey =
        '${fromLat.toStringAsFixed(4)},${fromLng.toStringAsFixed(4)};'
        '${toLat.toStringAsFixed(4)},${toLng.toStringAsFixed(4)};${mode.name}';
    final cached = _routeCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _routeCacheTtl) {
      return cached.bundle;
    }

    final coords = '$fromLng,$fromLat;$toLng,$toLat';
    final query =
        '?overview=simplified&geometries=geojson&steps=false'
        '&annotations=duration,distance'
        '&alternatives=2&continue_straight=true';

    for (final base in _endpointBases(mode)) {
      final profile = _profileForBase(base, mode);
      final uri = Uri.parse('$base/route/v1/$profile/$coords$query');
      try {
        final response = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'InstaPharm/1.0 (road-routing)',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['code'] != 'Ok') continue;

        final routes = data['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) continue;

        final parsed = <RouteResult>[];
        for (var i = 0; i < routes.length; i++) {
          final r = _parseOsrmRoute(
            routes[i] as Map<String, dynamic>,
            mode,
            index: i,
          );
          // Rejette les géométries quasi-ligne droite (< 4 points utiles)
          if (r.geometry.length >= 4) {
            parsed.add(r);
          } else if (r.geometry.length >= 2 &&
              _pathLength(r.geometry) >
                  _haversine(fromLat, fromLng, toLat, toLng) * 1.08) {
            // Peu de points mais détour réel (route courte)
            parsed.add(r);
          }
        }
        if (parsed.isEmpty) continue;

        final unique = <RouteResult>[];
        for (final r in parsed) {
          final dup = unique.any(
            (u) =>
                (u.distanceMeters - r.distanceMeters).abs() < 40 &&
                (u.durationSeconds - r.durationSeconds).abs() < 25,
          );
          if (!dup) unique.add(r);
        }

        unique.sort(
          (a, b) => a.durationSeconds.compareTo(b.durationSeconds),
        );
        final primary = unique.first.copyWith(
          label: 'Itinéraire recommandé',
          isShortcut: false,
        );
        final shortcuts = <RouteResult>[];
        var shortcutIdx = 1;
        var altIdx = 1;
        for (var i = 1; i < unique.length; i++) {
          final r = unique[i];
          final shorter = r.distanceMeters < primary.distanceMeters * 0.97;
          shortcuts.add(
            r.copyWith(
              label: shorter
                  ? 'Raccourci navigable'
                      '${unique.length > 2 ? ' $shortcutIdx' : ''}'
                  : 'Alternative $altIdx',
              isShortcut: true,
            ),
          );
          if (shorter) {
            shortcutIdx++;
          } else {
            altIdx++;
          }
        }
        shortcuts.sort((a, b) {
          final as_ = a.label?.contains('Raccourci') == true ? 0 : 1;
          final bs = b.label?.contains('Raccourci') == true ? 0 : 1;
          if (as_ != bs) return as_.compareTo(bs);
          return a.distanceMeters.compareTo(b.distanceMeters);
        });
        final bundle = RouteBundle(primary: primary, shortcuts: shortcuts);
        _putRouteCache(cacheKey, bundle);
        return bundle;
      } catch (_) {
        continue;
      }
    }

    // Dernier recours : toujours tenter une requête minimale sans alternatives
    final simple = await _fetchSimpleRoad(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
      mode: mode,
    );
    if (simple != null) {
      return RouteBundle(
        primary: simple.copyWith(label: 'Itinéraire recommandé'),
      );
    }

    // Estimation sans prétendre suivre la route (message UI)
    final fallback = _fallbackRoute(fromLat, fromLng, toLat, toLng, mode);
    return RouteBundle(
      primary: fallback.copyWith(
        label: 'Estimation (réseau indisponible)',
      ),
    );
  }

  Future<RouteResult?> _fetchSimpleRoad({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required TravelMode mode,
  }) async {
    final coords = '$fromLng,$fromLat;$toLng,$toLat';
    for (final base in _endpointBases(mode)) {
      final profile = _profileForBase(base, mode);
      final uri = Uri.parse(
        '$base/route/v1/$profile/$coords'
        '?overview=full&geometries=geojson&steps=false',
      );
      try {
        final response = await http
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['code'] != 'Ok') continue;
        final routes = data['routes'] as List<dynamic>?;
        if (routes == null || routes.isEmpty) continue;
        final r = _parseOsrmRoute(
          routes.first as Map<String, dynamic>,
          mode,
        );
        if (r.geometry.length >= 2) return r;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  RouteResult _parseOsrmRoute(
    Map<String, dynamic> route,
    TravelMode mode, {
    int index = 0,
  }) {
    final geometry = <Coordinates>[];
    final geo = route['geometry'] as Map<String, dynamic>?;
    final coords = geo?['coordinates'] as List<dynamic>?;
    if (coords != null) {
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          geometry.add(Coordinates(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble(),
          ));
        }
      }
    }

    final durations = <double>[];
    final distances = <double>[];
    final legs = route['legs'] as List<dynamic>? ?? [];
    for (final leg in legs) {
      final ann = (leg as Map<String, dynamic>)['annotation'];
      if (ann is Map<String, dynamic>) {
        final durs = ann['duration'] as List<dynamic>?;
        final dists = ann['distance'] as List<dynamic>?;
        if (durs != null) {
          for (final d in durs) {
            durations.add((d as num).toDouble());
          }
        }
        if (dists != null) {
          for (final d in dists) {
            distances.add((d as num).toDouble());
          }
        }
      }
    }

    final trafficSegments = _buildTrafficSegments(
      geometry: geometry,
      durations: durations,
      distances: distances,
      mode: mode,
    );

    final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0;
    var duration = ((route['duration'] as num?)?.toDouble() ?? 0);

    if (mode == TravelMode.moto) {
      duration = duration * 0.82;
    } else if (mode == TravelMode.driving && !OsrmConfig.usesCustomMldEngine) {
      duration = duration * 1.08;
    }

    final normalized = normalizeDurationSeconds(
      distanceMeters: distanceMeters,
      rawSeconds: duration.round(),
      mode: mode,
    );

    final freeFlow = _estimateFreeFlowSeconds(
      distanceMeters: distanceMeters,
      mode: mode,
    );

    return RouteResult(
      distanceMeters: distanceMeters,
      durationSeconds: normalized,
      geometry: geometry,
      travelMode: mode,
      steps: null,
      trafficSegments: trafficSegments,
      freeFlowDurationSeconds: freeFlow,
      fromTrafficEngine: OsrmConfig.usesCustomMldEngine,
      isShortcut: index > 0,
    );
  }

  List<TrafficSegment> _buildTrafficSegments({
    required List<Coordinates> geometry,
    required List<double> durations,
    required List<double> distances,
    required TravelMode mode,
  }) {
    if (geometry.length < 2) return const [];

    final n = math.min(durations.length, distances.length);
    if (n == 0) {
      return [
        TrafficSegment(
          points: geometry,
          level: CongestionLevel.free,
          distanceMeters: _pathLength(geometry),
          durationSeconds: 0,
        ),
      ];
    }

    final geoSegCount = geometry.length - 1;
    final segments = <TrafficSegment>[];

    void addRun({
      required int start,
      required int end,
      required CongestionLevel level,
      required double dist,
      required double dur,
    }) {
      if (end <= start) return;
      final endClamped = end.clamp(start + 1, geometry.length - 1);
      segments.add(TrafficSegment(
        points: geometry.sublist(start, endClamped + 1),
        level: level,
        distanceMeters: dist,
        durationSeconds: dur.round(),
        speedKmh: dur > 0.4 ? (dist / 1000) / (dur / 3600) : null,
      ));
    }

    if (n == geoSegCount) {
      CongestionLevel? runLevel;
      var runStart = 0;
      var runDist = 0.0;
      var runDur = 0.0;

      for (var i = 0; i < n; i++) {
        final dur = durations[i].clamp(0.05, 86400.0);
        final dist = distances[i].clamp(0.0, 1e7);
        final speed = (dist / 1000) / (dur / 3600);
        final level = _classifySpeed(speed, mode);
        if (runLevel == null) {
          runLevel = level;
          runStart = i;
          runDist = dist;
          runDur = dur;
        } else if (level == runLevel) {
          runDist += dist;
          runDur += dur;
        } else {
          addRun(
            start: runStart,
            end: i,
            level: runLevel,
            dist: runDist,
            dur: runDur,
          );
          runLevel = level;
          runStart = i;
          runDist = dist;
          runDur = dur;
        }
      }
      if (runLevel != null) {
        addRun(
          start: runStart,
          end: geoSegCount,
          level: runLevel,
          dist: runDist,
          dur: runDur,
        );
      }
      return segments;
    }

    final bucketSize = geoSegCount / n;
    CongestionLevel? runLevel;
    var runStart = 0;
    var runDist = 0.0;
    var runDur = 0.0;
    var geoIdx = 0;

    for (var i = 0; i < n; i++) {
      final dur = durations[i].clamp(0.05, 86400.0);
      final dist = distances[i].clamp(0.0, 1e7);
      final speed = (dist / 1000) / (dur / 3600);
      final level = _classifySpeed(speed, mode);
      final nextGeo = ((i + 1) * bucketSize).round().clamp(1, geoSegCount);

      if (runLevel == null) {
        runLevel = level;
        runStart = geoIdx;
        runDist = dist;
        runDur = dur;
      } else if (level == runLevel) {
        runDist += dist;
        runDur += dur;
      } else {
        addRun(
          start: runStart,
          end: geoIdx,
          level: runLevel,
          dist: runDist,
          dur: runDur,
        );
        runLevel = level;
        runStart = geoIdx;
        runDist = dist;
        runDur = dur;
      }
      geoIdx = nextGeo;
    }
    if (runLevel != null) {
      addRun(
        start: runStart,
        end: geoSegCount,
        level: runLevel,
        dist: runDist,
        dur: runDur,
      );
    }
    return segments;
  }

  CongestionLevel _classifySpeed(double speedKmh, TravelMode mode) {
    final b = speedBounds(mode);
    if (speedKmh >= b.typical * 0.9) return CongestionLevel.free;
    if (speedKmh >= b.typical * 0.55) return CongestionLevel.slow;
    if (speedKmh >= b.min * 0.7) return CongestionLevel.congested;
    return CongestionLevel.jammed;
  }

  int _estimateFreeFlowSeconds({
    required double distanceMeters,
    required TravelMode mode,
  }) {
    if (distanceMeters <= 0) return 60;
    final speed = speedBounds(mode).max;
    return ((distanceMeters / 1000) / speed * 3600).round().clamp(60, 86400);
  }

  double _pathLength(List<Coordinates> geometry) {
    var total = 0.0;
    for (var i = 1; i < geometry.length; i++) {
      total += _haversine(
        geometry[i - 1].latitude,
        geometry[i - 1].longitude,
        geometry[i].latitude,
        geometry[i].longitude,
      );
    }
    return total;
  }

  static Coordinates pointAlongRoute(List<Coordinates> geometry, double t) {
    if (geometry.isEmpty) {
      return const Coordinates(latitude: 0, longitude: 0);
    }
    if (geometry.length == 1 || t <= 0) return geometry.first;
    if (t >= 1) return geometry.last;

    final lengths = <double>[0];
    var total = 0.0;
    for (var i = 1; i < geometry.length; i++) {
      total += _haversine(
        geometry[i - 1].latitude,
        geometry[i - 1].longitude,
        geometry[i].latitude,
        geometry[i].longitude,
      );
      lengths.add(total);
    }
    if (total <= 0) return geometry.first;

    final target = t * total;
    for (var i = 1; i < lengths.length; i++) {
      if (target <= lengths[i]) {
        final segStart = lengths[i - 1];
        final segLen = lengths[i] - segStart;
        final localT = segLen <= 0 ? 0.0 : (target - segStart) / segLen;
        final a = geometry[i - 1];
        final b = geometry[i];
        return Coordinates(
          latitude: a.latitude + (b.latitude - a.latitude) * localT,
          longitude: a.longitude + (b.longitude - a.longitude) * localT,
        );
      }
    }
    return geometry.last;
  }

  static List<Coordinates> remainingGeometry(
    List<Coordinates> geometry,
    double t,
  ) {
    if (geometry.isEmpty) return const [];
    final current = pointAlongRoute(geometry, t);
    if (t >= 1) return [geometry.last];
    final startIndex =
        (t * (geometry.length - 1)).floor().clamp(0, geometry.length - 1);
    return [current, ...geometry.sublist(startIndex + 1)];
  }

  static List<Coordinates> completedGeometry(
    List<Coordinates> geometry,
    double t,
  ) {
    if (geometry.isEmpty) return const [];
    final current = pointAlongRoute(geometry, t);
    if (t <= 0) return [geometry.first];
    final endIndex =
        (t * (geometry.length - 1)).ceil().clamp(0, geometry.length - 1);
    return [...geometry.sublist(0, endIndex), current];
  }

  /// Fallback uniquement si tous les moteurs échouent (ne simule pas une route).
  RouteResult _fallbackRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
    TravelMode mode,
  ) {
    final geometry = [
      Coordinates(latitude: fromLat, longitude: fromLng),
      Coordinates(latitude: toLat, longitude: toLng),
    ];
    final baseDistance = _haversine(fromLat, fromLng, toLat, toLng) * 1.35;
    final typical = speedBounds(mode).typical;
    final duration = normalizeDurationSeconds(
      distanceMeters: baseDistance,
      rawSeconds: ((baseDistance / 1000) / typical * 3600).round(),
      mode: mode,
    );

    return RouteResult(
      distanceMeters: baseDistance,
      durationSeconds: duration,
      geometry: geometry,
      travelMode: mode,
      trafficSegments: const [],
      freeFlowDurationSeconds: duration,
      fromTrafficEngine: false,
    );
  }

  static double _haversine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
