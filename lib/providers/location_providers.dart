import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/coordinates.dart';
import '../models/pharmacy.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/platform_pharmacy_repository.dart';
import '../services/routing_service.dart';
import 'preferences_provider.dart';

/// Position GPS lissée pour l’UI carte (évite un rebuild à chaque mètre).
final liveLocationProvider = StreamProvider<LatLng?>((ref) async* {
  final service = LocationService.instance;

  final last = service.lastKnownLocation;
  if (last != null) {
    yield LatLng(last.latitude, last.longitude);
  }

  unawaited(service.getLastKnownPosition());

  final result = await service.ensureLocation();
  final current = result.coordinates ?? service.lastKnownLocation;
  if (current != null) {
    yield LatLng(current.latitude, current.longitude);
  } else if (last == null) {
    yield null;
  }

  await service.startLiveTracking(
    distanceFilterMeters: 35,
    accuracy: LocationAccuracy.medium,
  );

  LatLng? previous;
  var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  await for (final c in service.positionStream) {
    final next = LatLng(c.latitude, c.longitude);
    final now = DateTime.now();
    final elapsed = now.difference(lastEmit);

    if (previous != null) {
      final moved = LocationService.distanceBetween(
        previous.latitude,
        previous.longitude,
        next.latitude,
        next.longitude,
      );
      if (moved < 25 && elapsed.inMilliseconds < 2500) continue;
    } else if (elapsed.inMilliseconds < 800) {
      continue;
    }

    previous = next;
    lastEmit = now;
    yield next;
  }
});

final liveCoordinatesProvider = Provider<Coordinates?>((ref) {
  final async = ref.watch(liveLocationProvider);
  return async.whenOrNull(
    data: (ll) => ll == null
        ? null
        : Coordinates(latitude: ll.latitude, longitude: ll.longitude),
  );
});

/// Seau ~110 m — change rarement, évite de refetch Overpass à chaque GPS tick.
final locationBucketProvider = Provider<LatLng?>((ref) {
  final loc = ref.watch(liveLocationProvider).valueOrNull;
  if (loc == null) return null;
  return LatLng(
    double.parse(loc.latitude.toStringAsFixed(3)),
    double.parse(loc.longitude.toStringAsFixed(3)),
  );
});

bool _isOpenNow(Pharmacy p) => p.isOpen == true || p.isDuty == true;

/// Résultat de recherche locale (pharmacies + métadonnées UI).
class NearbyPharmaciesResult {
  final List<Pharmacy> pharmacies;
  final double radiusKm;
  final String? message;

  const NearbyPharmaciesResult({
    required this.pharmacies,
    required this.radiusKm,
    this.message,
  });

  bool get isEmpty => pharmacies.isEmpty;
  bool get needsWiderRadius => pharmacies.isEmpty;

  static const empty = NearbyPharmaciesResult(pharmacies: [], radiusKm: 0);
}

/// Cache process : une fois des pharmacies trouvées pour un rayon, on ne
/// relance Overpass que si le rayon **augmente** ou si l’utilisateur force.
class _NearbyCache {
  List<Pharmacy> pharmacies = const [];
  double radiusKm = 0;
  double? lat;
  double? lng;
  DateTime? at;
}

final _nearbyCacheProvider = Provider<_NearbyCache>((ref) => _NearbyCache());

/// Pharmacies autour de l’utilisateur.
/// - utilise uniquement le rayon **validé** (pas le slider en cours)
/// - stoppe les recherches une fois des résultats trouvés
/// - redemande seulement si le rayon augmente / refresh forcé / déplacement fort
final nearbyPharmaciesProvider =
    FutureProvider.autoDispose<NearbyPharmaciesResult>((ref) async {
  final link = ref.keepAlive();
  Timer? disposeTimer;
  ref.onCancel(() {
    disposeTimer = Timer(const Duration(seconds: 120), link.close);
  });
  ref.onResume(() => disposeTimer?.cancel());
  ref.onDispose(() => disposeTimer?.cancel());

  final bucket = ref.watch(locationBucketProvider);
  final radiusKm = ref.watch(committedSearchRadiusKmProvider).clamp(1.0, 15.0);
  final forceToken = ref.watch(pharmacySearchForceTokenProvider);
  if (bucket == null) {
    return const NearbyPharmaciesResult(
      pharmacies: [],
      radiusKm: 0,
      message: 'Position GPS requise',
    );
  }

  ref.read(effectiveRadiusKmProvider.notifier).state = radiusKm;
  final cache = ref.read(_nearbyCacheProvider);

  final sameArea = cache.lat != null &&
      cache.lng != null &&
      LocationService.distanceBetween(
            cache.lat!,
            cache.lng!,
            bucket.latitude,
            bucket.longitude,
          ) <
          300;

  // Déjà des résultats pour un rayon ≥ demandé → filtre local, pas de re-fetch.
  if (forceToken == 0 &&
      sameArea &&
      cache.pharmacies.isNotEmpty &&
      cache.radiusKm + 0.05 >= radiusKm &&
      cache.at != null &&
      DateTime.now().difference(cache.at!).inMinutes < 20) {
    final filtered = cache.pharmacies
        .where(
          (p) =>
              p.isPlatform ||
              (p.distanceMeters ?? 0) <= radiusKm * 1000 + 40,
        )
        .toList();
    // Toujours réinjecter les pharmacies plateforme (ajouts admin récents).
    final merged = await _mergeFreshPlatform(
      filtered,
      bucket.latitude,
      bucket.longitude,
    );
    return NearbyPharmaciesResult(
      pharmacies: _sortPharmacies(merged),
      radiusKm: radiusKm,
      message: merged.isEmpty
          ? 'Aucune pharmacie dans ce rayon — augmentez le rayon de recherche.'
          : null,
    );
  }

  // Résultats déjà trouvés et rayon non augmenté → ne pas relancer.
  if (forceToken == 0 &&
      sameArea &&
      cache.pharmacies.isNotEmpty &&
      radiusKm <= cache.radiusKm + 0.05) {
    return NearbyPharmaciesResult(
      pharmacies: _sortPharmacies(cache.pharmacies),
      radiusKm: cache.radiusKm,
    );
  }

  final list = await ApiService.instance.getNearbyPharmacies(
    latitude: bucket.latitude,
    longitude: bucket.longitude,
    radiusKm: radiusKm,
  );

  final sorted = _sortPharmacies(list);
  cache.pharmacies = sorted;
  cache.radiusKm = radiusKm;
  cache.lat = bucket.latitude;
  cache.lng = bucket.longitude;
  cache.at = DateTime.now();

  // Consommer le token de force (évite boucle).
  if (forceToken != 0) {
    Future.microtask(() {
      if (ref.read(pharmacySearchForceTokenProvider) == forceToken) {
        ref.read(pharmacySearchForceTokenProvider.notifier).state = 0;
      }
    });
  }

  return NearbyPharmaciesResult(
    pharmacies: sorted,
    radiusKm: radiusKm,
    message: sorted.isEmpty
        ? 'Aucune pharmacie détectée dans ${radiusKm.toStringAsFixed(0)} km. '
            'Augmentez le rayon de recherche.'
        : null,
  );
});

/// Compat : liste seule (écrans qui attendent List&lt;Pharmacy&gt;).
final nearbyPharmaciesListProvider =
    Provider.autoDispose<AsyncValue<List<Pharmacy>>>((ref) {
  return ref.watch(nearbyPharmaciesProvider).whenData((r) => r.pharmacies);
});

List<Pharmacy> _sortPharmacies(List<Pharmacy> list) {
  final sorted = [...list]..sort((a, b) {
      final ao = _isOpenNow(a) ? 0 : 1;
      final bo = _isOpenNow(b) ? 0 : 1;
      if (ao != bo) return ao.compareTo(bo);
      return (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0);
    });
  return sorted
      .map(
        (p) => p.travelTimeSeconds != null
            ? p
            : p.copyWith(
                travelTimeSeconds: RoutingService.estimateUrbanTravelSeconds(
                  p.distanceMeters ?? 0,
                ),
              ),
      )
      .toList();
}

Future<List<Pharmacy>> _mergeFreshPlatform(
  List<Pharmacy> base,
  double lat,
  double lng,
) async {
  try {
    final platform = await PlatformPharmacyRepository.instance
        .listPlatformPharmacies(nearLat: lat, nearLng: lng);
    final byId = {for (final p in base) p.id: p};
    for (final p in platform) {
      byId[p.id] = p.copyWith(isPlatform: true, isVerified: p.isVerified ?? true);
    }
    return byId.values.toList();
  } catch (_) {
    return base;
  }
}
