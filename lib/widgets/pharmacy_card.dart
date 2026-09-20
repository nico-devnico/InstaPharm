import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/currency.dart';
import '../core/utils/responsive.dart';
import '../models/pharmacy.dart';
import '../models/search_result.dart';
import '../models/enums.dart';
import 'status_badges.dart';

class PharmacyCard extends StatelessWidget {
  final Pharmacy pharmacy;
  final StockStatus? stockStatus;
  final bool isBestMatch;
  final DateTime? lastStockUpdate;
  final int? priceXaf;
  final VoidCallback? onTap;
  final VoidCallback? onRouteTap;
  final VoidCallback? onFavoriteToggle;
  final bool isFavorite;

  const PharmacyCard({
    super.key,
    required this.pharmacy,
    this.stockStatus,
    this.isBestMatch = false,
    this.lastStockUpdate,
    this.priceXaf,
    this.onTap,
    this.onRouteTap,
    this.onFavoriteToggle,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final wide = Responsive.isWide(context);
    final hPad = wide ? 0.0 : 14.0;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: hPad, vertical: 5),
      constraints: BoxConstraints(maxWidth: wide ? 520 : double.infinity),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(wide ? 16 : 18),
        border: isBestMatch
            ? Border.all(color: AppColors.accentGreen, width: 1.5)
            : Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(wide ? 16 : 18),
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBestMatch) _buildBestMatchBadge(),
                _buildMainRow(context),
                const SizedBox(height: 12),
                _buildBadgesRow(),
                if (lastStockUpdate != null) _buildUpdateText(),
                if (onRouteTap != null) _buildActionButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBestMatchBadge() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentGreen.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: AppColors.accentGreen),
            const SizedBox(width: 4),
            Text(
              'Meilleure correspondance',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accentGreen,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhoto(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pharmacy.name,
                      style: AppTypography.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pharmacy.isVerified == true) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.verified_rounded,
                        size: 15, color: AppColors.primaryBlue),
                  ],
                  if (onFavoriteToggle != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onFavoriteToggle,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 17,
                          color: isFavorite
                              ? AppColors.error
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (pharmacy.rating != null) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text(
                      pharmacy.rating!.toStringAsFixed(1),
                      style: AppTypography.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    if (pharmacy.reviewCount != null)
                      Text(
                        ' (${pharmacy.reviewCount})',
                        style: AppTypography.textTheme.labelMedium
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      pharmacy.fullAddress,
                      style: AppTypography.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadgesRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        StatusBadge(status: pharmacy.status, small: true),
        if (stockStatus != null)
          StockBadge(status: stockStatus!, small: true),
        if (priceXaf != null && priceXaf! > 0)
          InfoChipStatic(
            icon: Icons.payments_outlined,
            label: formatFcfa(priceXaf!),
          ),
        if ((pharmacy.services ?? [])
            .any((s) => s.toLowerCase().contains('livraison')))
          const InfoChipStatic(
            icon: Icons.delivery_dining_rounded,
            label: 'Livraison',
          ),
        if (pharmacy.distanceMeters != null)
          InfoChipStatic(
            icon: Icons.pin_drop_outlined,
            label: _formatDistance(pharmacy.distanceMeters!),
          ),
        if (pharmacy.travelTimeSeconds != null)
          InfoChipStatic(
            icon: Icons.directions_car_outlined,
            label: _formatDuration(pharmacy.travelTimeSeconds!),
          ),
      ],
    );
  }

  Widget _buildUpdateText() {
    final statusLabel = stockStatus?.displayName;
    final ago = _formatTimeAgo(lastStockUpdate!);
    final text = statusLabel != null
        ? '$statusLabel · Stock mis à jour $ago'
        : 'Stock mis à jour $ago';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: AppTypography.textTheme.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sur très petits écrans (<300px disponibles), on empile verticalement
          if (constraints.maxWidth < 280) {
            return Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.store_outlined, size: 16),
                    label: const Text('Voir la pharmacie'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRouteTap,
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: const Text('Itinéraire'),
                  ),
                ),
              ],
            );
          }
          // Sinon côte-à-côte
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.store_outlined, size: 16),
                  label: const Text('Voir', overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRouteTap,
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label:
                      const Text('Itinéraire', overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPhoto() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.12),
            AppColors.primaryBlue.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.local_pharmacy_rounded,
        size: 28,
        color: AppColors.primaryBlue,
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

// ─────────────────────────────────────────────────────────────────────────────

class InfoChipStatic extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const InfoChipStatic({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class PharmacyResultCard extends StatelessWidget {
  final PharmacySearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onRouteTap;
  final VoidCallback? onFavoriteToggle;
  final bool isFavorite;

  const PharmacyResultCard({
    super.key,
    required this.result,
    this.onTap,
    this.onRouteTap,
    this.onFavoriteToggle,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    return PharmacyCard(
      pharmacy: result.pharmacy,
      stockStatus: result.stockStatus,
      isBestMatch: result.isBestMatch,
      lastStockUpdate: result.inventory?.lastUpdated,
      priceXaf: result.inventory?.unitPriceXaf ?? result.medicine?.priceXaf,
      onTap: onTap,
      onRouteTap: onRouteTap,
      onFavoriteToggle: onFavoriteToggle,
      isFavorite: isFavorite,
    );
  }
}
