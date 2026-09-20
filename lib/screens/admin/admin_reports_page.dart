import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});

  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
  String? _status;
  int _page = 1;
  final _pageSize = 20;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _total = 0;

  static const _statuses = <String?, String>{
    null: 'Tous',
    'OPEN': 'OPEN',
    'IN_PROGRESS': 'IN_PROGRESS',
    'RESOLVED': 'RESOLVED',
    'CLOSED': 'CLOSED',
  };

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
      final data = await AdminRepository.instance.listReports(
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

  Future<void> _edit(Map<String, dynamic> report) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReportEditDialog(report: report),
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
                'Signalements',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Column(
        children: [
          SizedBox(
            height: 40,
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
                        ? const AdminEmptyState(message: 'Aucun signalement')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final r = _items[i];
                                final profile = r['profiles'];
                                final author = profile is Map
                                    ? profile['full_name']?.toString() ??
                                        profile['email']?.toString()
                                    : null;
                                final st = r['status']?.toString() ?? 'OPEN';
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: ListTile(
                                    onTap: () => _edit(r),
                                    title: Text(
                                      r['reason']?.toString() ??
                                          r['title']?.toString() ??
                                          'Signalement',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      [
                                        author,
                                        r['description']?.toString(),
                                      ]
                                          .where((e) =>
                                              e != null &&
                                              e.toString().isNotEmpty)
                                          .join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: AdminStatusBadge(
                                      label: st,
                                      color: reportStatusColor(st),
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

class _ReportEditDialog extends StatefulWidget {
  final Map<String, dynamic> report;
  const _ReportEditDialog({required this.report});

  @override
  State<_ReportEditDialog> createState() => _ReportEditDialogState();
}

class _ReportEditDialogState extends State<_ReportEditDialog> {
  late String _status;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.report['status']?.toString() ?? 'OPEN';
    _notes = TextEditingController(
      text: widget.report['admin_notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.updateReport(
        widget.report['id'].toString(),
        status: _status,
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Traiter le signalement'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.report['description']?.toString() ?? '',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: const [
                DropdownMenuItem(value: 'OPEN', child: Text('OPEN')),
                DropdownMenuItem(
                  value: 'IN_PROGRESS',
                  child: Text('IN_PROGRESS'),
                ),
                DropdownMenuItem(value: 'RESOLVED', child: Text('RESOLVED')),
                DropdownMenuItem(value: 'CLOSED', child: Text('CLOSED')),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes admin',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
        ),
      ],
    );
  }
}
