import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/currency.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../providers/location_providers.dart';
import '../providers/orders_provider.dart';
import '../services/location_service.dart';
import '../services/order_repository.dart';
import '../widgets/pharmacy_map.dart';
import 'rating_screen.dart';

/// Page entière de suivi transport (données Supabase Realtime).
class OrderTrackingScreen extends ConsumerStatefulWidget {
  final MedicineOrder order;

  const OrderTrackingScreen({super.key, required this.order});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  late MedicineOrder _order;
  StreamSubscription? _sub;
  bool? _alreadyRated;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _bindRealtime();
    _checkRated();
    LocationService.instance.startLiveTracking();
  }

  Future<void> _checkRated() async {
    final id = _order.supabaseId;
    if (id == null) return;
    final rated = await OrderRepository.instance.hasRated(id);
    if (mounted) setState(() => _alreadyRated = rated);
  }

  void _bindRealtime() {
    final uuid = _order.supabaseId;
    if (uuid == null) return;
    _sub = OrderRepository.instance.watchOrder(uuid).listen((row) async {
      if (row.isEmpty || !mounted) return;
      final fresh = await OrderRepository.instance.getOrder(uuid);
      if (fresh != null && mounted) {
        setState(() => _order = fresh);
        if (fresh.status == OrderStatus.delivered) _checkRated();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _callCourier() async {
    final phone = _order.delivery?.courierPhone;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _callPharmacy() async {
    final phone = _order.pharmacy?.phone;
    if (phone == null) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _openExternalNav() async {
    final d = _order.delivery;
    final from = _order.pharmacy?.coordinates ?? d?.courierLocation;
    final to = d?.destination ?? ref.read(liveCoordinatesProvider);
    if (from == null || to == null) return;
    await launchUrl(
      LocationService.googleMapsDirections(
        fromLat: from.latitude,
        fromLng: from.longitude,
        toLat: to.latitude,
        toLng: to.longitude,
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  List<_TimelineStep> get _timeline {
    final s = _order.status;
    final delivery = _order.fulfillment == FulfillmentType.delivery;
    return [
      _TimelineStep('Confirmée', s.index >= OrderStatus.confirmed.index),
      _TimelineStep('Préparation', s.index >= OrderStatus.preparing.index),
      _TimelineStep(
        delivery ? 'En livraison' : 'Prête au retrait',
        delivery
            ? s.index >= OrderStatus.outForDelivery.index
            : s.index >= OrderStatus.readyForPickup.index,
      ),
      _TimelineStep(
        delivery ? 'Livrée' : 'Récupérée',
        s == OrderStatus.delivered,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final livePatient = ref.watch(liveLocationProvider).valueOrNull;
    final d = _order.delivery;
    final pharmacy = _order.pharmacy;
    final isNarrow = MediaQuery.sizeOf(context).width < 380;
    final isLive = _order.status == OrderStatus.outForDelivery;
    final progress = d?.progress ?? 0.0;

    final courierLatLng = d?.courierLocation != null
        ? LatLng(d!.courierLocation!.latitude, d.courierLocation!.longitude)
        : null;
    final destLatLng = livePatient ??
        (d?.destination != null
            ? LatLng(d!.destination!.latitude, d.destination!.longitude)
            : null);
    final pharmacyLatLng = pharmacy?.coordinates != null
        ? LatLng(
            pharmacy!.coordinates!.latitude,
            pharmacy.coordinates!.longitude,
          )
        : null;
    final center = courierLatLng ??
        livePatient ??
        pharmacyLatLng ??
        destLatLng ??
        const LatLng(4.0511, 9.7679);

    final etaMin = d?.estimatedMinutes ?? 0;
    final remainKm = ((d?.liveRemainingMeters ?? d?.routeDistanceMeters ?? 0) *
            (1 - progress)) /
        1000;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            flex: isNarrow ? 5 : 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PharmacyMapWidget(
                    pharmacies: pharmacy != null ? [pharmacy] : const [],
                    initialCenter: center,
                    selectedPharmacyId: pharmacy?.id,
                    mapController: _mapController,
                    showUserLocation: true,
                    userLocation: livePatient,
                    courierLocation:
                        isLive || progress > 0 ? courierLatLng : null,
                    destinationLocation: destLatLng,
                    deliveryRouteGeometry: d?.routeGeometry,
                    deliveryProgress: progress,
                    // Fit une seule fois côté widget (_didFit)
                    fitToRoute: true,
                    followUser: false,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        _circleBtn(Icons.arrow_back_rounded,
                            () => Navigator.pop(context)),
                        const Spacer(),
                        if (isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Suivi live',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: isNarrow ? 11 : 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: isNarrow ? 6 : 5,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 14 : 18,
                  14,
                  isNarrow ? 14 : 18,
                  20,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Suivi du transport',
                    style: TextStyle(
                      fontSize: isNarrow ? 18 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_order.id} · ${_order.status.displayName}',
                    style: TextStyle(
                      fontSize: isNarrow ? 12 : 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._timeline.map((t) => _timelineTile(t, isNarrow)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _metric('ETA', etaMin > 0 ? '~$etaMin min' : '—', isNarrow),
                      _metric(
                        'Restant',
                        remainKm > 0
                            ? '${remainKm.toStringAsFixed(1)} km'
                            : '—',
                        isNarrow,
                      ),
                      _metric(
                        'Total',
                        formatFcfa(_order.totalXaf),
                        isNarrow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoBlock(
                    'Pharmacie',
                    _order.pharmacyName,
                    Icons.local_pharmacy_rounded,
                    isNarrow,
                  ),
                  if (_order.items.isNotEmpty)
                    _infoBlock(
                      'Médicament',
                      _order.items
                          .map((i) =>
                              '${i.medicineName} ×${i.quantity}')
                          .join(', '),
                      Icons.medication_rounded,
                      isNarrow,
                    ),
                  if (d != null)
                    _infoBlock(
                      'Adresse',
                      d.fullAddress,
                      Icons.home_outlined,
                      isNarrow,
                    ),
                  if (d?.courierName != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0x22F97316),
                            child: Icon(Icons.two_wheeler_rounded,
                                color: AppColors.accentOrange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d!.courierName!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  isLive
                                      ? 'Position mise à jour'
                                      : 'Livreur assigné',
                                  style: TextStyle(
                                    fontSize: isNarrow ? 11 : 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (d.courierPhone != null)
                            IconButton.filledTonal(
                              onPressed: _callCourier,
                              icon: const Icon(Icons.phone_rounded),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openExternalNav,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      isNarrow ? 'Google Maps' : 'Ouvrir dans Google Maps',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _order.pharmacy?.phone != null
                              ? _callPharmacy
                              : null,
                          icon: const Icon(Icons.local_pharmacy_outlined,
                              size: 16),
                          label: const Text('Pharmacie',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_order.status == OrderStatus.delivered &&
                          _alreadyRated != true)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RatingScreen(order: _order),
                                ),
                              );
                              if (ok == true) {
                                ref.invalidate(myOrdersProvider);
                                _checkRated();
                              }
                            },
                            icon: const Icon(Icons.star_rounded, size: 16),
                            label: const Text('Noter',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ],
                  ),
                  if (_alreadyRated == true) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Vous avez déjà noté cette livraison.',
                      style: TextStyle(
                        color: AppColors.accentGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon),
        ),
      ),
    );
  }

  Widget _timelineTile(_TimelineStep step, bool isNarrow) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            step.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: isNarrow ? 18 : 20,
            color: step.done ? AppColors.accentGreen : AppColors.border,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontSize: isNarrow ? 13 : 14,
                fontWeight: step.done ? FontWeight.w700 : FontWeight.w500,
                color: step.done
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, bool isNarrow) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: isNarrow ? 12 : 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: isNarrow ? 10 : 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock(
    String label,
    String value,
    IconData icon,
    bool isNarrow,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isNarrow ? 10 : 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isNarrow ? 13 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final bool done;
  const _TimelineStep(this.label, this.done);
}
