import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/currency.dart';
import '../core/utils/nav_utils.dart';
import '../core/utils/responsive.dart';
import '../models/pharmacy.dart';
import '../models/medicine.dart';
import '../models/enums.dart';
import '../services/order_repository.dart';
import '../services/platform_pharmacy_repository.dart';
import '../services/supabase_service.dart';
import '../widgets/pharmacy_action_bar.dart';
import '../widgets/status_badges.dart';
import 'order_checkout_sheet.dart';
import 'order_tracking_screen.dart';

class PharmacyDetailSheet extends StatefulWidget {
  final Pharmacy pharmacy;
  final Medicine? medicine;
  final StockStatus? stockStatus;
  final DateTime? lastStockUpdate;
  final bool initiallyShowRoute;
  /// Page plein écran (pas de modal) — évite l’overlay transparent collé.
  final bool asPage;

  const PharmacyDetailSheet({
    super.key,
    required this.pharmacy,
    this.medicine,
    this.stockStatus,
    this.lastStockUpdate,
    this.initiallyShowRoute = false,
    this.asPage = false,
  });

  @override
  State<PharmacyDetailSheet> createState() => _PharmacyDetailSheetState();
}

class _PharmacyDetailSheetState extends State<PharmacyDetailSheet> {
  bool _isFavorite = false;
  final TravelMode _travelMode = TravelMode.driving;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
    // L’itinéraire s’ouvre désormais hors sheet (évite la barrière collée).
    // initiallyShowRoute n’est plus utilisé pour auto-push.
  }

  Future<void> _loadFavorite() async {
    final fav =
        await OrderRepository.instance.isFavorite(widget.pharmacy.id);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      if (next) {
        await OrderRepository.instance.addFavorite(widget.pharmacy);
      } else {
        await OrderRepository.instance.removeFavorite(widget.pharmacy.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = !next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Favori : $e')),
      );
    }
  }

  Future<void> _openRoutePage() async {
    // Ferme le bottom sheet + sa ModalBarrier, puis ouvre l’itinéraire.
    await openPharmacyRoute(
      context,
      pharmacy: widget.pharmacy,
      mode: _travelMode,
      closeCurrentRoute: true,
    );
  }

  Future<void> _call() async {
    final p = widget.pharmacy.phone;
    if (p != null) await launchUrl(Uri(scheme: 'tel', path: p));
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildBody(context);
    } catch (e, st) {
      debugPrint('PharmacyDetailSheet crash: $e\n$st');
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Pharmacie'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text(
                  widget.pharmacy.name.isEmpty
                      ? 'Impossible d’afficher cette pharmacie'
                      : widget.pharmacy.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Une erreur d’affichage est survenue. Réessayez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final isNarrow = size.width < 380;
    final isPhone = Responsive.isPhone(context);

    final mapMin = isNarrow ? 120.0 : 140.0;
    final mapMax = isPhone ? 220.0 : 260.0;
    var mapHeight = size.height * (widget.asPage ? 0.22 : 0.24);
    if (mapHeight < mapMin) mapHeight = mapMin;
    if (mapHeight > mapMax) mapHeight = mapMax;

    final contentChildren = <Widget>[
      _buildHeader(isNarrow),
      const SizedBox(height: 12),
      _buildRouteSummary(isNarrow),
      const SizedBox(height: 12),
      Align(
        alignment: Responsive.useCompactControls(context)
            ? Alignment.centerLeft
            : Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.useCompactControls(context)
                ? 220
                : double.infinity,
          ),
          child: SizedBox(
            width: Responsive.useCompactControls(context)
                ? null
                : double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openRoutePage,
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Voir l’itinéraire'),
              style: OutlinedButton.styleFrom(
                padding: Responsive.actionButtonPadding(context),
              ),
            ),
          ),
        ),
      ),
      if (widget.medicine != null && widget.stockStatus != null) ...[
        const SizedBox(height: 12),
        _buildStockCard(isNarrow),
      ],
      const SizedBox(height: 12),
      _buildInfoCard(isNarrow),
      const SizedBox(height: 12),
      _buildHoursCard(isNarrow),
      const SizedBox(height: 12),
      _buildServicesCard(isNarrow),
      const SizedBox(height: 8),
      _buildReportLink(isNarrow),
      const SizedBox(height: 8),
    ];

    final scroll = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildMap(mapHeight, isNarrow)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Responsive.padH(context),
            12,
            Responsive.padH(context),
            16,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate(contentChildren),
          ),
        ),
      ],
    );

    if (widget.asPage) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            widget.pharmacy.name.isEmpty
                ? 'Pharmacie'
                : widget.pharmacy.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body: ColoredBox(
          color: AppColors.background,
          child: Column(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  child: scroll,
                ),
              ),
              Material(
                color: AppColors.surface,
                elevation: 8,
                child: _buildBottomActions(isNarrow),
              ),
            ],
          ),
        ),
      );
    }

    final preferred = size.height * (isPhone ? 0.88 : 0.82);
    final sheetHeight = preferred.clamp(280.0, size.height - pad.top - 12);
    return SizedBox(
      height: sheetHeight,
      width: double.infinity,
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHandle(),
            Expanded(child: scroll),
            _buildBottomActions(isNarrow),
          ],
        ),
      ),
    );
  }

  /// Commande possible même si fermée (itinéraire / rappel / livraison différée).
  bool get canOrder => true;

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(double height, bool isNarrow) {
    final open = widget.pharmacy.isOpen == true || widget.pharmacy.isDuty == true;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.18),
                  AppColors.accentGreen.withValues(alpha: 0.12),
                  AppColors.surfaceVariant,
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: isNarrow ? 64 : 72,
                  height: isNarrow ? 64 : 72,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.local_pharmacy_rounded,
                    size: isNarrow ? 32 : 36,
                    color: open ? AppColors.accentGreen : AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.pharmacy.distanceMeters != null
                      ? _formatDistance(widget.pharmacy.distanceMeters!)
                      : (widget.pharmacy.city ?? 'Pharmacie'),
                  style: TextStyle(
                    fontSize: isNarrow ? 13 : 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _mapChip(
              child: Text(
                open ? 'Ouverte' : 'Fiche',
                style: TextStyle(
                  fontSize: isNarrow ? 12 : 13,
                  fontWeight: FontWeight.w800,
                  color: open ? AppColors.accentGreen : AppColors.primaryBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapChip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.10),
            blurRadius: 8,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeader(bool isNarrow) {
    final titleSize = isNarrow ? 18.0 : (Responsive.isPhone(context) ? 20.0 : 22.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.pharmacy.name,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.pharmacy.isVerified == true) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.verified_rounded,
                size: isNarrow ? 18 : 20,
                color: AppColors.primaryBlue,
              ),
            ],
          ],
        ),
        if (widget.pharmacy.rating != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.star_rounded,
                  size: isNarrow ? 14 : 16, color: AppColors.warning),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  '${widget.pharmacy.rating!.toStringAsFixed(1)}'
                  '${widget.pharmacy.reviewCount != null ? ' (${widget.pharmacy.reviewCount} avis)' : ''}',
                  style: TextStyle(
                    fontSize: isNarrow ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusBadge(status: widget.pharmacy.status, small: isNarrow),
            if (widget.pharmacy.isDuty == true)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.duty.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'De garde',
                  style: TextStyle(
                    fontSize: isNarrow ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.duty,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteSummary(bool isNarrow) {
    final distance = widget.pharmacy.distanceMeters != null
        ? _formatDistance(widget.pharmacy.distanceMeters!)
        : '—';
    final duration = widget.pharmacy.travelTimeSeconds != null
        ? _formatDuration(widget.pharmacy.travelTimeSeconds!)
        : '—';

    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.pin_drop_outlined,
            label: 'Distance',
            value: distance,
            isNarrow: isNarrow,
          ),
        ),
        SizedBox(width: isNarrow ? 8 : 10),
        Expanded(
          child: _statCard(
            icon: Icons.schedule_rounded,
            label: 'Durée estimée',
            value: duration,
            isNarrow: isNarrow,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required bool isNarrow,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 10 : 14,
        vertical: isNarrow ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: isNarrow ? 13 : 15, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isNarrow ? 10 : 11,
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
            style: TextStyle(
              fontSize: isNarrow ? 15 : 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(bool isNarrow) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Médicament recherché',
            style: TextStyle(
              fontSize: isNarrow ? 11 : 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.medicine!.fullName,
            style: TextStyle(
              fontSize: isNarrow ? 14 : 16,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StockBadge(status: widget.stockStatus!, small: isNarrow),
              if (widget.lastStockUpdate != null)
                Text(
                  'Màj : ${_formatTimeAgo(widget.lastStockUpdate!)}',
                  style: TextStyle(
                    fontSize: isNarrow ? 10 : 11,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isNarrow) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _infoRow(
            Icons.location_on_outlined,
            'Adresse',
            widget.pharmacy.fullAddress.isEmpty
                ? 'Non renseignée'
                : widget.pharmacy.fullAddress,
            isNarrow: isNarrow,
          ),
          const Divider(height: 22),
          _infoRow(
            Icons.phone_outlined,
            'Téléphone',
            widget.pharmacy.phone ?? 'Non renseigné',
            onTap: widget.pharmacy.phone != null ? _call : null,
            highlight: true,
            isNarrow: isNarrow,
          ),
          if (widget.pharmacy.website != null) ...[
            const Divider(height: 22),
            _infoRow(
              Icons.language_outlined,
              'Site web',
              widget.pharmacy.website!,
              highlight: true,
              isNarrow: isNarrow,
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
    bool highlight = false,
    required bool isNarrow,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isNarrow ? 30 : 34,
            height: isNarrow ? 30 : 34,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: isNarrow ? 16 : 18, color: AppColors.primaryBlue),
          ),
          SizedBox(width: isNarrow ? 10 : 12),
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
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isNarrow ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: highlight
                        ? AppColors.primaryBlue
                        : AppColors.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildHoursCard(bool isNarrow) {
    final hours = widget.pharmacy.openingHours ?? [];
    if (hours.isEmpty) return const SizedBox.shrink();
    final today = (DateTime.now().weekday - 1) % 7;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Horaires',
                  style: TextStyle(
                    fontSize: isNarrow ? 14 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusBadge(status: widget.pharmacy.status, small: true),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(hours.length, (i) {
            final h = hours[i];
            final isToday = i == today;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: isNarrow ? 64 : 78,
                    child: Text(
                      h.dayName,
                      style: TextStyle(
                        fontSize: isNarrow ? 11 : 12,
                        fontWeight:
                            isToday ? FontWeight.w800 : FontWeight.w500,
                        color: isToday
                            ? AppColors.primaryBlue
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      h.display,
                      style: TextStyle(
                        fontSize: isNarrow ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isToday)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Auj.',
                        style: TextStyle(
                          fontSize: isNarrow ? 9 : 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildServicesCard(bool isNarrow) {
    final services = widget.pharmacy.services ?? [];
    if (services.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: TextStyle(
              fontSize: isNarrow ? 14 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: services
                .map(
                  (s) => Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isNarrow ? 8 : 10,
                      vertical: isNarrow ? 5 : 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: isNarrow ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentGreenDark,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportLink(bool isNarrow) {
    return InkWell(
      onTap: _showReportDialog,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.flag_outlined,
                size: isNarrow ? 16 : 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Signaler une information incorrecte',
                style: TextStyle(
                  fontSize: isNarrow ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _orderMedicine() async {
    try {
      var medicine = widget.medicine;
      if (medicine == null) {
        // Médicaments réellement en stock dans cette pharmacie (pas le catalogue seed)
        final lines = await PlatformPharmacyRepository.instance
            .getPharmacyInventory(widget.pharmacy.id);
        if (!mounted) return;
        if (lines.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Aucun médicament en stock pour cette pharmacie. '
                'Recherchez un produit depuis l’onglet Recherche.',
              ),
            ),
          );
          return;
        }
        medicine = lines.first.medicine;
      }
      final order = await OrderCheckoutSheet.show(
        context,
        pharmacy: widget.pharmacy,
        medicine: medicine,
        unitPriceXaf: medicine.priceXaf,
      );
      if (order != null && mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderTrackingScreen(order: order)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande : $e')),
      );
    }
  }

  Widget _buildBottomActions(bool isNarrow) {
    final orderLabel = widget.medicine != null
        ? (isNarrow
            ? 'Commander'
            : 'Commander · ${formatFcfa(widget.medicine!.priceXaf ?? 0)}')
        : (isNarrow ? 'Livrer' : 'Commander / Livrer');

    return PharmacyActionBar(
      canOrder: canOrder,
      orderLabel: orderLabel,
      isFavorite: _isFavorite,
      canCall: widget.pharmacy.phone != null,
      onOrder: _orderMedicine,
      onToggleFavorite: _toggleFavorite,
      onCall: _call,
      onRoute: _openRoutePage,
    );
  }

  void _showReportDialog() {
    final isNarrow = MediaQuery.sizeOf(context).width < 380;
    final descCtrl = TextEditingController();
    var reason = 'Information incorrecte';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: StatefulBuilder(
          builder: (ctx, setLocal) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
              maxWidth: Responsive.isWide(ctx) ? 520 : double.infinity,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      isNarrow ? 14 : 20, 14, isNarrow ? 14 : 20, 8),
                  child: Text(
                    'Signaler une information',
                    style: TextStyle(
                      fontSize: isNarrow ? 16 : 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isNarrow ? 14 : 20),
                  child: DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Motif'),
                    items: const [
                      'Information incorrecte',
                      'Horaires erronés',
                      'Stock incorrect',
                      'Pharmacie fermée',
                      'Autre problème',
                    ]
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => reason = v);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: isNarrow ? 14 : 20),
                  child: TextField(
                    controller: descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'Décrivez le problème (horaires, stock, fermeture…)',
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      isNarrow ? 14 : 16, 12, isNarrow ? 14 : 16, 16),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final uid = SupabaseService.client.auth.currentUser?.id;
                          if (uid == null) {
                            Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Connectez-vous pour envoyer un signalement.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          try {
                            await SupabaseService.client.from('reports').insert({
                              'reporter_id': uid,
                              'target_type': 'pharmacy',
                              'target_id': widget.pharmacy.id,
                              'pharmacy_id': widget.pharmacy.id,
                              'reason': reason,
                              'description': descCtrl.text.trim(),
                              'status': 'OPEN',
                            });
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Signalement envoyé. Merci.'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erreur : $e')),
                              );
                            }
                          }
                        },
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                              vertical: isNarrow ? 12 : 14),
                        ),
                        child: const Text('Envoyer'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _formatDuration(int seconds) {
    final m = (seconds / 60).round();
    return '$m min';
  }

  static String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }
}
