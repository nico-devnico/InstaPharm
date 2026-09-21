import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../models/medicine.dart';
import '../../models/pharmacy.dart';
import '../../screens/pharmacy_detail_sheet.dart';

/// Ouvre le détail pharmacie en page plein écran **opaque** (jamais un sheet
/// transparent qui laisse un écran blanc).
Future<void> showPharmacyDetailOverlay(
  BuildContext context, {
  required Pharmacy pharmacy,
  Medicine? medicine,
  StockStatus? stockStatus,
  DateTime? lastStockUpdate,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  await nav.push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      barrierColor: const Color(0xFFF8FAFC),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return PharmacyDetailSheet(
          pharmacy: pharmacy,
          medicine: medicine,
          stockStatus: stockStatus,
          lastStockUpdate: lastStockUpdate,
          asPage: true,
        );
      },
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}
