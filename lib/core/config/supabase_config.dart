import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static String get url =>
      dotenv.env['SUPABASE_URL']?.trim() ?? '';

  static String get anonKey =>
      dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      !url.contains('YOUR_PROJECT') &&
      !anonKey.contains('YOUR_SUPABASE') &&
      url.startsWith('https://') &&
      anonKey.length > 20;

  /// Charge `.env` depuis les assets Flutter (recharge forcée).
  static Future<void> loadEnv() async {
    try {
      final raw = await rootBundle.loadString('.env');
      dotenv.loadFromString(envString: raw);
    } catch (_) {
      await dotenv.load(fileName: '.env', isOptional: true);
    }
  }
}
