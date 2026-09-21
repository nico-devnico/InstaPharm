import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../models/medicine.dart';
import '../../models/pharmacy.dart';
import '../../screens/pharmacy_detail_sheet.dart';

/// Ouvre le détail pharmacie en **page plein écran** (pas de modal / bottom sheet).
/// Corrige définitivement l’overlay transparent vide qui bloquait l’accueil.
Future<void> showPharmacyDetailOverlay(
  BuildContext context, {
  required Pharmacy pharmacy,
  Medicine? medicine,
  StockStatus? stockStatus,
  DateTime? lastStockUpdate,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  await nav.push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PharmacyDetailSheet(
        pharmacy: pharmacy,
        medicine: medicine,
        stockStatus: stockStatus,
        lastStockUpdate: lastStockUpdate,
        asPage: true,
      ),
    ),
  );
}
