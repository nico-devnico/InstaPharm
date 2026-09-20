import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

final adminDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return AdminRepository.instance.dashboard();
});

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminDashboardProvider);
    final pad = Responsive.padH(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: Responsive.isDesktop(context)
          ? AppBar(
              backgroundColor: AppColors.background,
              title: Text(
                'Tableau de bord',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: () => ref.invalidate(adminDashboardProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmptyState(
          message: 'Erreur de chargement\n$e',
          icon: Icons.error_outline,
          action: FilledButton(
            onPressed: () => ref.invalidate(adminDashboardProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminDashboardProvider),
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 900
                      ? 4
                      : c.maxWidth > 560
                          ? 2
                          : 1;
                  final cards = <Widget>[
                    AdminStatCard(
                      label: 'Utilisateurs',
                      value: '${data['users_total'] ?? 0}',
                      icon: Icons.people_rounded,
                      color: AppColors.primaryBlue,
                    ),
                    AdminStatCard(
                      label: 'Pharmacies vérifiées',
                      value: '${data['pharmacies_verified'] ?? 0}',
                      icon: Icons.verified_rounded,
                      color: AppColors.accentGreen,
                    ),
                    AdminStatCard(
                      label: 'Pharmacies en attente',
                      value: '${data['pharmacies_pending'] ?? 0}',
                      icon: Icons.hourglass_top_rounded,
                      color: AppColors.accentOrange,
                    ),
                    AdminStatCard(
                      label: 'Médicaments',
                      value: '${data['medicines_total'] ?? 0}',
                      icon: Icons.medication_rounded,
                      color: AppColors.accentPurple,
                    ),
                    AdminStatCard(
                      label: 'Commandes actives',
                      value: '${data['orders_active'] ?? 0}',
                      icon: Icons.receipt_long_rounded,
                      color: AppColors.info,
                    ),
                    AdminStatCard(
                      label: 'Commandes livrées',
                      value: '${data['orders_delivered'] ?? 0}',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                    AdminStatCard(
                      label: 'Livraisons en cours',
                      value: '${data['deliveries_in_progress'] ?? 0}',
                      icon: Icons.local_shipping_rounded,
                      color: AppColors.accentOrange,
                    ),
                    AdminStatCard(
                      label: 'Signalements ouverts',
                      value: '${data['reports_open'] ?? 0}',
                      icon: Icons.flag_rounded,
                      color: AppColors.error,
                    ),
                  ];
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: cols == 1 ? 3.2 : 2.4,
                    children: cards,
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Commandes par statut',
                style: AppTypography.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _OrdersByStatus(data['orders_by_status']),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersByStatus extends StatelessWidget {
  final dynamic raw;
  const _OrdersByStatus(this.raw);

  @override
  Widget build(BuildContext context) {
    final map = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        map[k.toString()] = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      });
    }
    if (map.isEmpty) {
      return const AdminEmptyState(message: 'Aucune commande pour l’instant');
    }
    final max = map.values.fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 999999);
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final e in entries) ...[
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 10,
                        backgroundColor: AppColors.surfaceVariant,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${e.value}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
