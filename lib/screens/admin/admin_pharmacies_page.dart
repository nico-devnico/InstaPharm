import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/cameroon.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_form_helpers.dart';
import 'admin_widgets.dart';

class AdminPharmaciesPage extends ConsumerStatefulWidget {
  const AdminPharmaciesPage({super.key});

  @override
  ConsumerState<AdminPharmaciesPage> createState() =>
      _AdminPharmaciesPageState();
}

class _AdminPharmaciesPageState extends ConsumerState<AdminPharmaciesPage> {
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
    null: 'Toutes',
    'PENDING': 'PENDING',
    'VERIFIED': 'VERIFIED',
    'REJECTED': 'REJECTED',
    'SUSPENDED': 'SUSPENDED',
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
      final data = await AdminRepository.instance.listPharmacies(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
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
      builder: (ctx) => _PharmacyFormDialog(existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _setStatus(String id, String status) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Changer le statut',
      message: 'Passer cette pharmacie en $status ?',
      destructive: status == 'REJECTED' || status == 'SUSPENDED',
      confirmLabel: status,
    );
    if (!ok) return;
    try {
      await AdminRepository.instance.setPharmacyStatus(id, status);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PharmacyDetailSheet(
        pharmacyId: p['id'].toString(),
        onEdit: () {
          Navigator.pop(ctx);
          _showForm(existing: p);
        },
        onStatus: (st) async {
          Navigator.pop(ctx);
          await _setStatus(p['id'].toString(), st);
        },
      ),
    );
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
                'Pharmacies',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Ajouter',
                  onPressed: () => _showForm(),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: Responsive.isDesktop(context)
          ? null
          : FloatingActionButton(
              onPressed: () => _showForm(),
              child: const Icon(Icons.add_rounded),
            ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: Column(
              children: [
                AdminSearchBar(
                  controller: _search,
                  hint: 'Nom, ville, adresse…',
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
                        ? const AdminEmptyState(
                            message: 'Aucune pharmacie trouvée',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final useGrid = constraints.maxWidth >= 720;
                                if (!useGrid) {
                                  return ListView.separated(
                                    padding:
                                        EdgeInsets.fromLTRB(pad, 12, pad, 80),
                                    itemCount: _items.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, i) =>
                                        _pharmacyTile(_items[i]),
                                  );
                                }
                                final cross = constraints.maxWidth >= 1100
                                    ? 3
                                    : 2;
                                return GridView.builder(
                                  padding:
                                      EdgeInsets.fromLTRB(pad, 12, pad, 80),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cross,
                                    mainAxisExtent: 108,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: _items.length,
                                  itemBuilder: (_, i) =>
                                      _pharmacyTile(_items[i]),
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

  Widget _pharmacyTile(Map<String, dynamic> p) {
    final st = p['platform_status']?.toString() ?? 'VERIFIED';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: () => _openDetail(p),
        leading: CircleAvatar(
          backgroundColor:
              pharmacyStatusColor(st).withValues(alpha: 0.15),
          child: Icon(
            Icons.local_pharmacy_rounded,
            color: pharmacyStatusColor(st),
          ),
        ),
        title: Text(
          p['name']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            p['city'],
            p['address'],
            p['phone'],
          ]
              .where((e) => e != null && e.toString().isNotEmpty)
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Modifier')),
            PopupMenuItem(value: 'VERIFIED', child: Text('Vérifier')),
            PopupMenuItem(value: 'REJECTED', child: Text('Rejeter')),
            PopupMenuItem(value: 'SUSPENDED', child: Text('Suspendre')),
            PopupMenuItem(
              value: 'PENDING',
              child: Text('Remettre en attente'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Désactiver / supprimer',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
          onSelected: (v) async {
            if (v == 'edit') {
              _showForm(existing: p);
            } else if (v == 'delete') {
              final ok = await confirmAdminAction(
                context,
                title: 'Désactiver la pharmacie',
                message:
                    'Cette pharmacie sera suspendue et retirée de la plateforme.',
                destructive: true,
                confirmLabel: 'Désactiver',
              );
              if (!ok) return;
              try {
                await AdminRepository.instance
                    .deactivatePharmacy(p['id'].toString());
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur : $e')),
                  );
                }
              }
            } else {
              _setStatus(p['id'].toString(), v);
            }
          },
        ),
      ),
    );
  }
}

class _PharmacyFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _PharmacyFormDialog({this.existing});

  @override
  State<_PharmacyFormDialog> createState() => _PharmacyFormDialogState();
}

class _PharmacyFormDialogState extends State<_PharmacyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  String _status = 'VERIFIED';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _city = TextEditingController(text: e?['city']?.toString() ?? '');
    _address = TextEditingController(text: e?['address']?.toString() ?? '');
    _phone = TextEditingController(text: e?['phone']?.toString() ?? '');
    _lat = TextEditingController(
      text: e?['latitude']?.toString() ??
          CameroonDefaults.douala.latitude.toStringAsFixed(5),
    );
    _lng = TextEditingController(
      text: e?['longitude']?.toString() ??
          CameroonDefaults.douala.longitude.toStringAsFixed(5),
    );
    _status = e?['platform_status']?.toString() ?? 'VERIFIED';
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final lat = double.tryParse(_lat.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Latitude et longitude GPS obligatoires'),
        ),
      );
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordonnées GPS hors plage valide')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.upsertPharmacy({
        if (widget.existing?['id'] != null) 'id': widget.existing!['id'],
        'name': _name.text.trim(),
        'city': _city.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'latitude': lat,
        'longitude': lng,
        'platform_status': _status,
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
                      Icons.local_pharmacy_rounded,
                      color: AppColors.primaryBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Nouvelle pharmacie'
                          : 'Modifier pharmacie',
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
                      adminFormSection('Informations'),
                      TextFormField(
                        controller: _name,
                        decoration: adminFieldDecoration(
                          'Nom *',
                          prefixIcon: Icons.store_rounded,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 2)
                                ? 'Requis'
                                : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _city,
                        decoration: adminFieldDecoration(
                          'Ville',
                          prefixIcon: Icons.location_city_outlined,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _address,
                        decoration: adminFieldDecoration(
                          'Adresse',
                          prefixIcon: Icons.place_outlined,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _phone,
                        decoration: adminFieldDecoration(
                          'Téléphone',
                          prefixIcon: Icons.phone_outlined,
                        ),
                      ),
                      adminFormSection(
                        'Position GPS (carte)',
                        hint:
                            'Obligatoire : l’icône apparaît sur la carte pour tous les utilisateurs',
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _lat,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: adminFieldDecoration('Latitude *'),
                              validator: (v) => double.tryParse(
                                        (v ?? '').replaceAll(',', '.'),
                                      ) ==
                                      null
                                  ? 'GPS'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _lng,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: adminFieldDecoration('Longitude *'),
                              validator: (v) => double.tryParse(
                                        (v ?? '').replaceAll(',', '.'),
                                      ) ==
                                      null
                                  ? 'GPS'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _status,
                        decoration: adminFieldDecoration(
                          'Statut plateforme',
                          prefixIcon: Icons.verified_outlined,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'PENDING',
                            child: Text('PENDING'),
                          ),
                          DropdownMenuItem(
                            value: 'VERIFIED',
                            child: Text('VERIFIED'),
                          ),
                          DropdownMenuItem(
                            value: 'REJECTED',
                            child: Text('REJECTED'),
                          ),
                          DropdownMenuItem(
                            value: 'SUSPENDED',
                            child: Text('SUSPENDED'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _status = v ?? _status),
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

class _PharmacyDetailSheet extends StatefulWidget {
  final String pharmacyId;
  final VoidCallback onEdit;
  final Future<void> Function(String status) onStatus;

  const _PharmacyDetailSheet({
    required this.pharmacyId,
    required this.onEdit,
    required this.onStatus,
  });

  @override
  State<_PharmacyDetailSheet> createState() => _PharmacyDetailSheetState();
}

class _PharmacyDetailSheetState extends State<_PharmacyDetailSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _pharmacy;
  List<dynamic> _stock = [];
  List<dynamic> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await AdminRepository.instance.pharmacyDetail(widget.pharmacyId);
      if (!mounted) return;
      setState(() {
        _pharmacy = Map<String, dynamic>.from(data['pharmacy'] as Map);
        _stock = data['stock'] as List? ?? [];
        _orders = data['orders'] as List? ?? [];
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
    final h = MediaQuery.sizeOf(context).height * 0.85;
    return SizedBox(
      height: h,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AdminEmptyState(message: _error!)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Text(
                      _pharmacy?['name']?.toString() ?? '',
                      style: AppTypography.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [
                        _pharmacy?['city'],
                        _pharmacy?['address'],
                        _pharmacy?['phone'],
                      ]
                          .where((e) => e != null && e.toString().isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    AdminStatusBadge(
                      label: _pharmacy?['platform_status']?.toString() ?? '',
                      color: pharmacyStatusColor(
                        _pharmacy?['platform_status']?.toString(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: widget.onEdit,
                          child: const Text('Modifier'),
                        ),
                        OutlinedButton(
                          onPressed: () => widget.onStatus('VERIFIED'),
                          child: const Text('Vérifier'),
                        ),
                        OutlinedButton(
                          onPressed: () => widget.onStatus('REJECTED'),
                          child: const Text('Rejeter'),
                        ),
                        OutlinedButton(
                          onPressed: () => widget.onStatus('SUSPENDED'),
                          child: const Text('Suspendre'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Stock (${_stock.length})',
                      style: AppTypography.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (_stock.isEmpty)
                      const Text(
                        'Aucun stock',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      ..._stock.take(15).map((s) {
                        final m = Map<String, dynamic>.from(s as Map);
                        final med = m['medicines'];
                        final name = med is Map
                            ? med['name']?.toString()
                            : m['medicine_name']?.toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(name ?? 'Médicament'),
                          trailing: Text('${m['quantity'] ?? m['status'] ?? ''}'),
                        );
                      }),
                    const SizedBox(height: 16),
                    Text(
                      'Commandes (${_orders.length})',
                      style: AppTypography.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (_orders.isEmpty)
                      const Text(
                        'Aucune commande',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      ..._orders.take(15).map((o) {
                        final m = Map<String, dynamic>.from(o as Map);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            m['public_code']?.toString() ??
                                m['id']?.toString() ??
                                '',
                          ),
                          subtitle: Text('${m['status'] ?? ''}'),
                          trailing: Text('${m['subtotal_xaf'] ?? ''} XAF'),
                        );
                      }),
                  ],
                ),
    );
  }
}
