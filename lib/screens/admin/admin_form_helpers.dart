import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Dialogue admin scrollable anti-overflow (petits écrans).
Future<T?> showAdminFormDialog<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext ctx) builder,
  List<Widget>? actions,
  double maxWidth = 520,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      return AlertDialog(
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: maxWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h * 0.72),
            child: SingleChildScrollView(
              child: builder(ctx),
            ),
          ),
        ),
        actions: actions,
      );
    },
  );
}

InputDecoration adminFieldDecoration(String label, {String? hint, String? helper}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    filled: true,
    fillColor: AppColors.surfaceVariant.withValues(alpha: 0.45),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
