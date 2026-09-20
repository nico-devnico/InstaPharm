import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../models/pharmacy.dart';
import '../../screens/route_map_screen.dart';

/// Ouvre l’itinéraire sans laisser la barrière du bottom sheet collée à l’accueil.
Future<void> openPharmacyRoute(
  BuildContext context, {
  required Pharmacy pharmacy,
  TravelMode mode = TravelMode.driving,
  bool closeCurrentRoute = false,
}) async {
  final rootNav = Navigator.of(context, rootNavigator: true);

  if (closeCurrentRoute && rootNav.canPop()) {
    // Retire le modal + ModalBarrier avant le push plein écran.
    rootNav.pop();
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  if (!rootNav.mounted) return;

  await rootNav.push(
    MaterialPageRoute<void>(
      builder: (_) => RouteMapScreen(
        pharmacy: pharmacy,
        initialMode: mode,
      ),
    ),
  );
}
