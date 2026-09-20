import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminOrdersPage extends ConsumerStatefulWidget {
  /// Si true, n’affiche que les commandes livraison / en cours de livraison.
  final bool deliveriesOnly;

  const AdminOrdersPage({super.key, this.deliveriesOnly = false});

  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;
  int _page = 1;
  final _pageSize = 20;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;

  static const _statuses = <String?, String>{
    null: 'Tous',
    'pending': 'En attente',
    'confirmed': 'Confirmée',
    'preparing': 'Préparation',
    'out_for_delivery': 'En livraison',
    'ready_for_pickup': 'Prête',
    'delivered': 'Livrée',
    'cancelled': 'Annulée',
  };

  @override
  void initState() {
    super.initState();
    if (widget.deliveriesOnly) {
      _status = 'out_for_delivery';
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminRepository.instance.listOrders(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        status: _status,
        page: _page,
        pageSize: _pageSize,
      );
      var items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (widget.deliveriesOnly && _status == null) {
        items = items
            .where((o) =>
                o['fulfillment']?.toString() == 'delivery' ||
                o['status']?.toString() == 'out_for_delivery')
            .toList();
      }
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

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _load();
    });
  }

  Future<void> _openDetail(String id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _OrderDetailDialog(orderId: id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.padH(context);
    final title = widget.deliveriesOnly ? 'Livraisons' : 'Commandes';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: Responsive.isDesktop(context)
          ? AppBar(
              backgroundColor: AppColors.background,
              title: Text(
                title,
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: Column(
              children: [
                AdminSearchBar(
                  controller: _search,
                  hint: 'Code commande, pharmacie…',
                  onChanged: _onSearch,
                  onClear: () {
                    _page = 1;
                    _load();
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
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
                        ? AdminEmptyState(
                            message: widget.deliveriesOnly
                                ? 'Aucune livraison'
                                : 'Aucune commande',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final o = _items[i];
                                final profile = o['profiles'];
                                final courier = o['couriers'];
                                final customer = profile is Map
                                    ? profile['full_name']?.toString()
                                    : null;
                                final courierName = courier is Map
                                    ? courier['full_name']?.toString()
                                    : null;
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () =>
                                        _openDetail(o['id'].toString()),
                                    title: Text(
                                      o['public_code']?.toString() ??
                                          o['id']?.toString() ??
                                          '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        o['pharmacy_name'],
                                        customer,
                                        courierName,
                                        o['status'],
                                      ]
                                          .where((e) =>
                                              e != null &&
                                              e.toString().isNotEmpty)
                                          .join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(
                                      formatFcfa(
                                        (o['subtotal_xaf'] as num?) ?? 0,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
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

class _OrderDetailDialog extends StatefulWidget {
  final String orderId;
  const _OrderDetailDialog({required this.orderId});

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _order;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AdminRepository.instance.getOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = Map<String, dynamic>.from(data['order'] as Map);
        _items = data['items'] as List? ??
            _order?['order_items'] as List? ??
            [];
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

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final profile = o?['profiles'];
    final courier = o?['couriers'];
    return AlertDialog(
      title: Text(
        o?['public_code']?.toString() ?? 'Commande',
      ),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!)
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Statut', o?['status']?.toString() ?? '—'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: o?['status']?.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Changer le statut',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'pending', child: Text('En attente')),
                            DropdownMenuItem(
                                value: 'confirmed', child: Text('Confirmée')),
                            DropdownMenuItem(
                                value: 'preparing',
                                child: Text('Préparation')),
                            DropdownMenuItem(
                                value: 'ready_for_pickup',
                                child: Text('Prête')),
                            DropdownMenuItem(
                                value: 'out_for_delivery',
                                child: Text('En livraison')),
                            DropdownMenuItem(
                                value: 'delivered', child: Text('Livrée')),
                            DropdownMenuItem(
                                value: 'cancelled', child: Text('Annulée')),
                          ],
                          onChanged: (v) async {
                            if (v == null || o == null) return;
                            try {
                              await AdminRepository.instance
                                  .updateOrderStatus(widget.orderId, v);
                              await _load();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erreur : $e')),
                                );
                              }
                            }
                          },
                        ),
                        _row(
                          'Pharmacie',
                          o?['pharmacy_name']?.toString() ?? '—',
                        ),
                        _row(
                          'Client',
                          profile is Map
                              ? [
                                  profile['full_name'],
                                  profile['email'],
                                  profile['phone'],
                                ]
                                  .where((e) =>
                                      e != null && e.toString().isNotEmpty)
                                  .join(' · ')
                              : '—',
                        ),
                        _row(
                          'Livreur',
                          courier is Map
                              ? [
                                  courier['full_name'],
                                  courier['phone'],
                                ]
                                  .where((e) =>
                                      e != null && e.toString().isNotEmpty)
                                  .join(' · ')
                              : '—',
                        ),
                        _row(
                          'Paiement',
                          o?['payment_method']?.toString() ??
                              o?['payment_status']?.toString() ??
                              '—',
                        ),
                        _row(
                          'Total',
                          formatFcfa((o?['subtotal_xaf'] as num?) ?? 0),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Articles',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        if (_items.isEmpty)
                          const Text(
                            'Aucun article',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          ..._items.map((it) {
                            final m = Map<String, dynamic>.from(it as Map);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                m['medicine_name']?.toString() ??
                                    m['name']?.toString() ??
                                    'Article',
                              ),
                              subtitle: Text('x${m['quantity'] ?? 1}'),
                              trailing: Text(
                                formatFcfa(
                                  (m['unit_price_xaf'] as num?) ??
                                      (m['price_xaf'] as num?) ??
                                      0,
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
