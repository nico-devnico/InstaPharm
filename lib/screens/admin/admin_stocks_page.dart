import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminStocksPage extends ConsumerStatefulWidget {
  const AdminStocksPage({super.key});

  @override
  ConsumerState<AdminStocksPage> createState() => _AdminStocksPageState();
}

class _AdminStocksPageState extends ConsumerState<AdminStocksPage> {
  String? _pharmacyId;
  String? _status;
  int _page = 1;
  final _pageSize = 30;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _pharmacies = [];
  int _total = 0;

  static const _statuses = <String?, String>{
    null: 'Tous',
    'available': 'Disponible',
    'low_stock': 'Stock faible',
    'out_of_stock': 'Rupture',
  };

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final ph = await AdminRepository.instance.listPharmacies(
        page: 1,
        pageSize: 100,
      );
      _pharmacies = (ph['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminRepository.instance.listStocks(
        pharmacyId: _pharmacyId,
        status: _status,
        page: _page,
        pageSize: _pageSize,
      );
      final items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var total = (data['total'] as num?)?.toInt() ?? items.length;
      if (items.length >= _pageSize && total <= _page * _pageSize) {
        total = _page * _pageSize + 1;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'available':
        return AppColors.available;
      case 'low_stock':
        return AppColors.lowStock;
      case 'out_of_stock':
        return AppColors.outOfStock;
      default:
        return AppColors.unknown;
    }
  }

  Future<void> _editStock(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null) return;
    final qtyCtrl = TextEditingController(
      text: s['quantity']?.toString() ?? '0',
    );
    String status = s['status']?.toString() ?? 'available';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Modifier le stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantité'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(
                      value: 'available', child: Text('Disponible')),
                  DropdownMenuItem(
                      value: 'low_stock', child: Text('Stock faible')),
                  DropdownMenuItem(
                      value: 'out_of_stock', child: Text('Rupture')),
                ],
                onChanged: (v) => setLocal(() => status = v ?? status),
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
    try {
      await AdminRepository.instance.updateStock(
        inventoryId: id,
        quantity: int.tryParse(qtyCtrl.text.trim()),
        status: status,
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.padH(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: Responsive.isDesktop(context)
          ? AppBar(
              backgroundColor: AppColors.background,
              title: Text(
                'Stocks',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Column(
        children: [
          if (_pharmacies.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Toutes pharmacies'),
                      selected: _pharmacyId == null,
                      onSelected: (_) {
                        setState(() {
                          _pharmacyId = null;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ),
                  for (final p in _pharmacies)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(p['name']?.toString() ?? ''),
                        selected: _pharmacyId == p['id']?.toString(),
                        onSelected: (_) {
                          setState(() {
                            _pharmacyId = p['id']?.toString();
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              children: [
                for (final e in _statuses.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) {
                        setState(() {
                          _status = e.key;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? AdminEmptyState(
                        message: _error!,
                        icon: Icons.error_outline,
                        action: FilledButton(
                          onPressed: _load,
                          child: const Text('Réessayer'),
                        ),
                      )
                    : _items.isEmpty
                        ? const AdminEmptyState(message: 'Aucun stock')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final s = _items[i];
                                final med = s['medicines'];
                                final ph = s['pharmacies'];
                                final medName = med is Map
                                    ? med['name']?.toString()
                                    : null;
                                final phName = ph is Map
                                    ? ph['name']?.toString()
                                    : null;
                                final st = s['status']?.toString();
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () => _editStock(s),
                                    title: Text(
                                      medName ?? 'Médicament',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        phName,
                                        if (s['quantity'] != null)
                                          'Qté ${s['quantity']}',
                                      ]
                                          .where((e) =>
                                              e != null &&
                                              e.toString().isNotEmpty)
                                          .join(' · '),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AdminStatusBadge(
                                          label: st ?? '—',
                                          color: _statusColor(st),
                                        ),
                                        const Icon(Icons.edit_outlined,
                                            size: 18),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: AdminPaginationBar(
              page: _page,
              pageSize: _pageSize,
              total: _total,
              onPrev: () {
                setState(() => _page--);
                _load();
              },
              onNext: () {
                setState(() => _page++);
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }
}
