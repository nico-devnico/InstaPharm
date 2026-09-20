import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/currency.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../widgets/state_widgets.dart';
import 'order_tracking_screen.dart';
import 'rating_screen.dart';

/// Alias pour compatibilité avec les écrans qui invalident `ordersProvider`.
final ordersProvider = myOrdersProvider;

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  int _tab = 0; // 0 = actives, 1 = terminées

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(
          'Commandes',
          style: AppTypography.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(myOrdersProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                _tabChip('En cours', 0),
                const SizedBox(width: 8),
                _tabChip('Terminées', 1),
              ],
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Erreur',
                subtitle: e.toString(),
              ),
              data: (orders) {
                final filtered = orders.where((o) {
                  final active = o.status.isActive;
                  return _tab == 0 ? active : !active;
                }).toList();

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: _tab == 0
                        ? 'Aucune commande en cours'
                        : 'Aucun historique',
                    subtitle: _tab == 0
                        ? 'Commandez un médicament depuis une pharmacie pour suivre la livraison ici.'
                        : 'Vos commandes livrées apparaîtront ici.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myOrdersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _OrderCard(
                      order: filtered[i],
                      onOpen: () => _openDetail(filtered[i]),
                      onRate: filtered[i].status == OrderStatus.delivered
                          ? () => _openRating(filtered[i])
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.primaryBlue
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRating(MedicineOrder order) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RatingScreen(order: order)),
    );
    if (ok == true) ref.invalidate(myOrdersProvider);
  }

  void _openDetail(MedicineOrder order) {
    if (order.fulfillment == FulfillmentType.delivery) {
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(order: order),
            ),
          )
          .then((_) => ref.invalidate(myOrdersProvider));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(
        order: order,
        onRate: order.status == OrderStatus.delivered
            ? () {
                Navigator.pop(context);
                _openRating(order);
              }
            : null,
      ),
    ).then((_) => ref.invalidate(myOrdersProvider));
  }
}

class _OrderCard extends StatelessWidget {
  final MedicineOrder order;
  final VoidCallback onOpen;
  final VoidCallback? onRate;

  const _OrderCard({
    required this.order,
    required this.onOpen,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final item = order.items.isNotEmpty ? order.items.first : null;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.id,
                    style: AppTypography.textTheme.labelLarge?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item == null
                  ? 'Commande'
                  : '${item.medicineName}${item.dosage != null ? ' · ${item.dosage}' : ''}',
              style: AppTypography.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              order.pharmacyName,
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  order.fulfillment == FulfillmentType.delivery
                      ? Icons.delivery_dining_rounded
                      : Icons.storefront_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.fulfillment.displayName,
                    style: AppTypography.textTheme.bodySmall,
                  ),
                ),
                Text(
                  formatFcfa(order.totalXaf),
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
            if (order.status.isActive) ...[
              const SizedBox(height: 12),
              _ProgressBar(
                  status: order.status, fulfillment: order.fulfillment),
              if (order.fulfillment == FulfillmentType.delivery) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: const Text('Suivre le transport'),
                  ),
                ),
              ],
            ],
            if (order.status == OrderStatus.delivered && onRate != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onRate,
                  icon: const Icon(Icons.star_rounded, size: 18),
                  label: const Text('Noter'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.cancelled:
        return AppColors.error;
      case OrderStatus.outForDelivery:
        return AppColors.accentOrange;
      case OrderStatus.readyForPickup:
        return AppColors.accentPurple;
      default:
        return AppColors.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final OrderStatus status;
  final FulfillmentType fulfillment;

  const _ProgressBar({required this.status, required this.fulfillment});

  int get _step {
    switch (status) {
      case OrderStatus.pending:
        return 0;
      case OrderStatus.confirmed:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.outForDelivery:
      case OrderStatus.readyForPickup:
        return 3;
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.cancelled:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = fulfillment == FulfillmentType.delivery
        ? const ['Confirmée', 'Préparation', 'Livraison', 'Livrée']
        : const ['Confirmée', 'Préparation', 'Retrait', 'Terminée'];
    return Column(
      children: [
        Row(
          children: List.generate(4, (i) {
            final done = _step > i;
            final current = _step == i + 1 || (_step == 0 && i == 0);
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                decoration: BoxDecoration(
                  color: done || current
                      ? AppColors.primaryBlue
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map((l) => Text(
                    l,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _OrderDetailSheet extends StatelessWidget {
  final MedicineOrder order;
  final VoidCallback? onRate;

  const _OrderDetailSheet({required this.order, this.onRate});

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Détail ${order.id}',
                  style: AppTypography.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 16),
          _ProgressBar(
            status: order.status,
            fulfillment: order.fulfillment,
          ),
          const SizedBox(height: 20),
          _section('Pharmacie', order.pharmacyName),
          _section(
            'Médicament',
            order.items
                .map((i) =>
                    '${i.medicineName} ×${i.quantity} — ${formatFcfa(i.lineTotalXaf)}')
                .join('\n'),
          ),
          _section('Réception', order.fulfillment.displayName),
          _section('Paiement', order.paymentMethod.displayName),
          if (d != null) ...[
            _section('Livraison', d.fullAddress),
            if (d.courierName != null)
              _section(
                'Livreur',
                '${d.courierName}\n${d.courierPhone ?? ''}',
              ),
          ],
          _section('Total', formatFcfa(order.totalXaf)),
          if (onRate != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRate,
              icon: const Icon(Icons.star_rounded),
              label: const Text('Noter la commande'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.textTheme.labelLarge?.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: AppTypography.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
