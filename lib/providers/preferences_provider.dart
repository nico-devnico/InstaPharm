import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/user_activity_repository.dart';
import 'auth_provider.dart';

final notificationsEnabledProvider =
    StateNotifierProvider<NotificationsNotifier, bool>((ref) {
  return NotificationsNotifier();
});

class NotificationsNotifier extends StateNotifier<bool> {
  NotificationsNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    state = await UserActivityRepository.instance.getNotificationsEnabled();
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    await UserActivityRepository.instance.setNotificationsEnabled(value);
  }
}

final searchHistoryProvider =
    FutureProvider.autoDispose<List<SearchHistoryItem>>((ref) async {
  ref.watch(authStateProvider);
  return UserActivityRepository.instance.getSearches();
});

final pharmacyViewsProvider =
    FutureProvider.autoDispose<List<PharmacyViewItem>>((ref) async {
  ref.watch(authStateProvider);
  return UserActivityRepository.instance.getViews();
});

/// Rayon affiché sur le slider (brouillon).
final searchRadiusKmProvider = StateProvider<double>((ref) => 3.0);

/// Rayon réellement utilisé pour Overpass / cache (validé au relâchement).
final committedSearchRadiusKmProvider = StateProvider<double>((ref) => 3.0);

/// Incrémenter pour forcer une nouvelle recherche (bouton refresh).
final pharmacySearchForceTokenProvider = StateProvider<int>((ref) => 0);

/// Rayon effectivement utilisé après auto-élargissement.
final effectiveRadiusKmProvider = StateProvider<double>((ref) => 3.0);
