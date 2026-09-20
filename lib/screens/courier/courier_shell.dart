import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_providers.dart';
import '../../services/location_service.dart';
import '../../services/staff_repository.dart';
import '../../widgets/pharmacy_map.dart';
import '../profile_screen.dart';

final courierJobsProvider =
    FutureProvider.autoDispose<List<MedicineOrder>>((ref) async {
  ref.watch(authStateProvider);
  return StaffRepository.instance.getCourierJobs(availableOnly: true);
});

class CourierShell extends ConsumerStatefulWidget {
  const CourierShell({super.key});

  @override
  ConsumerState<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends ConsumerState<CourierShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _CourierJobsTab(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.two_wheeler_outlined),
            selectedIcon: Icon(Icons.two_wheeler_rounded),
            label: 'Courses',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _CourierJobsTab extends ConsumerWidget {
  const _CourierJobsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(courierJobsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Courses livreur',
          style: AppTypography.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(courierJobsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Impossible de charger les courses')),
        data: (jobs) {
          if (jobs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucune course disponible pour le moment.\nLes livraisons apparaîtront ici.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(courierJobsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _CourierJobCard(order: jobs[i]),
            ),
          );
        },
      ),
    );
  }
}

class _CourierJobCard extends ConsumerWidget {
  final MedicineOrder order;
  const _CourierJobCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = order.delivery;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.id,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(order.status.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentOrange)),
            ],
          ),
          const SizedBox(height: 6),
          Text(order.pharmacyName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (d != null)
            Text(d.fullAddress,
                style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            '~${d?.estimatedMinutes ?? '—'} min · ${formatFcfa(order.totalXaf)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (order.status != OrderStatus.outForDelivery &&
                  order.status != OrderStatus.delivered)
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final uuid = order.supabaseId;
                      if (uuid == null) return;
                      await StaffRepository.instance.claimDelivery(uuid);
                      ref.invalidate(courierJobsProvider);
                      if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CourierActiveDeliveryScreen(order: order),
                          ),
                        );
                      }
                    },
                    child: const Text('Prendre la course'),
                  ),
                ),
              if (order.status == OrderStatus.outForDelivery) ...[
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              CourierActiveDeliveryScreen(order: order),
                        ),
                      );
                    },
                    child: const Text('Continuer le suivi'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class CourierActiveDeliveryScreen extends ConsumerStatefulWidget {
  final MedicineOrder order;
  const CourierActiveDeliveryScreen({super.key, required this.order});

  @override
  ConsumerState<CourierActiveDeliveryScreen> createState() =>
      _CourierActiveDeliveryScreenState();
}

class _CourierActiveDeliveryScreenState
    extends ConsumerState<CourierActiveDeliveryScreen> {
  late MedicineOrder _order;
  double _progress = 0;
  Timer? _gpsTimer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _progress = _order.delivery?.progress ?? 0;
    LocationService.instance.startLiveTracking();
    _gpsTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      final uuid = _order.supabaseId;
      if (uuid == null) return;
      await StaffRepository.instance.pushLiveLocation(uuid);
    });
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    super.dispose();
  }

  Future<void> _setProgress(double value) async {
    final uuid = _order.supabaseId;
    if (uuid == null) return;
    setState(() {
      _busy = true;
      _progress = value;
    });
    try {
      final loc = await LocationService.instance.getCurrentLocation();
      await StaffRepository.instance.updateCourierProgress(
        orderUuid: uuid,
        progress: value,
        lat: loc?.latitude ??
            _order.delivery?.courierLocation?.latitude ??
            0,
        lng: loc?.longitude ??
            _order.delivery?.courierLocation?.longitude ??
            0,
        etaMinutes: ((1 - value) *
                (_order.delivery?.estimatedMinutes ?? 30))
            .round()
            .clamp(1, 120),
      );
      if (value >= 0.98 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Livraison terminée')),
        );
        ref.invalidate(courierJobsProvider);
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveLocationProvider).valueOrNull;
    final d = _order.delivery;
    final dest = d?.destination != null
        ? LatLng(d!.destination!.latitude, d.destination!.longitude)
        : null;
    final pharmacy = _order.pharmacy;

    return Scaffold(
      appBar: AppBar(
        title: Text('Course ${_order.id}'),
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: PharmacyMapWidget(
              pharmacies: pharmacy != null ? [pharmacy] : const [],
              userLocation: live,
              showUserLocation: true,
              courierLocation: live,
              destinationLocation: dest,
              deliveryRouteGeometry: d?.routeGeometry,
              deliveryProgress: _progress,
              fitToRoute: true,
              followUser: false,
              initialZoom: 14,
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  d?.fullAddress ?? 'Adresse de livraison',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Patient : ${d?.recipientName ?? '—'} · ${d?.phone ?? ''}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Avancement de la livraison',
                  style: AppTypography.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: _progress.clamp(0, 1),
                  onChanged: _busy ? null : (v) => setState(() => _progress = v),
                  onChangeEnd: _busy ? null : _setProgress,
                ),
                Text('${(_progress * 100).round()} %'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _setProgress((_progress + 0.2).clamp(0, 1)),
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Mettre à jour ma position'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _setProgress(1),
                  child: const Text('Confirmer la livraison'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
