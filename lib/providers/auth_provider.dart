import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// Émet d’abord la session courante, puis les changements Auth.
final authStateProvider = StreamProvider<AuthState>((ref) async* {
  final session = SupabaseService.client.auth.currentSession;
  yield AuthState(
    session != null
        ? AuthChangeEvent.initialSession
        : AuthChangeEvent.signedOut,
    session,
  );
  yield* AuthService.instance.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return AuthService.instance.currentUser;
});

final profileProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateProvider);
  if (AuthService.instance.currentUser == null) return null;
  return AuthService.instance.fetchProfile();
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});
