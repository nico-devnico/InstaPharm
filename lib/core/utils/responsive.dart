import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Breakpoints adaptatifs : smartphone / tablette / ordinateur / web.
class Responsive {
  Responsive._();

  static const double phone = 600;
  static const double tablet = 1024;
  static const double desktop = 1440;

  static bool get isWeb => kIsWeb;

  static double width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isPhone(BuildContext context) => width(context) < phone;

  static bool isTablet(BuildContext context) {
    final w = width(context);
    return w >= phone && w < tablet;
  }

  static bool isDesktop(BuildContext context) => width(context) >= tablet;

  static bool isWide(BuildContext context) => width(context) >= phone;

  /// Web ou grand écran : éviter les boutons pleine largeur.
  static bool useCompactControls(BuildContext context) =>
      isWeb || isWide(context);

  static bool isSmall(BuildContext context) => width(context) < 360;

  static bool isMedium(BuildContext context) {
    final w = width(context);
    return w >= 360 && w < 390;
  }

  static double screenWidth(BuildContext context) => width(context);

  static double screenHeight(BuildContext context) => height(context);

  static double padH(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < phone) return 16;
    if (w < tablet) return 24;
    return 32;
  }

  static double contentMaxWidth(BuildContext context) {
    if (isDesktop(context)) return 1200;
    if (isTablet(context)) return 900;
    return width(context);
  }

  static double sidePanelWidth(BuildContext context) {
    final w = width(context);
    if (w >= desktop) return 420;
    if (w >= tablet) return 380;
    if (w >= phone) return 340;
    return w;
  }

  /// Largeur max d’un bouton d’action (web / tablette).
  static double actionButtonMaxWidth(BuildContext context) {
    if (isDesktop(context) || isWeb) return 200;
    if (isTablet(context)) return 240;
    return double.infinity;
  }

  static EdgeInsets actionButtonPadding(BuildContext context) {
    if (useCompactControls(context)) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    }
    return const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  }

  static double sp(BuildContext context, double size) {
    if (isSmall(context)) return size * 0.9;
    if (isDesktop(context)) return size * 1.05;
    return size;
  }

  static double icon(BuildContext context, double size) {
    if (isSmall(context)) return size * 0.88;
    return size;
  }

  static double w(BuildContext context, double fraction) =>
      width(context) * fraction;

  static double h(BuildContext context, double fraction) =>
      height(context) * fraction;

  static EdgeInsets pageInsets(BuildContext context) {
    final pad = padH(context);
    if (!isDesktop(context)) {
      return EdgeInsets.symmetric(horizontal: pad);
    }
    final max = contentMaxWidth(context);
    final side = ((width(context) - max) / 2).clamp(pad, 120.0);
    return EdgeInsets.symmetric(horizontal: side);
  }

  /// Rangée de boutons : taille normale sur web, flexibles sur mobile.
  static Widget actionRow(
    BuildContext context, {
    required List<Widget> children,
  }) {
    if (useCompactControls(context)) {
      return Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: children
              .map(
                (c) => ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 120,
                    maxWidth: actionButtonMaxWidth(context),
                  ),
                  child: c,
                ),
              )
              .toList(),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
