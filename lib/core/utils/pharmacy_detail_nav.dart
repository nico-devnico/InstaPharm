import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../models/medicine.dart';
import '../../models/pharmacy.dart';
import '../../screens/pharmacy_detail_sheet.dart';
import '../theme/app_colors.dart';
import 'responsive.dart';

/// Ouvre le détail pharmacie sans laisser une barrière transparente collée.
Future<void> showPharmacyDetailOverlay(
  BuildContext context, {
  required Pharmacy pharmacy,
  Medicine? medicine,
  StockStatus? stockStatus,
  DateTime? lastStockUpdate,
}) async {
  final child = PharmacyDetailSheet(
    pharmacy: pharmacy,
    medicine: medicine,
    stockStatus: stockStatus,
    lastStockUpdate: lastStockUpdate,
  );

  if (Responsive.isWide(context)) {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: h * 0.92,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                color: AppColors.surface,
                child: child,
              ),
            ),
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SafeArea(
      child: Material(
        color: AppColors.surface,
        child: child,
      ),
    ),
  );
}
