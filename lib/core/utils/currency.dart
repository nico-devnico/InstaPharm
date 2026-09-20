import '../constants/cameroon.dart';

/// Formatage monétaire FCFA (XAF) — sans décimales.
String formatFcfa(num amount) {
  final n = amount.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u202f');
    buf.write(s[i]);
  }
  return '${buf.toString()} ${CameroonDefaults.currencyLabel}';
}
