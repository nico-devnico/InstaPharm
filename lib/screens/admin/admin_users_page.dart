import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/super_admin.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _role;
  int _page = 1;
  final _pageSize = 20;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;

  static const _roles = <String?, String>{
    null: 'Tous',
    'patient': 'CLIENT',
    'pharmacist': 'PHARMACIEN',
    'courier': 'LIVREUR',
    'admin': 'ADMIN',
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
      final data = await AdminRepository.instance.listUsers(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        role: _role,
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

  Future<void> _openDetail(Map<String, dynamic> user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _UserDetailSheet(
        userId: user['id'].toString(),
        onChanged: _load,
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
                'Utilisateurs',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Ajouter',
                  onPressed: _showCreate,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreate,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Ajouter'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            child: Column(
              children: [
                AdminSearchBar(
                  controller: _search,
                  hint: 'Nom, e-mail, téléphone…',
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
                      for (final e in _roles.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(e.value),
                            selected: _role == e.key,
                            onSelected: (_) {
                              setState(() {
                                _role = e.key;
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
                            message: 'Aucun utilisateur trouvé',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 88),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final u = _items[i];
                                final role = u['role']?.toString();
                                final active = u['is_active'] != false;
                                final isSuper = SuperAdmin.isSuperAdminEmail(
                                  u['email']?.toString(),
                                );
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () => _openDetail(u),
                                    leading: CircleAvatar(
                                      backgroundColor: roleColor(role)
                                          .withValues(alpha: 0.15),
                                      child: Icon(
                                        isSuper
                                            ? Icons.shield_rounded
                                            : Icons.person_rounded,
                                        color: roleColor(role),
                                      ),
                                    ),
                                    title: Text(
                                      u['full_name']?.toString() ??
                                          u['email']?.toString() ??
                                          'Sans nom',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        u['email'],
                                        u['phone'],
                                        if (isSuper) 'Super admin',
                                        if (!active && !isSuper) 'Suspendu',
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
                                          label: isSuper
                                              ? 'SUPER'
                                              : roleLabel(role),
                                          color: isSuper
                                              ? AppColors.accentOrange
                                              : roleColor(role),
                                        ),
                                        if (!isSuper)
                                          PopupMenuButton<String>(
                                            onSelected: (v) =>
                                                _onUserAction(u, v),
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Modifier'),
                                              ),
                                              PopupMenuItem(
                                                value: active
                                                    ? 'suspend'
                                                    : 'activate',
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

  Future<void> _showCreate() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _CreateUserDialog(),
    );
    if (saved == true) _load();
  }

  Future<void> _onUserAction(Map<String, dynamic> u, String action) async {
    final id = u['id'].toString();
    try {
      if (action == 'edit') {
        await _openDetail(u);
        return;
      }
      if (action == 'suspend') {
        final ok = await confirmAdminAction(
          context,
          title: 'Suspendre',
          message: 'Suspendre ce compte utilisateur ?',
          destructive: true,
          confirmLabel: 'Suspendre',
        );
        if (!ok) return;
        await AdminRepository.instance.suspendUser(id, reason: 'Suspendu par admin');
      } else if (action == 'activate') {
        await AdminRepository.instance.activateUser(id);
      } else if (action == 'delete') {
        final ok = await confirmAdminAction(
          context,
          title: 'Supprimer',
          message:
              'Désactiver définitivement ce compte (suppression soft) ?',
          destructive: true,
          confirmLabel: 'Supprimer',
        );
        if (!ok) return;
        await AdminRepository.instance.deleteUser(id);
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    }
  }
}

class _UserDetailSheet extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onChanged;

  const _UserDetailSheet({required this.userId, required this.onChanged});

  @override
  ConsumerState<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends ConsumerState<_UserDetailSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _user;
  List<dynamic> _orders = [];
  String? _role;
  bool _busy = false;
  late final TextEditingController _name;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminRepository.instance.getUser(widget.userId);
      if (!mounted) return;
      final user = Map<String, dynamic>.from(data['user'] as Map);
      _name.text = user['full_name']?.toString() ?? '';
      _phone.text = user['phone']?.toString() ?? '';
      setState(() {
        _user = user;
        _orders = data['recentOrders'] as List? ?? [];
        _role = user['role']?.toString() ?? 'patient';
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

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.updateUser(widget.userId, {
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      });
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRole(String role) async {
    final ok = await confirmAdminAction(
      context,
      title: 'Changer le rôle',
      message: 'Attribuer le rôle « ${roleLabel(role)} » à cet utilisateur ?',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.updateUser(widget.userId, {'role': role});
      setState(() => _role = role);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rôle mis à jour')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive() async {
    final active = _user?['is_active'] != false;
    final ok = await confirmAdminAction(
      context,
      title: active ? 'Suspendre' : 'Réactiver',
      message: active
          ? 'Suspendre ce compte utilisateur ?'
          : 'Réactiver ce compte utilisateur ?',
      destructive: active,
      confirmLabel: active ? 'Suspendre' : 'Réactiver',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      if (active) {
        await AdminRepository.instance
            .suspendUser(widget.userId, reason: 'Suspendu par admin');
      } else {
        await AdminRepository.instance.activateUser(widget.userId);
      }
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAdminAction(
      context,
      title: 'Supprimer',
      message: 'Désactiver définitivement ce compte ?',
      destructive: true,
      confirmLabel: 'Supprimer',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.deleteUser(widget.userId);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Modifier utilisateur',
                      style: AppTypography.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _user?['email']?.toString() ?? '',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone',
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _saveProfile,
                      child: const Text('Enregistrer le profil'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: _role,
                      decoration: InputDecoration(
                        labelText: SuperAdmin.isSuperAdminEmail(
                          _user?['email']?.toString(),
                        )
                            ? 'Rôle (protégé)'
                            : 'Rôle',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'patient',
                          child: Text('CLIENT'),
                        ),
                        DropdownMenuItem(
                          value: 'pharmacist',
                          child: Text('PHARMACIEN'),
                        ),
                        DropdownMenuItem(
                          value: 'courier',
                          child: Text('LIVREUR'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('ADMIN'),
                        ),
                      ],
                      onChanged: _busy ||
                              SuperAdmin.isSuperAdminEmail(
                                _user?['email']?.toString(),
                              )
                          ? null
                          : (v) {
                              if (v != null && v != _role) _saveRole(v);
                            },
                    ),
                    const SizedBox(height: 12),
                    if (!SuperAdmin.isSuperAdminEmail(
                      _user?['email']?.toString(),
                    )) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _toggleActive,
                        icon: Icon(
                          _user?['is_active'] != false
                              ? Icons.block_rounded
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          _user?['is_active'] != false
                              ? 'Suspendre le compte'
                              : 'Réactiver le compte',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        label: const Text('Supprimer'),
                      ),
                    ] else
                      const Text(
                        'Compte super-admin protégé — suspension / suppression impossibles.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accentOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Commandes récentes',
                      style: AppTypography.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (_orders.isEmpty)
                      const Text(
                        'Aucune commande',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      ..._orders.map((o) {
                        final m = Map<String, dynamic>.from(o as Map);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            m['public_code']?.toString() ??
                                m['id']?.toString() ??
                                '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${m['pharmacy_name'] ?? ''} · ${m['status'] ?? ''}',
                          ),
                          trailing: Text(
                            '${m['subtotal_xaf'] ?? ''} XAF',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'patient';
  bool _saving = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.createUserProfile(
        email: _email.text.trim(),
        fullName: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        role: _role,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un utilisateur'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail *',
                    filled: true,
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'E-mail invalide' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: const [
                    DropdownMenuItem(value: 'patient', child: Text('CLIENT')),
                    DropdownMenuItem(
                      value: 'pharmacist',
                      child: Text('PHARMACIEN'),
                    ),
                    DropdownMenuItem(value: 'courier', child: Text('LIVREUR')),
                    DropdownMenuItem(value: 'admin', child: Text('ADMIN')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Si l’API admin n’est pas configurée, la personne doit '
                  's’inscrire dans l’app ; vous pourrez ensuite gérer son compte.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
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
              : const Text('Créer'),
        ),
      ],
    );
  }
}

