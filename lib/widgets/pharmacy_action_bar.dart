import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';

/// Barre d’actions moderne pour la fiche pharmacie.
class PharmacyActionBar extends StatelessWidget {
  final bool canOrder;
  final String orderLabel;
  final bool isFavorite;
  final bool canCall;
  final VoidCallback onOrder;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onCall;
  final VoidCallback onRoute;

  const PharmacyActionBar({
    super.key,
    required this.canOrder,
    required this.orderLabel,
    required this.isFavorite,
    required this.canCall,
    required this.onOrder,
    required this.onToggleFavorite,
    required this.onCall,
    required this.onRoute,
  });

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.useCompactControls(context);
    final narrow = MediaQuery.sizeOf(context).width < 380;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 14 : 18, 14, narrow ? 14 : 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canOrder) ...[
                Align(
                  alignment: compact ? Alignment.centerRight : Alignment.center,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 280 : double.infinity,
                    ),
                    child: SizedBox(
                      width: compact ? null : double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: onOrder,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize:
                              compact ? MainAxisSize.min : MainAxisSize.max,
                          children: [
                            const Icon(Icons.local_shipping_rounded, size: 20),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                orderLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  _Chip(
                    icon: isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: 'Favori',
                    onTap: onToggleFavorite,
                    active: isFavorite,
                    activeColor: AppColors.error,
                    showLabel: !narrow,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Chip(
                      icon: Icons.phone_rounded,
                      label: 'Appeler',
                      onTap: canCall ? onCall : null,
                      showLabel: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Chip(
                      icon: Icons.near_me_rounded,
                      label: 'Itinéraire',
                      onTap: onRoute,
                      primary: true,
                      showLabel: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool active;
  final bool showLabel;
  final Color? activeColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.active = false,
    this.showLabel = true,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = activeColor ?? AppColors.primaryBlue;
    final fg = !enabled
        ? AppColors.textTertiary
        : primary
            ? Colors.white
            : active
                ? accent
                : AppColors.textPrimary;
    final bg = !enabled
        ? AppColors.surfaceVariant.withValues(alpha: 0.45)
        : primary
            ? AppColors.primaryBlue
            : active
                ? accent.withValues(alpha: 0.12)
                : AppColors.surfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: fg),
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
