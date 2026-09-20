import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/cameroon.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../models/map_style.dart';
import '../../providers/location_providers.dart';
import '../../services/admin_repository.dart';
import 'admin_widgets.dart';

class AdminPharmacyMapPage extends ConsumerStatefulWidget {
  const AdminPharmacyMapPage({super.key});

  @override
  ConsumerState<AdminPharmacyMapPage> createState() =>
      _AdminPharmacyMapPageState();
}

class _AdminPharmacyMapPageState extends ConsumerState<AdminPharmacyMapPage> {
  final _mapController = MapController();
  List<Map<String, dynamic>> _pharmacies = [];
  bool _loading = true;
  String? _error;
  String? _selectedId;
  bool _pickMode = false;
  bool _saving = false;
  bool _followAdmin = true;
  LatLng? _lastAdminPos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    try {
      _mapController.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminRepository.instance.listPharmacies(
        page: 1,
        pageSize: 200,
      );
      final items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _pharmacies = items;
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

  LatLng? _latLngOf(Map<String, dynamic> p) {
    final lat = (p['latitude'] as num?)?.toDouble();
    final lng = (p['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  void _onAdminLocation(LatLng? pos) {
    if (pos == null) return;
    final prev = _lastAdminPos;
    _lastAdminPos = pos;
    if (!_followAdmin) return;
    if (prev != null) {
      final moved = (prev.latitude - pos.latitude).abs() +
          (prev.longitude - pos.longitude).abs();
      if (moved < 0.00008) return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(pos, _mapController.camera.zoom);
      } catch (_) {}
    });
  }

  Future<void> _confirmAddAtCenter() async {
    final center = _mapController.camera.center;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MapPharmacyFormDialog(
        latitude: center.latitude,
        longitude: center.longitude,
      ),
    );
    if (saved == true) {
      setState(() => _pickMode = false);
      await _load();
    }
  }

  Future<void> _updateSelectedLocation(LatLng pos) async {
    final id = _selectedId;
    if (id == null) return;
    final ok = await confirmAdminAction(
      context,
      title: 'Mettre à jour la position',
      message:
          'Déplacer la pharmacie sélectionnée vers ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} ?',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.updatePharmacyLocation(
        id,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position mise à jour')),
        );
      }
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
    ref.listen<AsyncValue<LatLng?>>(liveLocationProvider, (prev, next) {
      next.whenData(_onAdminLocation);
    });
    final adminLoc = ref.watch(liveLocationProvider);
    final adminPos = adminLoc.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: Responsive.isDesktop(context)
          ? AppBar(
              backgroundColor: AppColors.background,
              title: Text(
                'Carte des pharmacies',
                style: AppTypography.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              actions: [
                if (_pickMode)
                  TextButton(
                    onPressed: () => setState(() => _pickMode = false),
                    child: const Text('Annuler'),
                  ),
                IconButton(
                  tooltip: _followAdmin
                      ? 'Suivi GPS admin activé'
                      : 'Centrer sur ma position',
                  onPressed: () {
                    setState(() => _followAdmin = !_followAdmin);
                    if (_followAdmin && adminPos != null) {
                      _mapController.move(adminPos, 15);
                    }
                  },
                  icon: Icon(
                    _followAdmin
                        ? Icons.my_location_rounded
                        : Icons.location_searching_rounded,
                    color: _followAdmin ? AppColors.primaryBlue : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'admin_gps',
            tooltip: 'Ma position (admin)',
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primaryBlue,
            onPressed: () {
              final pos = adminPos ?? _lastAdminPos;
              if (pos == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Position admin indisponible'),
                  ),
                );
                return;
              }
              setState(() => _followAdmin = true);
              _mapController.move(pos, 15);
            },
            child: const Icon(Icons.gps_fixed_rounded),
          ),
          const SizedBox(height: 10),
          if (_pickMode) ...[
            FloatingActionButton.extended(
              heroTag: 'cancel_pick',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              onPressed: () => setState(() => _pickMode = false),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Annuler'),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'confirm_pos',
              onPressed: _saving ? null : _confirmAddAtCenter,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirmer la position'),
            ),
          ] else
            FloatingActionButton.extended(
              heroTag: 'add_pharm',
              onPressed: () => setState(() => _pickMode = true),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Ajouter'),
            ),
        ],
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
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: adminPos ?? CameroonDefaults.douala,
                        initialZoom: adminPos != null ? 14 : 12,
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture && _followAdmin) {
                            setState(() => _followAdmin = false);
                          }
                        },
                        onLongPress: (tap, latLng) {
                          if (_selectedId != null) {
                            _updateSelectedLocation(latLng);
                          }
                        },
                        onTap: (tap, latLng) {
                          if (_pickMode) return;
                          setState(() => _selectedId = null);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: MapBaseStyle.streets.urlTemplate,
                          userAgentPackageName: 'com.instapharm.app',
                          maxNativeZoom: MapBaseStyle.streets.maxNativeZoom,
                        ),
                        MarkerLayer(
                          markers: [
                            if (adminPos != null)
                              Marker(
                                point: adminPos,
                                width: 52,
                                height: 52,
                                child: const _AdminLiveMarker(),
                              ),
                            for (final p in _pharmacies)
                              if (_latLngOf(p) != null)
                                Marker(
                                  point: _latLngOf(p)!,
                                  width: 44,
                                  height: 44,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(
                                        () => _selectedId = p['id']?.toString(),
                                      );
                                    },
                                    onLongPress: () {
                                      setState(
                                        () => _selectedId = p['id']?.toString(),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Appui long sur la carte pour déplacer',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Icon(
                                      Icons.location_on_rounded,
                                      size: 40,
                                      color: _selectedId == p['id']?.toString()
                                          ? AppColors.accentOrange
                                          : AppColors.primaryBlue,
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.surface.withValues(alpha: 0.95),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                adminPos != null
                                    ? Icons.radar_rounded
                                    : Icons.location_disabled_rounded,
                                color: adminPos != null
                                    ? AppColors.accentGreen
                                    : AppColors.accentOrange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  adminPos != null
                                      ? 'Votre position admin en direct'
                                          '${_followAdmin ? ' · suivi actif' : ''}'
                                      : (adminLoc.isLoading
                                          ? 'Localisation admin…'
                                          : 'GPS admin indisponible'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (adminPos != null)
                                Text(
                                  '${adminPos.latitude.toStringAsFixed(4)}, '
                                  '${adminPos.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_pickMode)
                      IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.add_location_alt_rounded,
                            size: 48,
                            color: AppColors.error.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    if (_selectedId != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 88,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(14),
                          color: AppColors.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Builder(
                              builder: (_) {
                                final p = _pharmacies.firstWhere(
                                  (e) => e['id']?.toString() == _selectedId,
                                  orElse: () => <String, dynamic>{},
                                );
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      p['name']?.toString() ?? 'Pharmacie',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      [
                                        p['city'],
                                        p['address'],
                                      ]
                                          .where((e) =>
                                              e != null &&
                                              e.toString().isNotEmpty)
                                          .join(' · '),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Appui long sur la carte pour déplacer le marqueur',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _AdminLiveMarker extends StatelessWidget {
  const _AdminLiveMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentGreen.withValues(alpha: 0.22),
          ),
        ),
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentGreen,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentGreen.withValues(alpha: 0.4),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapPharmacyFormDialog extends StatefulWidget {
  final double latitude;
  final double longitude;

  const _MapPharmacyFormDialog({
    required this.latitude,
    required this.longitude,
  });

  @override
  State<_MapPharmacyFormDialog> createState() => _MapPharmacyFormDialogState();
}

class _MapPharmacyFormDialogState extends State<_MapPharmacyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController(text: 'Douala');
  final _address = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminRepository.instance.upsertPharmacy({
        'name': _name.text.trim(),
        'city': _city.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'latitude': widget.latitude,
        'longitude': widget.longitude,
        'platform_status': 'VERIFIED',
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
      title: const Text('Nouvelle pharmacie'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Position : ${widget.latitude.toStringAsFixed(5)}, '
                  '${widget.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Requis' : null,
                ),
                TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'Ville'),
                ),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
              ],
            ),
          ),
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
