import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme/app_colors.dart';
import '../models/pharmacy.dart';
import '../models/enums.dart';
import '../models/map_style.dart';
import '../models/route_result.dart';
import '../models/coordinates.dart';
import '../services/routing_service.dart';

class PharmacyMapWidget extends StatefulWidget {
  final List<Pharmacy> pharmacies;
  final LatLng? initialCenter;
  final String? selectedPharmacyId;
  final RouteResult? route;
  final List<RouteResult> alternativeRoutes;
  final Function(Pharmacy)? onPharmacyTap;
  final MapController? mapController;
  final bool showUserLocation;
  final LatLng? userLocation;
  final LatLng? courierLocation;
  final LatLng? destinationLocation;
  final List<Coordinates>? deliveryRouteGeometry;
  final double deliveryProgress;
  final bool fitToRoute;
  final bool followUser;
  final double? initialZoom;
  final double? searchRadiusKm;
  final MapBaseStyle mapStyle;
  final MapDetailOptions detailOptions;
  final int maxPharmacyMarkers;

  /// Si false, la carte ignore le zoom/pan (overlay).
  final bool interactive;

  const PharmacyMapWidget({
    super.key,
    required this.pharmacies,
    this.initialCenter,
    this.selectedPharmacyId,
    this.route,
    this.alternativeRoutes = const [],
    this.onPharmacyTap,
    this.mapController,
    this.showUserLocation = true,
    this.userLocation,
    this.courierLocation,
    this.destinationLocation,
    this.deliveryRouteGeometry,
    this.deliveryProgress = 0,
    this.fitToRoute = false,
    this.followUser = false,
    this.initialZoom,
    this.searchRadiusKm,
    this.mapStyle = MapBaseStyle.streets,
    this.detailOptions = const MapDetailOptions(),
    this.maxPharmacyMarkers = 60,
    this.interactive = true,
  });

  @override
  State<PharmacyMapWidget> createState() => _PharmacyMapWidgetState();
}

class _PharmacyMapWidgetState extends State<PharmacyMapWidget> {
  late final MapController _controller;
  late final bool _ownsController;
  bool _didFit = false;

  List<Marker>? _cachedPharmacyMarkers;
  List<String>? _markerSignature;

  List<Polyline>? _cachedRoutePolylines;
  Object? _routeCacheKey;
  List<Polyline>? _cachedAltPolylines;
  Object? _altCacheKey;

  // Pas de rotation : elle concurrence souvent pinch-zoom et donne l’impression
  // que la carte « plante ».
  static const _interactionFlags =
      InteractiveFlag.all & ~InteractiveFlag.rotate;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.mapController == null;
    _controller = widget.mapController ?? MapController();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PharmacyMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pharmacies != oldWidget.pharmacies ||
        widget.selectedPharmacyId != oldWidget.selectedPharmacyId) {
      _cachedPharmacyMarkers = null;
      _markerSignature = null;
    }
    if (widget.route != oldWidget.route ||
        widget.detailOptions.traffic != oldWidget.detailOptions.traffic) {
      _cachedRoutePolylines = null;
      _routeCacheKey = null;
    }
    if (widget.alternativeRoutes != oldWidget.alternativeRoutes) {
      _cachedAltPolylines = null;
      _altCacheKey = null;
    }

    // Fit une seule fois (évite de voler le contrôle zoom/pan à l’utilisateur)
    if (widget.fitToRoute && !_didFit) {
      final geo = widget.deliveryRouteGeometry;
      final hasRoute = (geo != null && geo.length >= 2) ||
          (widget.route != null && widget.route!.geometry.length >= 2);
      if (hasRoute) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_didFit) _fitBounds();
        });
      }
    }

    if (widget.followUser &&
        widget.userLocation != null &&
        oldWidget.userLocation != widget.userLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          final z = _controller.camera.zoom;
          _controller.move(widget.userLocation!, z < 13 ? 15 : z);
        } catch (_) {}
      });
    }
  }

  void _fitBounds() {
    final pts = <LatLng>[];
    void addCoords(List<Coordinates> list) {
      final step = list.length > 80 ? (list.length / 80).ceil() : 1;
      for (var i = 0; i < list.length; i += step) {
        pts.add(LatLng(list[i].latitude, list[i].longitude));
      }
      if (list.isNotEmpty) {
        final last = list.last;
        pts.add(LatLng(last.latitude, last.longitude));
      }
    }

    final geo = widget.deliveryRouteGeometry;
    if (geo != null) addCoords(geo);
    if (widget.route != null) addCoords(widget.route!.geometry);
    for (final alt in widget.alternativeRoutes.take(3)) {
      addCoords(alt.geometry);
    }
    if (widget.userLocation != null) pts.add(widget.userLocation!);
    if (widget.courierLocation != null) pts.add(widget.courierLocation!);
    if (widget.destinationLocation != null) {
      pts.add(widget.destinationLocation!);
    }
    for (final p in widget.pharmacies.take(widget.maxPharmacyMarkers)) {
      if (p.coordinates != null) {
        pts.add(LatLng(p.coordinates!.latitude, p.coordinates!.longitude));
      }
    }
    if (pts.length < 2) return;
    try {
      final bounds = LatLngBounds.fromPoints(pts);
      _controller.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
      _didFit = true;
    } catch (_) {}
  }

  List<Marker> _pharmacyMarkers() {
    final sig = <String>[
      widget.selectedPharmacyId ?? '',
      ...widget.pharmacies.take(widget.maxPharmacyMarkers).map((p) => p.id),
    ];
    if (_cachedPharmacyMarkers != null &&
        _markerSignature != null &&
        _listEquals(_markerSignature!, sig)) {
      return _cachedPharmacyMarkers!;
    }
    final markers = widget.pharmacies
        .take(widget.maxPharmacyMarkers)
        .where((p) => p.coordinates != null)
        .map(_buildMarker)
        .toList(growable: false);
    _cachedPharmacyMarkers = markers;
    _markerSignature = sig;
    return markers;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<LatLng> _decimate(List<LatLng> points, {int maxPoints = 100}) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final out = <LatLng>[];
    for (var i = 0; i < points.length; i += step) {
      out.add(points[i]);
    }
    if (out.isEmpty || out.last != points.last) out.add(points.last);
    return out;
  }

  List<Polyline> _routePolylines() {
    final route = widget.route;
    if (route == null || route.geometry.length < 2) return const [];

    final key = (
      route.label,
      route.distanceMeters,
      route.durationSeconds,
      route.geometry.length,
      widget.detailOptions.traffic,
      route.trafficSegments.length,
    );
    if (_cachedRoutePolylines != null && _routeCacheKey == key) {
      return _cachedRoutePolylines!;
    }

    final List<Polyline> lines;
    if (widget.detailOptions.traffic && route.trafficSegments.isNotEmpty) {
      lines = _trafficPolylines(route);
    } else {
      lines = [
        Polyline(
          points: _decimate(
            route.geometry.map((c) => LatLng(c.latitude, c.longitude)).toList(),
          ),
          color: AppColors.primaryBlue,
          strokeWidth: 5,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ),
      ];
    }
    _cachedRoutePolylines = lines;
    _routeCacheKey = key;
    return lines;
  }

  List<Polyline> _altPolylines() {
    final alts = widget.alternativeRoutes;
    if (alts.isEmpty) return const [];
    final key = alts
        .take(3)
        .map((r) => '${r.label}|${r.distanceMeters}|${r.geometry.length}')
        .join(';');
    if (_cachedAltPolylines != null && _altCacheKey == key) {
      return _cachedAltPolylines!;
    }
    final lines = <Polyline>[];
    for (var i = 0; i < alts.length && i < 3; i++) {
      final g = alts[i].geometry;
      if (g.length < 2) continue;
      lines.add(
        Polyline(
          points: _decimate(
            g.map((c) => LatLng(c.latitude, c.longitude)).toList(),
            maxPoints: 80,
          ),
          color: _altColor(i).withValues(alpha: 0.7),
          strokeWidth: 4,
        ),
      );
    }
    _cachedAltPolylines = lines;
    _altCacheKey = key;
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter ??
        widget.courierLocation ??
        widget.userLocation ??
        const LatLng(4.0511, 9.7679);

    final deliveryGeo = widget.deliveryRouteGeometry;
    final hasDeliveryRoute = deliveryGeo != null && deliveryGeo.length >= 2;
    final progress = widget.deliveryProgress.clamp(0.0, 1.0);

    List<LatLng> completed = const [];
    List<LatLng> remaining = const [];
    if (hasDeliveryRoute) {
      completed = _decimate(
        RoutingService.completedGeometry(deliveryGeo, progress)
            .map((c) => LatLng(c.latitude, c.longitude))
            .toList(),
        maxPoints: 80,
      );
      remaining = _decimate(
        RoutingService.remainingGeometry(deliveryGeo, progress)
            .map((c) => LatLng(c.latitude, c.longitude))
            .toList(),
        maxPoints: 80,
      );
    }

    final altLines = _altPolylines();
    final routeLines = _routePolylines();

    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: widget.initialZoom ?? 13.5,
        minZoom: 5,
        maxZoom: 18,
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? _interactionFlags : InteractiveFlag.none,
          // false = pinch-zoom fiable (évite la course multi-doigts qui bloque)
          enableMultiFingerGestureRace: false,
        ),
        onMapReady: widget.fitToRoute && !_didFit ? _fitBounds : null,
      ),
      children: [
        TileLayer(
          key: ValueKey(widget.mapStyle),
          urlTemplate: widget.mapStyle.urlTemplate,
          userAgentPackageName: 'com.instapharm.app',
          maxNativeZoom: widget.mapStyle.maxNativeZoom > 17
              ? 17
              : widget.mapStyle.maxNativeZoom,
          keepBuffer: 2,
          panBuffer: 1,
          retinaMode: false,
        ),
        if (widget.detailOptions.transit)
          Opacity(
            opacity: 0.65,
            child: TileLayer(
              urlTemplate: MapDetailOptions.transitTileUrl,
              userAgentPackageName: 'com.instapharm.app',
              maxNativeZoom: 16,
              keepBuffer: 1,
              panBuffer: 0,
              retinaMode: false,
            ),
          ),
        if (widget.showUserLocation &&
            widget.userLocation != null &&
            widget.searchRadiusKm != null &&
            widget.searchRadiusKm! > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: widget.userLocation!,
                radius: widget.searchRadiusKm! * 1000,
                useRadiusInMeter: true,
                color: AppColors.primaryBlue.withValues(alpha: 0.14),
                borderColor: AppColors.primaryBlue.withValues(alpha: 0.45),
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        if (altLines.isNotEmpty) PolylineLayer(polylines: altLines),
        if (routeLines.isNotEmpty) PolylineLayer(polylines: routeLines),
        if (completed.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: completed,
                color: AppColors.textTertiary.withValues(alpha: 0.5),
                strokeWidth: 3.5,
              ),
            ],
          ),
        if (remaining.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: remaining,
                color: AppColors.accentOrange,
                strokeWidth: 4.5,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              ),
            ],
          ),
        MarkerLayer(markers: _pharmacyMarkers()),
        if (widget.showUserLocation && widget.userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.userLocation!,
                width: 22,
                height: 22,
                child: const _UserDot(),
              ),
            ],
          ),
        if (widget.destinationLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.destinationLocation!,
                width: 40,
                height: 40,
                child: const _PinMarker(
                  color: AppColors.accentGreen,
                  icon: Icons.home_rounded,
                ),
              ),
            ],
          ),
        if (widget.courierLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.courierLocation!,
                width: 44,
                height: 44,
                child: const _CourierMarker(),
              ),
            ],
          ),
      ],
    );

    return RepaintBoundary(child: map);
  }

  List<Polyline> _trafficPolylines(RouteResult route) {
    final segs = route.trafficSegments;
    if (segs.isEmpty) {
      return [
        Polyline(
          points: _decimate(
            route.geometry.map((c) => LatLng(c.latitude, c.longitude)).toList(),
          ),
          color: AppColors.primaryBlue,
          strokeWidth: 4.5,
        ),
      ];
    }

    // Limiter le nombre de polylines trafic (évite le freeze)
    final usable = segs.where((s) => s.points.length >= 2).toList();
    final step = usable.length > 24 ? (usable.length / 24).ceil() : 1;
    final lines = <Polyline>[];
    for (var i = 0; i < usable.length; i += step) {
      final s = usable[i];
      lines.add(
        Polyline(
          points: _decimate(
            s.points.map((c) => LatLng(c.latitude, c.longitude)).toList(),
            maxPoints: 24,
          ),
          color: _congestionColor(s.level),
          strokeWidth: s.level.isAlert ? 5.5 : 5,
        ),
      );
    }
    return lines;
  }

  Color _altColor(int index) {
    const palette = [
      Color(0xFF64748B),
      Color(0xFF0EA5E9),
      Color(0xFF8B5CF6),
      Color(0xFF14B8A6),
    ];
    return palette[index % palette.length];
  }

  Color _congestionColor(CongestionLevel level) {
    switch (level) {
      case CongestionLevel.free:
        return const Color(0xFF22C55E);
      case CongestionLevel.slow:
        return const Color(0xFFF59E0B);
      case CongestionLevel.congested:
        return const Color(0xFFEF4444);
      case CongestionLevel.jammed:
        return const Color(0xFF991B1B);
    }
  }

  Marker _buildMarker(Pharmacy p) {
    final isSelected = widget.selectedPharmacyId == p.id;
    final color = _getColor(p.status);
    final size = isSelected ? 44.0 : 34.0;

    return Marker(
      point: LatLng(p.coordinates!.latitude, p.coordinates!.longitude),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => widget.onPharmacyTap?.call(p),
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? color : Colors.white,
              width: isSelected ? 2.5 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.local_pharmacy_rounded,
            color: isSelected ? color : Colors.white,
            size: isSelected ? 22 : 17,
          ),
        ),
      ),
    );
  }

  Color _getColor(PharmacyStatus status) {
    switch (status) {
      case PharmacyStatus.open:
        return AppColors.open;
      case PharmacyStatus.onDuty:
        return AppColors.duty;
      case PharmacyStatus.closed:
        return AppColors.closed;
      case PharmacyStatus.unknown:
        return AppColors.primaryBlue;
    }
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryBlue,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _PinMarker extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _PinMarker({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _CourierMarker extends StatelessWidget {
  const _CourierMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.accentOrange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentOrange.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Icon(
        Icons.two_wheeler_rounded,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}
