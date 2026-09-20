import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/coordinates.dart';

/// Résultat d’une demande de localisation (utile pour feedback UI web).
class LocationResult {
  final Coordinates? coordinates;
  final String? errorMessage;
  final bool permissionDenied;
  final bool serviceDisabled;

  const LocationResult({
    this.coordinates,
    this.errorMessage,
    this.permissionDenied = false,
    this.serviceDisabled = false,
  });

  bool get isSuccess => coordinates != null;
}

/// Géolocalisation GPS réelle (mobile + web navigateur).
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  Coordinates? _lastKnownLocation;
  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<Coordinates>.broadcast();

  Coordinates? get lastKnownLocation => _lastKnownLocation;

  /// Flux partagé des positions GPS.
  Stream<Coordinates> get positionStream => _controller.stream;

  void _emit(Coordinates c) {
    _lastKnownLocation = c;
    if (!_controller.isClosed) _controller.add(c);
  }

  Coordinates _fromPosition(Position position) => Coordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );

  /// Permissions via Geolocator (fonctionne sur web ; permission_handler non).
  Future<bool> requestPermission() async {
    if (kIsWeb) {
      // Sur web, checkPermission peut rester "denied" sans Permissions API.
      // getCurrentPosition déclenche la popup navigateur.
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
        _emit(_fromPosition(pos));
        return true;
      } on LocationServiceDisabledException {
        return false;
      } on PermissionDeniedException {
        return false;
      } catch (_) {
        // Tentative via requestPermission navigateur
        final permission = await Geolocator.requestPermission();
        return permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always;
      }
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      try {
        await openAppSettings();
      } catch (_) {}
      return false;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<bool> isPermissionGranted() async {
    if (kIsWeb) {
      // Si on a déjà une position, OK. Sinon ne pas bloquer (voir getCurrentLocation).
      if (_lastKnownLocation != null) return true;
      try {
        final p = await Geolocator.checkPermission();
        return p == LocationPermission.whileInUse ||
            p == LocationPermission.always;
      } catch (_) {
        return false;
      }
    }
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse ||
        p == LocationPermission.always;
  }

  Future<bool> isServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      // Sur certains navigateurs l’API peut échouer → on laisse tenter getCurrentPosition.
      return kIsWeb;
    }
  }

  /// Demande + récupère la position, avec message d’erreur explicite (web inclus).
  Future<LocationResult> ensureLocation() async {
    try {
      if (!kIsWeb) {
        final enabled = await isServiceEnabled();
        if (!enabled) {
          return const LocationResult(
            serviceDisabled: true,
            errorMessage:
                'Activez le GPS / la localisation dans les réglages de l’appareil.',
          );
        }
      }

      if (kIsWeb) {
        // Déclenche directement la boîte de dialogue du navigateur.
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 25),
        );
        final c = _fromPosition(pos);
        _emit(c);
        await startLiveTracking();
        return LocationResult(coordinates: c);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationResult(
          permissionDenied: true,
          errorMessage:
              'Autorisation de localisation refusée. Autorisez InstaPharm dans les paramètres.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      final c = _fromPosition(position);
      _emit(c);
      await startLiveTracking();
      return LocationResult(coordinates: c);
    } on LocationServiceDisabledException {
      return LocationResult(
        serviceDisabled: true,
        errorMessage: kIsWeb
            ? 'Localisation désactivée dans le navigateur. Autorisez la position pour ce site.'
            : 'Service de localisation désactivé. Activez le GPS.',
      );
    } on PermissionDeniedException {
      return LocationResult(
        permissionDenied: true,
        errorMessage: kIsWeb
            ? 'Permission refusée. Cliquez sur l’icône 🔒 / ⓘ à gauche de l’URL → Autoriser la position, puis réessayez.'
            : 'Permission de localisation refusée.',
      );
    } on TimeoutException {
      return const LocationResult(
        errorMessage:
            'Délai dépassé. Vérifiez que le GPS / la position du navigateur est active.',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('denied') || msg.contains('permission')) {
        return LocationResult(
          permissionDenied: true,
          errorMessage: kIsWeb
              ? 'Le navigateur a bloqué la géolocalisation. Autorisez la position pour ce site (icône à gauche de l’URL).'
              : 'Permission de localisation refusée.',
        );
      }
      if (msg.contains('secure') || msg.contains('only secure')) {
        return const LocationResult(
          errorMessage:
              'La géolocalisation web exige HTTPS ou localhost. Relancez avec flutter run -d chrome.',
        );
      }
      return LocationResult(
        errorMessage: 'Impossible d’obtenir la position : $e',
        coordinates: _lastKnownLocation,
      );
    }
  }

  Future<Coordinates?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    final result = await ensureLocation();
    return result.coordinates ?? _lastKnownLocation;
  }

  Future<Coordinates?> getLastKnownPosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        _emit(_fromPosition(position));
      }
      return _lastKnownLocation;
    } catch (_) {
      return _lastKnownLocation;
    }
  }

  /// Démarre le suivi GPS continu (filtre large pour limiter CPU / rebuilds).
  Future<void> startLiveTracking({
    int distanceFilterMeters = 35,
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    try {
      if (!kIsWeb) {
        final permission =
            await isPermissionGranted() || await requestPermission();
        if (!permission) return;
        if (!await isServiceEnabled()) return;
      }

      await _subscription?.cancel();
      _subscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilterMeters,
        ),
      ).listen(
        (position) => _emit(_fromPosition(position)),
        onError: (_) {},
      );
    } catch (_) {
      // Sur web, le stream peut échouer si permission pas encore accordée.
    }
  }

  Future<void> stopLiveTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static double distanceBetween(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(
      startLat,
      startLng,
      endLat,
      endLng,
    );
  }

  static Uri googleMapsDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    String mode = 'driving',
  }) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$fromLat,$fromLng'
      '&destination=$toLat,$toLng'
      '&travelmode=$mode',
    );
  }

  static Uri osmDirections({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return Uri.parse(
      'https://www.openstreetmap.org/directions?'
      'engine=fossgis_osrm_car'
      '&route=$fromLat%2C$fromLng%3B$toLat%2C$toLng',
    );
  }
}
