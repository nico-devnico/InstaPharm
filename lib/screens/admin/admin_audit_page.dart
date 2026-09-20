import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminAuditPage extends ConsumerStatefulWidget {
  const AdminAuditPage({super.key});

  @override
  ConsumerState<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends ConsumerState<AdminAuditPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _page = 1;
  final _pageSize = 40;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  String? _resourceType;

  static const _resourceFilters = <String?, String>{
    null: 'Toutes',
    'pharmacy': 'Pharmacies',
    'profile': 'Utilisateurs',
    'medicine': 'Médicaments',
    'inventory': 'Stocks',
    'order': 'Commandes',
    'courier': 'Livreurs',
    'report': 'Signalements',
    'setting': 'Paramètres',
    'app': 'Application',
  };

  @override
  void initState() {
    super.initState();
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
      final data = await AdminRepository.instance.listAuditLogs(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        resourceType: _resourceType,
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

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _load();
    });
  }

  String _actor(Map<String, dynamic> log) {
    final name = log['actor_name']?.toString();
    final email = log['actor_email']?.toString();
    if (name != null && name.isNotEmpty) return name;
    if (email != null && email.isNotEmpty) return email;
    final profile = log['profiles'];
    if (profile is Map) {
      return profile['full_name']?.toString() ??
          profile['email']?.toString() ??
          'Acteur';
    }
    return log['actor_id']?.toString() ?? 'Système';
  }

  String _date(Map<String, dynamic> log) {
    final raw = log['created_at']?.toString();
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _metaText(Map<String, dynamic> log) {
    final meta = log['meta'];
    if (meta == null) return '';
    try {
      if (meta is Map) {
        if (meta.isEmpty) return '';
        return const JsonEncoder.withIndent('  ').convert(meta);
      }
      return meta.toString();
    } catch (_) {
      return meta.toString();
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
                'Journal d’audit',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminSearchBar(
                  controller: _search,
                  hint: 'Action, ressource, meta…',
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
                      for (final e in _resourceFilters.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(e.value),
                            selected: _resourceType == e.key,
                            onSelected: (_) {
                              setState(() {
                                _resourceType = e.key;
                                _page = 1;
                              });
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Toutes les opérations admin et actions applicatives journalisées.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
                        ? const AdminEmptyState(message: 'Aucun log d’audit')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final log = _items[i];
                                final action =
                                    log['action']?.toString() ?? '—';
                                final resourceType =
                                    log['resource_type']?.toString() ?? '';
                                final resourceId =
                                    log['resource_id']?.toString() ?? '';
                                final ip = log['ip']?.toString();
                                final meta = _metaText(log);
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 4,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      14,
                                      12,
                                    ),
                                    title: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: _actor(log),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: '  →  ',
                                            style: TextStyle(
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                          TextSpan(
                                            text: action,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        [
                                          if (resourceType.isNotEmpty)
                                            resourceType,
                                          if (resourceId.isNotEmpty) resourceId,
                                          _date(log),
                                          if (ip != null && ip.isNotEmpty)
                                            'IP $ip',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    children: [
                                      if (meta.isNotEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceVariant,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            meta,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              height: 1.35,
                                            ),
                                          ),
                                        )
                                      else
                                        const Text(
                                          'Aucun détail supplémentaire',
                                          style: TextStyle(
                                            color: AppColors.textTertiary,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
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
