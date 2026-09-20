import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/nav_utils.dart';
import '../core/utils/pharmacy_detail_nav.dart';
import '../models/pharmacy.dart';
import '../providers/auth_provider.dart';
import '../services/order_repository.dart';
import '../widgets/pharmacy_card.dart';
import '../widgets/skeleton_widgets.dart';
import '../widgets/state_widgets.dart';
import 'main_shell.dart';

final favoritesProvider = FutureProvider.autoDispose<List<Pharmacy>>((ref) async {
  ref.watch(authStateProvider);
  return OrderRepository.instance.getFavorites();
});

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPharmacies = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(
          'Favoris',
          style: AppTypography.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: asyncPharmacies.when(
        loading: () => ListView(
          children: List.generate(4, (_) => const PharmacyCardSkeleton()),
        ),
        error: (e, _) => ErrorState(
          message: 'Impossible de charger vos favoris.',
          onAction: () => ref.invalidate(favoritesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Aucune pharmacie favorite',
              subtitle:
                  'Ajoutez les pharmacies que vous aimez en cliquant sur le cœur.',
              actionLabel: 'Rechercher des pharmacies',
              onAction: () {
                ref.read(shellIndexProvider.notifier).state = 0;
              },
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 2),
            itemBuilder: (_, i) {
              final p = list[i];
              return PharmacyCard(
                pharmacy: p,
                isFavorite: true,
                onTap: () => _showDetail(context, p),
                onRouteTap: () => _showDetail(context, p, showRoute: true),
                onFavoriteToggle: () async {
                  await OrderRepository.instance.removeFavorite(p.id);
                  ref.invalidate(favoritesProvider);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, Pharmacy p, {bool showRoute = false}) {
    if (showRoute) {
      openPharmacyRoute(context, pharmacy: p);
      return;
    }
    showPharmacyDetailOverlay(context, pharmacy: p);
  }
}
