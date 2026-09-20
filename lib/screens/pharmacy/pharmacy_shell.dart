import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/responsive.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/platform_pharmacy_repository.dart';
import '../../services/staff_repository.dart';
import '../profile_screen.dart';

final pharmacyOrdersProvider =
    FutureProvider.autoDispose<List<MedicineOrder>>((ref) async {
  ref.watch(authStateProvider);
  return StaffRepository.instance.getPharmacyOrders();
});

final myPharmacyInventoryProvider =
    FutureProvider.autoDispose<List<InventoryLine>>((ref) async {
  ref.watch(authStateProvider);
  final repo = PlatformPharmacyRepository.instance;
  var pharmacy = await repo.getMyPharmacy();
  // Fallback : première pharmacie plateforme si pas encore liée
  pharmacy ??= (await repo.listPlatformPharmacies()).firstOrNull;
  if (pharmacy == null) return [];
  return repo.getPharmacyInventory(pharmacy.id);
});

final myPharmacyProvider =
    FutureProvider.autoDispose((ref) async {
  ref.watch(authStateProvider);
  final repo = PlatformPharmacyRepository.instance;
  var pharmacy = await repo.getMyPharmacy();
  pharmacy ??= (await repo.listPlatformPharmacies()).firstOrNull;
  return pharmacy;
});

class PharmacyShell extends ConsumerStatefulWidget {
  const PharmacyShell({super.key});

  @override
  ConsumerState<PharmacyShell> createState() => _PharmacyShellState();
}

class _PharmacyShellState extends ConsumerState<PharmacyShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _PharmacyHomeTab(),
      const _PharmacyStockTab(),
      const _PharmacyOrdersTab(),
      const ProfileScreen(),
    ];
    final wide = Responsive.isDesktop(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.surface,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard_rounded),
                  label: Text('Tableau'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2_rounded),
                  label: Text('Stock'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: Text('Commandes'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: Text('Profil'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: IndexedStack(index: _index, children: pages),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Tableau',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Commandes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _PharmacyHomeTab extends ConsumerWidget {
  const _PharmacyHomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pharmacyOrdersProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Espace pharmacie',
          style: AppTypography.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.background,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur de chargement')),
        data: (orders) {
          final pending = orders
              .where((o) =>
                  o.status == OrderStatus.pending ||
                  o.status == OrderStatus.confirmed)
              .length;
          final preparing =
              orders.where((o) => o.status == OrderStatus.preparing).length;
          final out = orders
              .where((o) => o.status == OrderStatus.outForDelivery)
              .length;
          final done =
              orders.where((o) => o.status == OrderStatus.delivered).length;

          final pad = Responsive.padH(context);
          final wide = Responsive.isWide(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
            children: [
              Text(
                'Bonjour${profile?.fullName != null ? ', ${profile!.fullName}' : ''}',
                style: AppTypography.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gérez le stock et les commandes patients',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (wide)
                Row(
                  children: [
                    _statCard('À traiter', pending, AppColors.primaryBlue),
                    const SizedBox(width: 10),
                    _statCard('Préparation', preparing, AppColors.accentOrange),
                    const SizedBox(width: 10),
                    _statCard('En livraison', out, AppColors.accentPurple),
                    const SizedBox(width: 10),
                    _statCard('Livrées', done, AppColors.accentGreen),
                  ],
                )
              else ...[
                Row(
                  children: [
                    _statCard('À traiter', pending, AppColors.primaryBlue),
                    const SizedBox(width: 10),
                    _statCard('Préparation', preparing, AppColors.accentOrange),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statCard('En livraison', out, AppColors.accentPurple),
                    const SizedBox(width: 10),
                    _statCard('Livrées', done, AppColors.accentGreen),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Consumer(
                builder: (context, ref, _) {
                  final stock = ref.watch(myPharmacyInventoryProvider);
                  return stock.maybeWhen(
                    data: (lines) {
                      final low = lines
                          .where((l) =>
                              l.inventory.status == StockStatus.lowStock)
                          .length;
                      final out = lines
                          .where((l) =>
                              l.inventory.status == StockStatus.outOfStock)
                          .length;
                      if (low == 0 && out == 0) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          [
                            if (out > 0) '$out produit(s) en rupture',
                            if (low > 0) '$low en stock faible',
                          ].join(' · '),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentOrange,
                          ),
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                },
              ),
              Text(
                'Actions rapides',
                style: AppTypography.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...orders
                  .where((o) => o.status.isActive)
                  .take(5)
                  .map((o) => _QuickOrderTile(order: o)),
              if (orders.where((o) => o.status.isActive).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Aucune commande en cours pour le moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PharmacyStockTab extends ConsumerStatefulWidget {
  const _PharmacyStockTab();

  @override
  ConsumerState<_PharmacyStockTab> createState() => _PharmacyStockTabState();
}

class _PharmacyStockTabState extends ConsumerState<_PharmacyStockTab> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // all | low | out | unknown

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<InventoryLine> _filtered(List<InventoryLine> lines) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return lines.where((line) {
      final inv = line.inventory;
      if (_filter == 'low' && inv.status != StockStatus.lowStock) return false;
      if (_filter == 'out' && inv.status != StockStatus.outOfStock) return false;
      if (_filter == 'unknown' && inv.status != StockStatus.unknown) {
        return false;
      }
      if (q.isEmpty) return true;
      return line.medicine.fullName.toLowerCase().contains(q) ||
          (line.medicine.category?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pharmacyAsync = ref.watch(myPharmacyProvider);
    final stockAsync = ref.watch(myPharmacyInventoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Mon stock',
          style: AppTypography.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            tooltip: 'Ajouter un médicament',
            onPressed: () async {
              final pharmacy = await ref.read(myPharmacyProvider.future);
              if (pharmacy == null || !context.mounted) return;
              await _addMedicine(context, pharmacy.id);
            },
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () {
              ref.invalidate(myPharmacyInventoryProvider);
              ref.invalidate(myPharmacyProvider);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: pharmacyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (pharmacy) {
          if (pharmacy == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Aucune pharmacie liée à votre compte.\n'
                  'Demandez à l’administrateur de vous assigner une pharmacie.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pharmacy.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Rechercher un médicament…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    stockAsync.maybeWhen(
                      data: (lines) {
                        final low = lines
                            .where(
                                (l) => l.inventory.status == StockStatus.lowStock)
                            .length;
                        final out = lines
                            .where((l) =>
                                l.inventory.status == StockStatus.outOfStock)
                            .length;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'Tous (${lines.length})',
                                selected: _filter == 'all',
                                onTap: () => setState(() => _filter = 'all'),
                              ),
                              _FilterChip(
                                label: 'Stock faible ($low)',
                                selected: _filter == 'low',
                                color: AppColors.lowStock,
                                onTap: () => setState(() => _filter = 'low'),
                              ),
                              _FilterChip(
                                label: 'Rupture ($out)',
                                selected: _filter == 'out',
                                color: AppColors.outOfStock,
                                onTap: () => setState(() => _filter = 'out'),
                              ),
                              _FilterChip(
                                label: 'Inconnu',
                                selected: _filter == 'unknown',
                                color: AppColors.unknown,
                                onTap: () =>
                                    setState(() => _filter = 'unknown'),
                              ),
                            ],
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: stockAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (lines) {
                    if (lines.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Stock vide'),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () =>
                                  _addMedicine(context, pharmacy.id),
                              child: const Text('Ajouter un médicament'),
                            ),
                          ],
                        ),
                      );
                    }
                    final visible = _filtered(lines);
                    if (visible.isEmpty) {
                      return const Center(
                        child: Text('Aucun résultat pour ce filtre.'),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final line = visible[i];
                        final inv = line.inventory;
                        return Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _editStock(
                              context,
                              pharmacy.id,
                              line,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.medicine.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          inv.freshnessLabel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: inv.isStale
                                                ? AppColors.accentOrange
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            if (inv.displayQuantity != null)
                                              '${inv.displayQuantity} unités',
                                            if (inv.unitPriceXaf != null)
                                              formatFcfa(inv.unitPriceXaf!),
                                            inv.stockSource.displayName,
                                          ].join(' · '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Màj rapide quantité',
                                    icon: const Icon(Icons.bolt_outlined),
                                    onPressed: () => _quickQty(
                                      context,
                                      pharmacy.id,
                                      line,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editStock(
                                      context,
                                      pharmacy.id,
                                      line,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _quickQty(
    BuildContext context,
    String pharmacyId,
    InventoryLine line,
  ) async {
    final ctrl = TextEditingController(
      text: '${line.inventory.quantity ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantité — ${line.medicine.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nouvelle quantité',
            helperText: 'Le statut sera recalculé (sauf si Inconnu)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(ctrl.text);
    if (qty == null) return;
    await PlatformPharmacyRepository.instance.quickUpdateQuantity(
      pharmacyId: pharmacyId,
      medicineId: line.medicine.id,
      medicineVariantId: line.inventory.medicineVariantId,
      quantity: qty,
      currentStatus: line.inventory.status,
    );
    ref.invalidate(myPharmacyInventoryProvider);
  }

  Future<void> _addMedicine(BuildContext context, String pharmacyId) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddMedicineDialog(pharmacyId: pharmacyId),
    );
    if (saved == true) {
      ref.invalidate(myPharmacyInventoryProvider);
    }
  }

  Future<void> _editStock(
    BuildContext context,
    String pharmacyId,
    InventoryLine line,
  ) async {
    final qtyCtrl =
        TextEditingController(text: '${line.inventory.quantity ?? 0}');
    final priceCtrl = TextEditingController(
      text: '${line.inventory.unitPriceXaf ?? line.medicine.priceXaf ?? 0}',
    );
    var status = line.inventory.status;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(line.medicine.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                line.inventory.freshnessLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<StockStatus>(
                // ignore: deprecated_member_use
                value: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: StockStatus.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setLocal(() => status = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await PlatformPharmacyRepository.instance.upsertInventory(
      pharmacyId: pharmacyId,
      medicineId: line.medicine.id,
      medicineVariantId: line.inventory.medicineVariantId,
      status: status,
      quantity: int.tryParse(qtyCtrl.text),
      unitPriceXaf: int.tryParse(priceCtrl.text),
    );
    ref.invalidate(myPharmacyInventoryProvider);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryBlue;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: c.withValues(alpha: 0.18),
        checkmarkColor: c,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? c : AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PharmacyOrdersTab extends ConsumerWidget {
  const _PharmacyOrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pharmacyOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Commandes pharmacie'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(pharmacyOrdersProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('Aucune commande'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pharmacyOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PharmacyOrderCard(order: orders[i]),
            ),
          );
        },
      ),
    );
  }
}

class _QuickOrderTile extends ConsumerWidget {
  final MedicineOrder order;
  const _QuickOrderTile({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(order.id, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${order.items.isNotEmpty ? order.items.first.medicineName : 'Commande'} · ${order.status.displayName}',
        ),
        trailing: Text(formatFcfa(order.totalXaf)),
        onTap: () => _showActions(context, ref, order),
      ),
    );
  }
}

class _PharmacyOrderCard extends ConsumerWidget {
  final MedicineOrder order;
  const _PharmacyOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.id,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(order.status.displayName,
                  style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(order.pharmacyName),
          Text(
            order.items
                .map((i) => '${i.medicineName} ×${i.quantity}')
                .join(', '),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(formatFcfa(order.totalXaf),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.primaryBlue)),
          if (order.status.isActive) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final uuid = order.supabaseId;
    if (uuid == null) return [];
    final buttons = <Widget>[];

    Future<void> go(OrderStatus s) async {
      await StaffRepository.instance.updateOrderStatus(uuid, s);
      ref.invalidate(pharmacyOrdersProvider);
    }

    if (order.status == OrderStatus.pending ||
        order.status == OrderStatus.confirmed) {
      buttons.add(FilledButton(
        onPressed: () => go(OrderStatus.preparing),
        child: const Text('Préparer'),
      ));
    }
    if (order.status == OrderStatus.preparing) {
      if (order.fulfillment == FulfillmentType.delivery) {
        buttons.add(FilledButton(
          onPressed: () => go(OrderStatus.outForDelivery),
          child: const Text('Remettre au livreur'),
        ));
      } else {
        buttons.add(FilledButton(
          onPressed: () => go(OrderStatus.readyForPickup),
          child: const Text('Prêt au retrait'),
        ));
      }
    }
    if (order.status == OrderStatus.readyForPickup ||
        order.status == OrderStatus.outForDelivery) {
      buttons.add(FilledButton.tonal(
        onPressed: () => go(OrderStatus.delivered),
        child: const Text('Marquer livrée'),
      ));
    }
    buttons.add(TextButton(
      onPressed: () => go(OrderStatus.cancelled),
      child: const Text('Annuler'),
    ));
    return buttons;
  }
}

void _showActions(BuildContext context, WidgetRef ref, MedicineOrder order) {
  showModalBottomSheet(
    context: context,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(20),
      child: _PharmacyOrderCard(order: order),
    ),
  );
}

class _AddMedicineDialog extends StatefulWidget {
  final String pharmacyId;
  const _AddMedicineDialog({required this.pharmacyId});

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _dosage = TextEditingController();
  final _form = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController(text: '1000');
  final _qty = TextEditingController(text: '20');
  StockStatus _status = StockStatus.available;
  bool _rx = false;
  bool _saving = false;
  String? _error;

  static const _forms = [
    'Comprimé',
    'Gélule',
    'Sirop',
    'Injectable',
    'Pommade',
    'Suppositoire',
    'Sachet',
    'Autre',
  ];

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _dosage.dispose();
    _form.dispose();
    _category.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await PlatformPharmacyRepository.instance.addMedicineToPharmacyStock(
        pharmacyId: widget.pharmacyId,
        name: _name.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        dosage: _dosage.text.trim().isEmpty ? null : _dosage.text.trim(),
        form: _form.text.trim().isEmpty ? null : _form.text.trim(),
        category:
            _category.text.trim().isEmpty ? null : _category.text.trim(),
        priceXaf: int.tryParse(_price.text.replaceAll(' ', '')) ?? 0,
        quantity: int.tryParse(_qty.text.replaceAll(' ', '')) ?? 0,
        status: _status,
        requiresPrescription: _rx,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return AlertDialog(
      title: const Text('Ajouter un médicament'),
      content: SizedBox(
        width: 460,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Le médicament est ajouté au catalogue et au stock '
                    'de votre pharmacie.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nom du médicament *',
                      hintText: 'Ex. Paracétamol',
                      filled: true,
                      prefixIcon: Icon(Icons.medication_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _brand,
                    decoration: const InputDecoration(
                      labelText: 'Marque / laboratoire',
                      hintText: 'Ex. Doliprane',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dosage,
                          decoration: const InputDecoration(
                            labelText: 'Dosage',
                            hintText: '500 mg',
                            filled: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          // ignore: deprecated_member_use
                          value: _forms.contains(_form.text) &&
                                  _form.text.isNotEmpty
                              ? _form.text
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Forme',
                            filled: true,
                          ),
                          items: _forms
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _form.text = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _category,
                    decoration: const InputDecoration(
                      labelText: 'Catégorie',
                      hintText: 'Antalgique, antibiotique…',
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prix (FCFA) *',
                            filled: true,
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          validator: (v) {
                            final n = int.tryParse(v?.replaceAll(' ', '') ?? '');
                            if (n == null || n < 0) return 'Prix invalide';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantité *',
                            filled: true,
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          validator: (v) {
                            final n = int.tryParse(v?.replaceAll(' ', '') ?? '');
                            if (n == null || n < 0) return 'Quantité invalide';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StockStatus>(
                    // ignore: deprecated_member_use
                    value: _status,
                    decoration: const InputDecoration(
                      labelText: 'Statut stock',
                      filled: true,
                    ),
                    items: StockStatus.values
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _status = v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ordonnance requise'),
                    value: _rx,
                    onChanged: (v) => setState(() => _rx = v),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text(_saving ? 'Ajout…' : 'Ajouter au stock'),
        ),
      ],
    );
  }
}

