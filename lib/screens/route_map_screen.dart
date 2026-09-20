import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/responsive.dart';
import '../models/enums.dart';
import '../models/map_style.dart';
import '../models/pharmacy.dart';
import '../models/route_result.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/pharmacy_map.dart';

/// Page plein écran : itinéraire utilisateur → pharmacie (+ raccourcis).
class RouteMapScreen extends StatefulWidget {
  final Pharmacy pharmacy;
  final TravelMode initialMode;

  const RouteMapScreen({
    super.key,
    required this.pharmacy,
    this.initialMode = TravelMode.driving,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _mapController = MapController();
  LatLng? _userLoc;
  TravelMode _mode = TravelMode.driving;
  RouteBundle? _bundle;
  RouteResult? _selected;
  bool _loading = true;
  String? _error;

  // Trafic OFF par défaut : les segments colorés figent souvent la carte
  MapBaseStyle _mapStyle = MapBaseStyle.streets;
  MapDetailOptions _details = const MapDetailOptions(traffic: false);
  bool _layersOpen = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _bootstrap();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final last = LocationService.instance.lastKnownLocation;
    if (last != null && mounted) {
      setState(() => _userLoc = LatLng(last.latitude, last.longitude));
    }

    // Une seule lecture GPS — pas de stream (évite rebuilds qui bloquent zoom/pan)
    try {
      final fresh = await LocationService.instance
          .getCurrentLocation()
          .timeout(const Duration(seconds: 25));
      if (fresh != null && mounted) {
        setState(() => _userLoc = LatLng(fresh.latitude, fresh.longitude));
      }
    } catch (_) {}

    await _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    if (widget.pharmacy.coordinates == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Position de la pharmacie indisponible';
      });
      return;
    }

    if (_userLoc == null) {
      final r = await LocationService.instance.ensureLocation();
      if (r.coordinates != null) {
        _userLoc = LatLng(r.coordinates!.latitude, r.coordinates!.longitude);
      }
    }

    if (_userLoc == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Activez la localisation pour calculer l’itinéraire';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bundle = await ApiService.instance
          .getRouteBundle(
            fromLat: _userLoc!.latitude,
            fromLng: _userLoc!.longitude,
            toLat: widget.pharmacy.coordinates!.latitude,
            toLng: widget.pharmacy.coordinates!.longitude,
            mode: _mode,
          )
          .timeout(const Duration(seconds: 35));

      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _selected = bundle.primary;
        _loading = false;
      });
      _fitAllRoutes();

      if (bundle.primary.label?.contains('Estimation') == true ||
          bundle.primary.geometry.length < 4) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tracé routier indisponible pour le moment — réessayez.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de calculer l’itinéraire';
      });
    }
  }

  List<RouteResult> get _visibleAlternatives {
    final bundle = _bundle;
    if (bundle == null) return const [];
    return bundle.all
        .where((r) => !_isSameRoute(r, _selected))
        .take(3)
        .toList();
  }

  bool _isSameRoute(RouteResult? a, RouteResult? b) {
    if (a == null || b == null) return false;
    return identical(a, b) ||
        (a.label == b.label &&
            (a.distanceMeters - b.distanceMeters).abs() < 1 &&
            a.durationSeconds == b.durationSeconds);
  }

  List<LatLng> _samplePoints(List<LatLng> pts, {int max = 60}) {
    if (pts.length <= max) return pts;
    final step = (pts.length / max).ceil();
    final out = <LatLng>[];
    for (var i = 0; i < pts.length; i += step) {
      out.add(pts[i]);
    }
    if (out.isEmpty || out.last != pts.last) out.add(pts.last);
    return out;
  }

  void _fitCamera(List<LatLng> rawPts, {EdgeInsets? padding}) {
    final pts = _samplePoints(rawPts);
    if (pts.length < 2 || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: padding ??
                EdgeInsets.fromLTRB(
                  40,
                  110,
                  40,
                  Responsive.isPhone(context) ? 300 : 260,
                ),
          ),
        );
      } catch (_) {}
    });
  }

  void _fitAllRoutes() {
    final bundle = _bundle;
    if (bundle == null) return;
    final pts = <LatLng>[];
    for (final r in bundle.all.take(4)) {
      final g = r.geometry;
      final step = g.length > 40 ? (g.length / 40).ceil() : 1;
      for (var i = 0; i < g.length; i += step) {
        pts.add(LatLng(g[i].latitude, g[i].longitude));
      }
    }
    if (_userLoc != null) pts.add(_userLoc!);
    final dest = widget.pharmacy.coordinates;
    if (dest != null) {
      pts.add(LatLng(dest.latitude, dest.longitude));
    }
    _fitCamera(pts);
  }

  void _fitSelected() {
    final route = _selected;
    if (route == null || route.geometry.length < 2) {
      _fitAllRoutes();
      return;
    }
    final pts = <LatLng>[];
    final g = route.geometry;
    final step = g.length > 50 ? (g.length / 50).ceil() : 1;
    for (var i = 0; i < g.length; i += step) {
      pts.add(LatLng(g[i].latitude, g[i].longitude));
    }
    if (_userLoc != null) pts.add(_userLoc!);
    _fitCamera(pts, padding: const EdgeInsets.fromLTRB(40, 100, 40, 280));
  }

  Future<void> _openExternalNav() async {
    if (_userLoc == null || widget.pharmacy.coordinates == null) return;
    final mode = _mode == TravelMode.walking
        ? 'walking'
        : _mode == TravelMode.cycling
            ? 'bicycling'
            : 'driving';
    await launchUrl(
      LocationService.googleMapsDirections(
        fromLat: _userLoc!.latitude,
        fromLng: _userLoc!.longitude,
        toLat: widget.pharmacy.coordinates!.latitude,
        toLng: widget.pharmacy.coordinates!.longitude,
        mode: mode,
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openStreetView() async {
    final c = widget.pharmacy.coordinates;
    if (c == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/@?api=1&map_action=pano'
      '&viewpoint=${c.latitude},${c.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final wide = Responsive.useCompactControls(context);
    final dest = widget.pharmacy.coordinates != null
        ? LatLng(
            widget.pharmacy.coordinates!.latitude,
            widget.pharmacy.coordinates!.longitude,
          )
        : null;
    final panelMaxW = wide ? 440.0 : double.infinity;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: PharmacyMapWidget(
              pharmacies: [widget.pharmacy],
              userLocation: _userLoc,
              initialCenter: _userLoc ?? dest,
              selectedPharmacyId: widget.pharmacy.id,
              route: _selected,
              alternativeRoutes: _visibleAlternatives,
              mapController: _mapController,
              fitToRoute: false,
              followUser: false,
              showUserLocation: true,
              destinationLocation: dest,
              initialZoom: 14,
              mapStyle: _mapStyle,
              detailOptions: _details,
              // Toujours interactif : basculer les flags au déchargement
              // recrée les gestes et peut figer zoom/pan.
              interactive: true,
            ),
          ),
          // Indicateur léger (pas d’overlay plein écran qui peut « coller »)
          if (_loading)
            Positioned(
              top: pad.top + 64,
              left: 24,
              right: 24,
              child: const Material(
                elevation: 2,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Calcul de l’itinéraire…',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: pad.top + 8,
            left: 12,
            right: 12,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? 560 : double.infinity,
                ),
                child: Row(
                  children: [
                    _roundBtn(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(14),
                        color: AppColors.surface,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vers ${widget.pharmacy.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (widget.pharmacy.city != null)
                                Text(
                                  widget.pharmacy.city!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _roundBtn(
                      icon: Icons.layers_rounded,
                      onTap: () => setState(() => _layersOpen = !_layersOpen),
                    ),
                    const SizedBox(width: 8),
                    _roundBtn(
                      icon: Icons.refresh_rounded,
                      onTap: _loading ? null : _loadRoutes,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_layersOpen)
            Positioned(
              top: pad.top + 72,
              right: 12,
              child: _layersPanel(),
            ),
          if (_details.streetView)
            Positioned(
              top: pad.top + (_layersOpen ? 320 : 72),
              right: 12,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                color: AppColors.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _openStreetView,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.streetview_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Street View',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_error != null && !_loading)
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadRoutes,
                      style: FilledButton.styleFrom(
                        padding: Responsive.actionButtonPadding(context),
                      ),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: panelMaxW),
                child: _bottomPanel(pad.bottom),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layersPanel() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surface,
      child: SizedBox(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Type de carte',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final style in MapBaseStyle.values) ...[
                    Expanded(
                      child: _styleChip(
                        label: style.label,
                        selected: _mapStyle == style,
                        icon: style == MapBaseStyle.satellite
                            ? Icons.satellite_alt_rounded
                            : Icons.map_rounded,
                        onTap: () => setState(() => _mapStyle = style),
                      ),
                    ),
                    if (style != MapBaseStyle.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Détails de la carte',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Trafic', style: TextStyle(fontSize: 13)),
                secondary: const Icon(Icons.traffic_rounded, size: 20),
                value: _details.traffic,
                onChanged: (v) =>
                    setState(() => _details = _details.copyWith(traffic: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Transport en commun',
                  style: TextStyle(fontSize: 13),
                ),
                secondary: const Icon(Icons.directions_bus_rounded, size: 20),
                value: _details.transit,
                onChanged: (v) =>
                    setState(() => _details = _details.copyWith(transit: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title:
                    const Text('Street View', style: TextStyle(fontSize: 13)),
                secondary: const Icon(Icons.streetview_rounded, size: 20),
                value: _details.streetView,
                onChanged: (v) => setState(
                  () => _details = _details.copyWith(streetView: v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styleChip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: 0.12)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? AppColors.primaryBlue
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundBtn({required IconData icon, VoidCallback? onTap}) {
    return Material(
      elevation: 3,
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _bottomPanel(double bottomPad) {
    final pad = Responsive.actionButtonPadding(context);
    final routes = _bundle?.all ?? const <RouteResult>[];
    final maxH = MediaQuery.sizeOf(context).height * 0.52;

    return Material(
      elevation: 12,
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _modeSelector(),
              const SizedBox(height: 12),
              if (_selected != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: _infoTile(
                        Icons.schedule_rounded,
                        _selected!.durationFormatted,
                        'Durée ${_mode.displayName.toLowerCase()}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _infoTile(
                        Icons.straighten_rounded,
                        _selected!.distanceFormatted,
                        'Distance',
                      ),
                    ),
                  ],
                ),
                if (_selected!.hasCongestion && _details.traffic) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.traffic_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selected!.congestionSummary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (routes.length > 1) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Itinéraires & raccourcis (${routes.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: routes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _routeOptionCard(
                        routes[i],
                        isPrimary: i == 0 && !routes[i].isShortcut,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Responsive.actionRow(
                  context,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openExternalNav,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('GPS externe'),
                      style: OutlinedButton.styleFrom(padding: pad),
                    ),
                    FilledButton.icon(
                      onPressed: _fitAllRoutes,
                      icon: const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text('Voir le trajet'),
                      style: FilledButton.styleFrom(
                        padding: pad,
                        backgroundColor: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeSelector() {
    const modes = [
      TravelMode.driving,
      TravelMode.moto,
      TravelMode.cycling,
      TravelMode.walking,
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: modes.map((m) {
          final selected = _mode == m;
          return Expanded(
            child: Material(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              elevation: selected ? 1 : 0,
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: _loading
                    ? null
                    : () {
                        setState(() => _mode = m);
                        _loadRoutes();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: [
                      Text(m.icon, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        m.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _infoTile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeOptionCard(RouteResult route, {bool isPrimary = false}) {
    final selected = _isSameRoute(_selected, route);
    return Material(
      color: selected
          ? AppColors.primaryBlue.withValues(alpha: 0.12)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _selected = route);
          _fitSelected();
        },
        child: Container(
          width: 148,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : AppColors.border.withValues(alpha: 0.6),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.label ?? (isPrimary ? 'Recommandé' : 'Alternative'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                route.durationFormatted,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                route.distanceFormatted,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
