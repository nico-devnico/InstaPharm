import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_form_helpers.dart';
import 'admin_widgets.dart';

class AdminMedicinesPage extends ConsumerStatefulWidget {
  const AdminMedicinesPage({super.key});

  @override
  ConsumerState<AdminMedicinesPage> createState() => _AdminMedicinesPageState();
}

class _AdminMedicinesPageState extends ConsumerState<AdminMedicinesPage> {
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
      final data = await AdminRepository.instance.listMedicines(
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
      builder: (ctx) => _MedicineFormDialog(existing: existing),
    );
    if (saved == true) _load();
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
                'Médicaments',
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
              hint: 'Nom, marque, catégorie…',
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
                        ? const AdminEmptyState(
                            message: 'Aucun médicament dans le référentiel',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 80),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final m = _items[i];
                                final active = m['is_active'] != false;
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () => _showForm(existing: m),
                                    title: Text(
                                      m['name']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        m['brand'],
                                        m['dosage'],
                                        m['form'],
                                        m['category'],
                                      ]
                                          .where((e) =>
                                              e != null &&
                                              e.toString().isNotEmpty)
                                          .join(' · '),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatFcfa(
                                            (m['price_xaf'] as num?) ?? 0,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (!active)
                                          const AdminStatusBadge(
                                            label: 'Inactif',
                                            color: AppColors.textSecondary,
                                          )
                                        else if (m['requires_prescription'] ==
                                            true)
                                          const AdminStatusBadge(
                                            label: 'Ordonnance',
                                            color: AppColors.accentOrange,
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

class _MedicineFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _MedicineFormDialog({this.existing});

  @override
  State<_MedicineFormDialog> createState() => _MedicineFormDialogState();
}

class _MedicineFormDialogState extends State<_MedicineFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _dosage;
  late final TextEditingController _form;
  late final TextEditingController _category;
  late final TextEditingController _price;
  bool _rx = false;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _brand = TextEditingController(text: e?['brand']?.toString() ?? '');
    _dosage = TextEditingController(text: e?['dosage']?.toString() ?? '');
    _form = TextEditingController(text: e?['form']?.toString() ?? '');
    _category = TextEditingController(text: e?['category']?.toString() ?? '');
    _price = TextEditingController(
      text: e?['price_xaf']?.toString() ?? '0',
    );
    _rx = e?['requires_prescription'] == true;
    _active = e?['is_active'] != false;
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _dosage.dispose();
    _form.dispose();
    _category.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.upsertMedicine({
        if (widget.existing?['id'] != null) 'id': widget.existing!['id'],
        'name': _name.text.trim(),
        'brand': _brand.text.trim(),
        'dosage': _dosage.text.trim(),
        'form': _form.text.trim(),
        'category': _category.text.trim(),
        'price_xaf': int.tryParse(_price.text.trim()) ?? 0,
        'requires_prescription': _rx,
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
    final h = MediaQuery.sizeOf(context).height;
    final w = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: w < 420 ? 12 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: h * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.10),
                    AppColors.accentGreen.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primaryBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Nouveau médicament'
                          : 'Modifier médicament',
                      style: AppTypography.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      adminFormSection('Identité'),
                      TextFormField(
                        controller: _name,
                        decoration: adminFieldDecoration(
                          'Nom *',
                          prefixIcon: Icons.medication_liquid_rounded,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Requis' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _brand,
                        decoration: adminFieldDecoration(
                          'Marque',
                          prefixIcon: Icons.storefront_outlined,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dosage,
                              decoration: adminFieldDecoration('Dosage'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _form,
                              decoration: adminFieldDecoration('Forme'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _category,
                        decoration: adminFieldDecoration(
                          'Catégorie',
                          prefixIcon: Icons.category_outlined,
                        ),
                      ),
                      adminFormSection('Tarif & statut'),
                      TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        decoration: adminFieldDecoration(
                          'Prix (XAF)',
                          prefixIcon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(height: 8),
                      adminSwitchTile(
                        title: 'Ordonnance requise',
                        subtitle: 'Médicament sous prescription',
                        icon: Icons.receipt_long_outlined,
                        value: _rx,
                        onChanged: (v) => setState(() => _rx = v),
                      ),
                      adminSwitchTile(
                        title: 'Actif dans le catalogue',
                        icon: Icons.toggle_on_outlined,
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _saving ? 'Enregistrement…' : 'Enregistrer',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
