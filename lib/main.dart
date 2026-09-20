import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/app_config_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/courier/courier_shell.dart';
import 'screens/main_shell.dart';
import 'screens/pharmacy/pharmacy_shell.dart';
import 'services/admin_repository.dart';
import 'services/location_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? bootError;
  try {
    await SupabaseConfig.loadEnv();
    if (!SupabaseConfig.isConfigured) {
      bootError =
          'Configuration requise. Contactez le support si le problème persiste.';
    } else {
      await SupabaseService.initialize();
    }
  } catch (e) {
    bootError = e.toString();
  }

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    final mobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (mobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  if (bootError == null) {
    // Différer le GPS : laisse l’UI démarrer avant le stream de position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        unawaited(LocationService.instance.startLiveTracking(
          distanceFilterMeters: 35,
        ));
      });
    });
  }

  runApp(ProviderScope(
    child: InstaPharmApp(bootError: bootError),
  ));
}

class InstaPharmApp extends StatelessWidget {
  final String? bootError;

  const InstaPharmApp({super.key, this.bootError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstaPharm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = mq.size.width >= 1024 ? 1.05 : 1.0;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: bootError != null
          ? _ConfigErrorScreen(message: bootError!)
          : const AuthGate(),
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  final String message;
  const _ConfigErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_outlined,
                  size: 48, color: AppColors.primaryBlue),
              const SizedBox(height: 16),
              const Text(
                'Configuration',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  var _bootstrapTried = false;

  Future<void> _tryBootstrapAdmin() async {
    if (_bootstrapTried) return;
    _bootstrapTried = true;
    try {
      final result = await AdminRepository.instance.claimBootstrap();
      if (result['ok'] == true && result['promoted'] == true) {
        ref.invalidate(profileProvider);
      }
    } catch (_) {
      // Aucun admin à créer, ou script SQL non appliqué
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur auth : $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ),
      ),
      data: (state) {
        if (state.session != null || ref.watch(currentUserProvider) != null) {
          final profile = ref.watch(profileProvider);
          return profile.when(
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const MainShell(),
            data: (user) {
              // Charger les paramètres globaux (frais, rayon, etc.)
              ref.watch(appConfigProvider);
              // Promouvoir automatiquement le premier compte connecté
              if (user != null && user.isAdmin != true && !_bootstrapTried) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _tryBootstrapAdmin();
                });
              }
              if (user?.isAdmin == true) {
                return const AdminShell();
              }
              if (user?.isPharmacist == true) {
                return const PharmacyShell();
              }
              if (user?.isCourier == true) {
                return const CourierShell();
              }
              return const MainShell();
            },
          );
        }
        return const AuthScreen();
      },
    );
  }
}
