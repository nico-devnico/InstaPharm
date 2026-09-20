import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/nav_utils.dart';
import '../core/utils/pharmacy_detail_nav.dart';
import '../core/utils/responsive.dart';
import '../models/pharmacy.dart';
import '../providers/location_providers.dart';
import '../providers/preferences_provider.dart';
import '../services/location_service.dart';
import '../services/user_activity_repository.dart';
import '../widgets/pharmacy_map.dart';
import '../widgets/pharmacy_card.dart';
import '../widgets/skeleton_widgets.dart';
import '../widgets/state_widgets.dart';
import 'main_shell.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = DraggableScrollableController();
  final _mapController = MapController();
  String _selectedFilter = 'all';
  String? _selectedPharmacyId;
  bool _followUser = true;
  bool _activatingGps = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _activateGps() async {
    if (_activatingGps) return;
    setState(() => _activatingGps = true);
    try {
      final result = await LocationService.instance.ensureLocation();
      if (!mounted) return;
      if (result.isSuccess) {
        ref.invalidate(liveLocationProvider);
        _forcePharmacySearch();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position obtenue')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ??
                  'Impossible d’obtenir la position. Réessayez.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
        ref.invalidate(liveLocationProvider);
      }
    } catch (_) {
      // ignore — on réinitialise toujours le flag ci-dessous
    } finally {
      if (mounted) {
        setState(() => _activatingGps = false);
      } else {
        _activatingGps = false;
      }
    }
  }

  void _forcePharmacySearch() {
    ref.read(pharmacySearchForceTokenProvider.notifier).update((n) => n + 1);
    ref.invalidate(nearbyPharmaciesProvider);
  }

  List<Pharmacy> _pharmaciesOf(AsyncValue<NearbyPharmaciesResult> async) =>
      async.valueOrNull?.pharmacies ?? const [];

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(liveLocationProvider);
    final location = locationAsync.valueOrNull;
    final pharmaciesAsync = ref.watch(nearbyPharmaciesProvider);
    final wide = Responsive.isWide(context);

    ref.listen(liveLocationProvider, (prev, next) {
      final loc = next.valueOrNull;
      if (loc == null || !_followUser) return;
      // Ne déplace la carte que si le déplacement est sensible (évite jank)
      final prevLoc = prev?.valueOrNull;
      if (prevLoc != null) {
        final d = LocationService.distanceBetween(
          prevLoc.latitude,
          prevLoc.longitude,
          loc.latitude,
          loc.longitude,
        );
        if (d < 20) return;
      }
      try {
        _mapController.move(loc, _mapController.camera.zoom);
      } catch (_) {}
    });

    if (location == null && !locationAsync.isLoading) {
      if (_activatingGps) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Demande de localisation…'),
              ],
            ),
          ),
        );
      }
      return Scaffold(
        body: EmptyState(
          icon: Icons.location_off_rounded,
          title: 'Position GPS requise',
          subtitle: kIsWeb
              ? 'Autorisez la localisation dans votre navigateur '
                  '(popup ou icône 🔒 / ⓘ à gauche de l’URL), '
                  'puis cliquez sur le bouton ci-dessous.'
              : 'Activez la localisation de cet appareil pour détecter '
                  'automatiquement les pharmacies autour de vous.',
          actionLabel: 'Activer le GPS',
          onAction: _activateGps,
        ),
      );
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  _buildMap(location, pharmaciesAsync),
                  _buildTopBar(context, floating: true),
                  _buildRadiusChip(),
                  _buildMapControls(),
                ],
              ),
            ),
            Container(
              width: Responsive.sidePanelWidth(context),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: _buildSidePanel(location, pharmaciesAsync),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _buildMap(location, pharmaciesAsync),
          _buildTopBar(context),
          _buildRadiusChip(),
          _buildMapControls(),
          _buildBottomSheet(location, pharmaciesAsync),
        ],
      ),
    );
  }

  Widget _buildMap(
    LatLng? location,
    AsyncValue<NearbyPharmaciesResult> pharmaAsync,
  ) {
    final pharmacies = _pharmaciesOf(pharmaAsync);
    final radiusKm = ref.watch(committedSearchRadiusKmProvider).clamp(1.0, 15.0);
    return Positioned.fill(
      child: RepaintBoundary(
        child: PharmacyMapWidget(
          pharmacies: pharmacies,
          userLocation: location,
          initialCenter: location,
          mapController: _mapController,
          selectedPharmacyId: _selectedPharmacyId,
          followUser: false, // suivi géré ici avec seuil
          searchRadiusKm: radiusKm,
          initialZoom: radiusKm <= 1.5 ? 14.8 : (radiusKm <= 3 ? 13.5 : 12.2),
          maxPharmacyMarkers: 50,
          onPharmacyTap: (p) {
            setState(() => _selectedPharmacyId = p.id);
            if (!Responsive.isWide(context)) {
              try {
                _scrollController.animateTo(
                  0.5,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              } catch (_) {}
            }
            _showPharmacyDetail(p);
          },
          showUserLocation: true,
        ),
      ),
    );
  }

  Widget _buildRadiusChip() {
    final radius = ref.watch(searchRadiusKmProvider);
    final result = ref.watch(nearbyPharmaciesProvider);
    final pharmacies = result.valueOrNull?.pharmacies ?? const [];
    final searching = result.isLoading;
    final openCount = pharmacies
        .where((p) => p.isOpen == true || p.isDuty == true)
        .length;
    final total = pharmacies.length;
    final needWider = result.valueOrNull?.needsWiderRadius == true;

    return Positioned(
      left: Responsive.padH(context),
      top: MediaQuery.paddingOf(context).top + 108,
      right: Responsive.padH(context),
      child: Material(
        color: AppColors.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    searching
                        ? Icons.hourglass_top_rounded
                        : Icons.radar_rounded,
                    size: 18,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      searching
                          ? 'Recherche dans ${radius.toStringAsFixed(0)} km…'
                          : 'Rayon ${radius.toStringAsFixed(0)} km',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: total > 0
                          ? (openCount > 0
                              ? AppColors.accentGreen.withValues(alpha: 0.14)
                              : AppColors.primaryBlue.withValues(alpha: 0.12))
                          : AppColors.accentOrange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      searching
                          ? '…'
                          : total == 0
                              ? 'Aucune pharmacie'
                              : '$total trouvée${total > 1 ? 's' : ''}'
                                  '${openCount > 0 ? ' · $openCount ouverte${openCount > 1 ? 's' : ''}' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: total > 0
                            ? (openCount > 0
                                ? AppColors.accentGreen
                                : AppColors.primaryBlue)
                            : AppColors.accentOrange,
                      ),
                    ),
                  ),
                ],
              ),
              if (needWider && !searching) ...[
                const SizedBox(height: 8),
                Text(
                  result.valueOrNull?.message ??
                      'Augmentez le rayon pour détecter des pharmacies.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              Slider(
                value: radius.clamp(1, 15),
                min: 1,
                max: 15,
                divisions: 14,
                label: '${radius.round()} km',
                onChanged: (v) {
                  ref.read(searchRadiusKmProvider.notifier).state = v;
                },
                onChangeEnd: (v) {
                  final prev = ref.read(committedSearchRadiusKmProvider);
                  ref.read(searchRadiusKmProvider.notifier).state = v;
                  ref.read(committedSearchRadiusKmProvider.notifier).state = v;
                  ref.read(effectiveRadiusKmProvider.notifier).state = v;
                  final hasResults = (ref
                              .read(nearbyPharmaciesProvider)
                              .valueOrNull
                              ?.pharmacies
                              .isNotEmpty ??
                          false);
                  // Relance uniquement si élargissement ou aucune pharmacie encore.
                  if (!hasResults || v > prev + 0.05) {
                    ref.invalidate(nearbyPharmaciesProvider);
                  } else {
                    // Réduction de rayon : filtre local via cache.
                    ref.invalidate(nearbyPharmaciesProvider);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: Responsive.padH(context),
      bottom: Responsive.isWide(context) ? 24 : MediaQuery.of(context).size.height * 0.34,
      child: Column(
        children: [
          _fab(
            icon: _followUser ? Icons.gps_fixed : Icons.gps_not_fixed,
            color: _followUser ? AppColors.accentGreen : AppColors.primaryBlue,
            onTap: () async {
              setState(() => _followUser = true);
              final loc = await LocationService.instance.getCurrentLocation();
              if (loc != null) {
                _mapController.move(
                  LatLng(loc.latitude, loc.longitude),
                  15.5,
                );
              }
              ref.invalidate(liveLocationProvider);
              _forcePharmacySearch();
            },
          ),
          const SizedBox(height: 10),
          _fab(
            icon: Icons.refresh_rounded,
            onTap: _forcePharmacySearch,
          ),
        ],
      ),
    );
  }

  Widget _fab({
    required IconData icon,
    required VoidCallback onTap,
    Color color = AppColors.primaryBlue,
  }) {
    return Material(
      elevation: 3,
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: color),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, {bool floating = false}) {
    final padH = Responsive.padH(context);
    final isSmall = Responsive.isSmall(context);

    return Positioned(
      top: 0,
      left: 0,
      right: floating ? 0 : 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(padH, isSmall ? 6 : 10, padH, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withValues(alpha: 0.95),
                AppColors.background.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'InstaPharm',
                    style: AppTypography.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.my_location_rounded,
                            size: 14, color: AppColors.accentGreen),
                        SizedBox(width: 4),
                        Text(
                          'Position active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () =>
                    ref.read(shellIndexProvider.notifier).state = 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: AppColors.textTertiary,
                          size: Responsive.icon(context, 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Rechercher un médicament…',
                          style: AppTypography.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Text(
                        'Stock partenaires',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(
    LatLng? location,
    AsyncValue<NearbyPharmaciesResult> pharmaAsync,
  ) {
    final count = pharmaAsync.valueOrNull?.pharmacies.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pharmacies autour de vous',
                  style: AppTypography.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null) _countBadge(count),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Ouvertes en premier · statut en temps réel',
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _filtersRow(),
        Expanded(child: _pharmacyList(pharmaAsync)),
      ],
    );
  }

  Widget _countBadge(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _filtersRow() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        children: [
          _buildFilterChip('all', 'Toutes', Icons.format_list_bulleted_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('open', 'Ouvertes', Icons.schedule_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('duty', 'De garde', Icons.local_hospital_rounded),
          const SizedBox(width: 8),
          _buildFilterChip('verified', 'Vérifiées', Icons.verified_rounded),
        ],
      ),
    );
  }

  Widget _pharmacyList(AsyncValue<NearbyPharmaciesResult> pharmaAsync) {
    return pharmaAsync.when(
      loading: () => ListView(
        children: List.generate(4, (_) => const PharmacyCardSkeleton()),
      ),
      error: (e, _) => ErrorState(
        message: e.toString(),
        onAction: () {
          _forcePharmacySearch();
          ref.invalidate(liveLocationProvider);
        },
      ),
      data: (result) {
        final list = result.pharmacies;
        final filtered = _applyFilter(list);
        if (filtered.isEmpty) {
          final hasClosed = list.any(
            (p) => p.isOpen == false && p.isDuty != true,
          );
          return EmptyState(
            icon: Icons.local_pharmacy_outlined,
            title: list.isEmpty
                ? 'Aucune pharmacie à proximité'
                : (_selectedFilter == 'open'
                    ? 'Aucune pharmacie ouverte'
                    : 'Aucun résultat pour ce filtre'),
            subtitle: list.isEmpty
                ? (result.message ??
                    'Augmentez le rayon de recherche ou déplacez-vous.')
                : (_selectedFilter == 'open' && (hasClosed || list.isNotEmpty)
                    ? 'Des pharmacies sont à proximité (y compris fermées). '
                        'Choisissez « Toutes » pour les voir.'
                    : 'Essayez un autre filtre ou augmentez le rayon.'),
            actionLabel: list.isEmpty &&
                    ref.read(committedSearchRadiusKmProvider) < 15
                ? 'Élargir à ${(ref.read(committedSearchRadiusKmProvider) + 2).clamp(1, 15).round()} km'
                : null,
            onAction: list.isEmpty &&
                    ref.read(committedSearchRadiusKmProvider) < 15
                ? () {
                    final next = (ref.read(committedSearchRadiusKmProvider) + 2)
                        .clamp(1.0, 15.0);
                    ref.read(searchRadiusKmProvider.notifier).state = next;
                    ref.read(committedSearchRadiusKmProvider.notifier).state =
                        next;
                    ref.invalidate(nearbyPharmaciesProvider);
                  }
                : null,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (_, i) {
            final p = filtered[i];
            return PharmacyCard(
              pharmacy: p,
              onTap: () => _showPharmacyDetail(p),
              onRouteTap: () => _showPharmacyDetail(p, showRoute: true),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomSheet(
    LatLng? location,
    AsyncValue<NearbyPharmaciesResult> pharmaAsync,
  ) {
    return DraggableScrollableSheet(
      controller: _scrollController,
      initialChildSize: 0.30,
      minChildSize: 0.16,
      maxChildSize: 0.84,
      snap: true,
      snapSizes: const [0.16, 0.30, 0.58, 0.84],
      builder: (context, scrollController) {
        final count = pharmaAsync.valueOrNull?.pharmacies.length;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.10),
                blurRadius: 32,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pharmacies à proximité',
                          style: AppTypography.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (count != null) _countBadge(count),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _filtersRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              pharmaAsync.when(
                loading: () => SliverToBoxAdapter(
                  child: Column(
                    children: List.generate(
                      3,
                      (_) => const PharmacyCardSkeleton(),
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ErrorState(
                      message: e.toString(),
                      onAction: _forcePharmacySearch,
                    ),
                  ),
                ),
                data: (result) {
                  final list = result.pharmacies;
                  final filtered = _applyFilter(list);
                  if (filtered.isEmpty) {
                    return SliverToBoxAdapter(
                      child: SizedBox(
                        height: 240,
                        child: EmptyState(
                          icon: Icons.local_pharmacy_outlined,
                          title: list.isEmpty
                              ? 'Aucune pharmacie trouvée'
                              : (_selectedFilter == 'open'
                                  ? 'Aucune pharmacie ouverte'
                                  : 'Aucun résultat pour ce filtre'),
                          subtitle: list.isEmpty
                              ? (result.message ??
                                  'Augmentez le rayon de recherche.')
                              : (_selectedFilter == 'open'
                                  ? 'Des pharmacies sont à proximité. '
                                      'Choisissez « Toutes » pour les voir.'
                                  : 'Essayez un autre filtre.'),
                          actionLabel: list.isEmpty &&
                                  ref.read(committedSearchRadiusKmProvider) < 15
                              ? 'Élargir le rayon'
                              : null,
                          onAction: list.isEmpty &&
                                  ref.read(committedSearchRadiusKmProvider) < 15
                              ? () {
                                  final next =
                                      (ref.read(committedSearchRadiusKmProvider) +
                                              2)
                                          .clamp(1.0, 15.0);
                                  ref
                                      .read(searchRadiusKmProvider.notifier)
                                      .state = next;
                                  ref
                                      .read(
                                          committedSearchRadiusKmProvider.notifier)
                                      .state = next;
                                  ref.invalidate(nearbyPharmaciesProvider);
                                }
                              : null,
                        ),
                      ),
                    );
                  }
                  return SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return PharmacyCard(
                        pharmacy: p,
                        onTap: () => _showPharmacyDetail(p),
                        onRouteTap: () =>
                            _showPharmacyDetail(p, showRoute: true),
                      );
                    },
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String key, String label, IconData icon) {
    final selected = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Pharmacy> _applyFilter(List<Pharmacy> list) {
    switch (_selectedFilter) {
      case 'open':
        return list
            .where((p) => p.isOpen == true || p.isDuty == true)
            .toList();
      case 'duty':
        return list.where((p) => p.isDuty == true).toList();
      case 'verified':
        return list.where((p) => p.isVerified == true).toList();
      default:
        return list;
    }
  }

  Future<void> _showPharmacyDetail(Pharmacy p, {bool showRoute = false}) async {
    setState(() {
      _selectedPharmacyId = p.id;
      _followUser = false;
    });
    unawaited(UserActivityRepository.instance.logPharmacyView(p));

    if (showRoute) {
      await openPharmacyRoute(context, pharmacy: p);
      return;
    }

    await showPharmacyDetailOverlay(context, pharmacy: p);
    if (!mounted) return;
    setState(() => _selectedPharmacyId = null);
  }
}
