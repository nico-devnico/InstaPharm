import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../providers/app_config_provider.dart';
import '../../services/admin_repository.dart';
import '../../services/auth_service.dart';
import 'admin_form_helpers.dart';
import 'admin_widgets.dart';

class AdminSettingsPage extends ConsumerStatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  ConsumerState<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends ConsumerState<AdminSettingsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  static const _secretHints = [
    'secret',
    'password',
    'token',
    'api_key',
    'apikey',
    'private',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isSecret(Map<String, dynamic> s) {
    final key = (s['key']?.toString() ?? '').toLowerCase();
    final cat = (s['category']?.toString() ?? '').toLowerCase();
    return _secretHints.any((h) => key.contains(h) || cat.contains(h));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminRepository.instance.listSettings();
      final items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => !_isSecret(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      ref.invalidate(appConfigProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> setting) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SettingEditDialog(setting: setting),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Paramètre enregistré — appliqué à toute l’application.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe mis à jour')),
      );
    }
  }

  Map<String, List<Map<String, dynamic>>> _grouped() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in _items) {
      final cat = s['category']?.toString() ?? 'Général';
      map.putIfAbsent(cat, () => []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.padH(context);
    final groups = _grouped();
    final cfg = ref.watch(appConfigValueProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: Responsive.isDesktop(context)
          ? AppBar(
              backgroundColor: AppColors.background,
              title: Text(
                'Paramètres',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                IconButton(
                  tooltip: 'Mot de passe',
                  onPressed: _changePassword,
                  icon: const Icon(Icons.lock_reset_rounded),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _changePassword,
        icon: const Icon(Icons.lock_reset_rounded),
        label: const Text('Mot de passe'),
      ),
      body: _loading
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 100),
                    children: [
                      Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Effet immédiat sur l’app',
                                style: AppTypography.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Livraison ${cfg.deliveryBaseXaf} / express ${cfg.deliveryExpressXaf} XAF · '
                                'Rayon recherche ${cfg.searchRadiusKm} km · '
                                'Approbation pro : ${cfg.requireStaffApproval ? 'oui' : 'non'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: AdminEmptyState(message: 'Aucun paramètre'),
                        ),
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            entry.key,
                            style: AppTypography.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        ...entry.value.map((s) {
                          final label = s['label']?.toString();
                          final key = s['key']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                onTap: () => _edit(s),
                                title: Text(
                                  (label != null && label.isNotEmpty)
                                      ? label
                                      : key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _old = TextEditingController();
  final _neu = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _neu.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(
        currentPassword: _old.text,
        newPassword: _neu.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Changer le mot de passe'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _old,
                obscureText: _obscure,
                decoration: adminFieldDecoration('Mot de passe actuel *'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _neu,
                obscureText: _obscure,
                decoration: adminFieldDecoration('Nouveau mot de passe *'),
                validator: (v) =>
                    (v == null || v.length < 8) ? '8 caractères min.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: adminFieldDecoration('Confirmer *'),
                validator: (v) =>
                    v != _neu.text ? 'Les mots de passe diffèrent' : null,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  label: Text(_obscure ? 'Afficher' : 'Masquer'),
                ),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
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

class _SettingEditDialog extends StatefulWidget {
  final Map<String, dynamic> setting;
  const _SettingEditDialog({required this.setting});

  @override
  State<_SettingEditDialog> createState() => _SettingEditDialogState();
}

class _SettingEditDialogState extends State<_SettingEditDialog> {
  late Map<String, TextEditingController> _fields;
  late final TextEditingController _raw;
  bool _saving = false;
  String? _parseError;
  bool _useRaw = false;

  @override
  void initState() {
    super.initState();
    final v = widget.setting['value'];
    _fields = {};
    if (v is Map) {
      for (final e in v.entries) {
        _fields[e.key.toString()] =
            TextEditingController(text: '${e.value}');
      }
    } else {
      _useRaw = true;
    }
    try {
      _raw = TextEditingController(
        text: v is String
            ? v
            : const JsonEncoder.withIndent('  ').convert(v),
      );
    } catch (_) {
      _raw = TextEditingController(text: v?.toString() ?? '');
      _useRaw = true;
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _raw.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _parseError = null;
    });
    try {
      dynamic parsed;
      if (_useRaw || _fields.isEmpty) {
        final raw = _raw.text.trim();
        try {
          parsed = jsonDecode(raw);
        } catch (_) {
          parsed = raw;
        }
      } else {
        final map = <String, dynamic>{};
        for (final e in _fields.entries) {
          final t = e.value.text.trim();
          if (t == 'true' || t == 'false') {
            map[e.key] = t == 'true';
          } else if (num.tryParse(t) != null) {
            map[e.key] = num.parse(t);
          } else {
            map[e.key] = t;
          }
        }
        parsed = map;
      }
      await AdminRepository.instance.updateSetting(
        widget.setting['key'].toString(),
        parsed,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _parseError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.setting['label']?.toString() ??
        widget.setting['key']?.toString() ??
        'Paramètre';
    final h = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.65),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.setting['key']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_useRaw && _fields.isNotEmpty)
                  ..._fields.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: e.value,
                        decoration: adminFieldDecoration(e.key),
                      ),
                    ),
                  )
                else
                  TextField(
                    controller: _raw,
                    maxLines: 12,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: adminFieldDecoration('Valeur JSON'),
                  ),
                TextButton(
                  onPressed: () => setState(() => _useRaw = !_useRaw),
                  child: Text(_useRaw
                      ? 'Édition par champs'
                      : 'Édition JSON brute'),
                ),
                if (_parseError != null)
                  Text(
                    _parseError!,
                    style: const TextStyle(color: AppColors.error),
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
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
