import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/enums.dart';

class StockBadge extends StatelessWidget {
  final StockStatus status;
  final bool small;

  const StockBadge({super.key, required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor, icon) = _getStyle();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(small ? 8 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: TextStyle(fontSize: small ? 11 : 13),
          ),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: small ? 11 : 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, String) _getStyle() {
    switch (status) {
      case StockStatus.available:
        return (
          AppColors.available,
          AppColors.available.withValues(alpha: 0.10),
          '✓'
        );
      case StockStatus.lowStock:
        return (
          AppColors.lowStock,
          AppColors.lowStock.withValues(alpha: 0.12),
          '⚠'
        );
      case StockStatus.outOfStock:
        return (
          AppColors.outOfStock,
          AppColors.outOfStock.withValues(alpha: 0.10),
          '✕'
        );
      case StockStatus.unknown:
        return (
          AppColors.unknown,
          AppColors.unknown.withValues(alpha: 0.12),
          '?'
        );
    }
  }
}

class StatusBadge extends StatelessWidget {
  final PharmacyStatus status;
  final bool small;

  const StatusBadge({super.key, required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (color, bgColor) = _getStyle();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(small ? 8 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: small ? 6 : 8,
            height: small ? 6 : 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.displayName,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: small ? 11 : 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _getStyle() {
    switch (status) {
      case PharmacyStatus.open:
        return (AppColors.open, AppColors.open.withValues(alpha: 0.10));
      case PharmacyStatus.closed:
        return (AppColors.closed, AppColors.closed.withValues(alpha: 0.10));
      case PharmacyStatus.onDuty:
        return (AppColors.duty, AppColors.duty.withValues(alpha: 0.12));
      case PharmacyStatus.unknown:
        return (
          AppColors.primaryBlue,
          AppColors.primaryBlue.withValues(alpha: 0.10),
        );
    }
  }
}

class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color ?? AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
