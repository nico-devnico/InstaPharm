import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminCouriersPage extends ConsumerStatefulWidget {
  const AdminCouriersPage({super.key});

  @override
  ConsumerState<AdminCouriersPage> createState() => _AdminCouriersPageState();
}

class _AdminCouriersPageState extends ConsumerState<AdminCouriersPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _page = 1;
  final _pageSize = 20;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;

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
      final data = await AdminRepository.instance.listCouriers(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
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

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CourierFormDialog(existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> c) async {
    final active = c['is_active'] != false;
    final ok = await confirmAdminAction(
      context,
      title: active ? 'Suspendre' : 'Réactiver',
      message: active
          ? 'Suspendre ce livreur ?'
          : 'Réactiver ce livreur ?',
      destructive: active,
    );
    if (!ok) return;
    try {
      await AdminRepository.instance.upsertCourier({
        'id': c['id'],
        'full_name': c['full_name'],
        'phone': c['phone'],
        'is_available': c['is_available'] ?? true,
        'is_active': !active,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _deleteCourier(Map<String, dynamic> c) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Supprimer le livreur',
      message: 'Désactiver définitivement « ${c['full_name']} » ?',
      destructive: true,
      confirmLabel: 'Supprimer',
    );
    if (!ok) return;
    try {
      await AdminRepository.instance.deleteCourier(c['id'].toString());
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
                'Livreurs',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  onPressed: () => _showForm(),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: AdminSearchBar(
              controller: _search,
              hint: 'Nom, téléphone…',
              onChanged: _onSearch,
              onClear: () {
                _page = 1;
                _load();
              },
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
                        ? const AdminEmptyState(message: 'Aucun livreur')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 80),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final c = _items[i];
                                final available = c['is_available'] == true;
                                final active = c['is_active'] != false;
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () => _showForm(existing: c),
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.accentOrange
                                          .withValues(alpha: 0.15),
                                      child: const Icon(
                                        Icons.delivery_dining_rounded,
                                        color: AppColors.accentOrange,
                                      ),
                                    ),
                                    title: Text(
                                      c['full_name']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(c['phone']?.toString() ?? ''),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AdminStatusBadge(
                                          label: available
                                              ? 'Disponible'
                                              : 'Indisponible',
                                          color: available
                                              ? AppColors.accentGreen
                                              : AppColors.textSecondary,
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') {
                                              _showForm(existing: c);
                                            } else if (v == 'toggle') {
                                              _toggleActive(c);
                                            } else if (v == 'delete') {
                                              _deleteCourier(c);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Modifier'),
                                            ),
                                            PopupMenuItem(
                                              value: 'toggle',
                                              child: Text(
                                                active
                                                    ? 'Suspendre'
                                                    : 'Réactiver',
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                'Supprimer',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
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

class _CourierFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _CourierFormDialog({this.existing});

  @override
  State<_CourierFormDialog> createState() => _CourierFormDialogState();
}

class _CourierFormDialogState extends State<_CourierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _available = true;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['full_name']?.toString() ?? '');
    _phone = TextEditingController(text: e?['phone']?.toString() ?? '');
    _available = e?['is_available'] != false;
    _active = e?['is_active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.upsertCourier({
        if (widget.existing?['id'] != null) 'id': widget.existing!['id'],
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'is_available': _available,
        'is_active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Nouveau livreur' : 'Modifier livreur',
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Nom complet *',
                      filled: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone *',
                      filled: true,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponible'),
                    value: _available,
                    onChanged: (v) => setState(() => _available = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    subtitle: const Text(
                      'Préférez lier un compte validé (menu Validations)',
                    ),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
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
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
