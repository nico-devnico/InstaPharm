import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import '../../services/supabase_service.dart';
import '../../widgets/document_drop_button.dart';
import 'admin_widgets.dart';

/// Demandes d’inscription pharmacien / livreur à valider.
class AdminApprovalsPage extends ConsumerStatefulWidget {
  const AdminApprovalsPage({super.key});

  @override
  ConsumerState<AdminApprovalsPage> createState() => _AdminApprovalsPageState();
}

class _AdminApprovalsPageState extends ConsumerState<AdminApprovalsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String? _status = 'PENDING';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AdminRepository.instance.listApplications(
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  bool _hasDocs(Map<String, dynamic> app) {
    final idUrl = app['id_document_url']?.toString();
    final proUrl = app['professional_document_url']?.toString();
    return idUrl != null &&
        idUrl.isNotEmpty &&
        proUrl != null &&
        proUrl.isNotEmpty;
  }

  Future<void> _openReview(Map<String, dynamic> app) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApplicationReviewDialog(application: app),
    );
    if (changed == true) _load();
  }

  Future<void> _quickReject(Map<String, dynamic> app) async {
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeter'),
        content: TextField(
          controller: notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif',
            hintText: 'Documents incomplets, informations incorrectes…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminRepository.instance.reviewApplication(
        app['id'].toString(),
        status: 'REJECTED',
        adminNotes: notesCtrl.text.trim(),
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
                'Validations comptes',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
            child: const Text(
              'Avant d’approuver : demandez et déposez la pièce d’identité '
              '(image/PDF) et le document professionnel.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              children: [
                for (final e in {
                  'PENDING': 'En attente',
                  'NEEDS_INFO': 'Infos requises',
                  'APPROVED': 'Approuvées',
                  'REJECTED': 'Rejetées',
                  null: 'Toutes',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) {
                        setState(() => _status = e.key);
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
                        ? const AdminEmptyState(
                            message: 'Aucune demande',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final a = _items[i];
                                final role =
                                    a['role_requested']?.toString() ?? '';
                                final docsOk = _hasDocs(a);
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                a['full_name']?.toString() ??
                                                    '—',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            AdminStatusBadge(
                                              label: docsOk
                                                  ? 'Docs OK'
                                                  : 'Docs manquants',
                                              color: docsOk
                                                  ? AppColors.accentGreen
                                                  : AppColors.accentOrange,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            role == 'pharmacist'
                                                ? 'Pharmacien'
                                                : 'Livreur',
                                            a['email'],
                                            a['phone'],
                                            a['business_name'],
                                            a['business_city'],
                                            if (a['license_number'] != null)
                                              'N°: ${a['license_number']}',
                                          ]
                                              .where((e) =>
                                                  e != null &&
                                                  e.toString().isNotEmpty)
                                              .join(' · '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        if (a['notes'] != null) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            a['notes'].toString(),
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.icon(
                                              onPressed: () => _openReview(a),
                                              icon: const Icon(
                                                Icons.folder_open_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                docsOk
                                                    ? 'Examiner / Approuver'
                                                    : 'Demander documents',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _quickReject(a),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.error,
                                              ),
                                              child: const Text('Rejeter'),
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
        ],
      ),
    );
  }
}

class _ApplicationReviewDialog extends StatefulWidget {
  final Map<String, dynamic> application;

  const _ApplicationReviewDialog({required this.application});

  @override
  State<_ApplicationReviewDialog> createState() =>
      _ApplicationReviewDialogState();
}

class _ApplicationReviewDialogState extends State<_ApplicationReviewDialog> {
  late final TextEditingController _license;
  late final TextEditingController _notes;
  late final TextEditingController _extraInfo;
  String? _idUrl;
  String? _proUrl;
  String? _idName;
  String? _proName;
  bool _uploadingId = false;
  bool _uploadingPro = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.application;
    _license = TextEditingController(
      text: a['license_number']?.toString() ?? '',
    );
    _notes = TextEditingController(text: a['admin_notes']?.toString() ?? '');
    _extraInfo = TextEditingController(text: a['notes']?.toString() ?? '');
    _idUrl = a['id_document_url']?.toString();
    _proUrl = a['professional_document_url']?.toString();
  }

  @override
  void dispose() {
    _license.dispose();
    _notes.dispose();
    _extraInfo.dispose();
    super.dispose();
  }

  bool get _canApprove =>
      (_idUrl != null && _idUrl!.isNotEmpty) &&
      (_proUrl != null && _proUrl!.isNotEmpty);

  Future<void> _pickAndUpload({required bool isId}) async {
    final uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session admin requise')),
      );
      return;
    }

    setState(() {
      if (isId) {
        _uploadingId = true;
      } else {
        _uploadingPro = true;
      }
    });

    try {
      final url = await pickAndUploadVerificationDoc(
        context,
        folder: uid,
      );
      if (url == null) return;

      if (isId) {
        _idUrl = url;
        _idName = 'Pièce d’identité';
      } else {
        _proUrl = url;
        _proName = 'Document professionnel';
      }

      await AdminRepository.instance.attachApplicationDocuments(
        widget.application['id'].toString(),
        idDocumentUrl: _idUrl,
        professionalDocumentUrl: _proUrl,
        licenseNumber: _license.text.trim().isEmpty
            ? null
            : _license.text.trim(),
        adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        extraInfo: {'notes': _extraInfo.text.trim()},
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingId = false;
          _uploadingPro = false;
        });
      }
    }
  }

  Future<void> _saveInfoOnly() async {
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.attachApplicationDocuments(
        widget.application['id'].toString(),
        idDocumentUrl: _idUrl,
        professionalDocumentUrl: _proUrl,
        licenseNumber:
            _license.text.trim().isEmpty ? null : _license.text.trim(),
        adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        extraInfo: {'notes': _extraInfo.text.trim()},
      );
      await AdminRepository.instance.reviewApplication(
        widget.application['id'].toString(),
        status: 'NEEDS_INFO',
        adminNotes: _notes.text.trim().isEmpty
            ? 'Documents / infos complémentaires demandés'
            : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
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

  Future<void> _approve() async {
    if (!_canApprove) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Déposez la pièce d’identité et le document professionnel '
            'avant d’approuver.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.attachApplicationDocuments(
        widget.application['id'].toString(),
        idDocumentUrl: _idUrl,
        professionalDocumentUrl: _proUrl,
        licenseNumber:
            _license.text.trim().isEmpty ? null : _license.text.trim(),
        adminNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        extraInfo: {'notes': _extraInfo.text.trim()},
      );
      await AdminRepository.instance.reviewApplication(
        widget.application['id'].toString(),
        status: 'APPROVED',
        adminNotes: _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
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

  Widget _dropZone({
    required String title,
    required String subtitle,
    required bool uploading,
    required String? url,
    required String? fileName,
    required VoidCallback onTap,
  }) {
    return DocumentDropButton(
      title: title,
      subtitle: subtitle,
      uploading: uploading,
      done: url != null && url.isNotEmpty,
      fileLabel: fileName,
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.application;
    final role = a['role_requested']?.toString() ?? '';
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return AlertDialog(
      title: Text(
        role == 'pharmacist'
            ? 'Validation pharmacien'
            : 'Validation livreur',
      ),
      content: SizedBox(
        width: 480,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a['full_name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    a['email'],
                    a['phone'],
                    a['business_name'],
                    a['business_city'],
                  ]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pièces justificatives (obligatoires pour approuver)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _dropZone(
                  title: 'Pièce d’identité',
                  subtitle: 'CNI, passeport… (JPG, PNG ou PDF)',
                  uploading: _uploadingId,
                  url: _idUrl,
                  fileName: _idName,
                  onTap: () => _pickAndUpload(isId: true),
                ),
                const SizedBox(height: 10),
                _dropZone(
                  title: 'Document professionnel',
                  subtitle: role == 'pharmacist'
                      ? 'Agrément / licence pharmacie (JPG, PNG ou PDF)'
                      : 'Permis / attestation livreur (JPG, PNG ou PDF)',
                  uploading: _uploadingPro,
                  url: _proUrl,
                  fileName: _proName,
                  onTap: () => _pickAndUpload(isId: false),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _license,
                  decoration: const InputDecoration(
                    labelText: 'N° licence / document',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _extraInfo,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Informations complémentaires',
                    hintText: 'Adresse, véhicule, horaires…',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes admin',
                    filled: true,
                  ),
                ),
                if (!_canApprove) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Déposez les 2 documents avant de pouvoir approuver.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentOrange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Fermer'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _saveInfoOnly,
          child: const Text('Demander infos'),
        ),
        FilledButton(
          onPressed: _busy || !_canApprove ? null : _approve,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approuver'),
        ),
      ],
    );
  }
}
