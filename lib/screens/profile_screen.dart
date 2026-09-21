import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/verification_docs_service.dart';
import '../widgets/document_drop_button.dart';
import 'history_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final user = ref.watch(currentUserProvider);
    final profile = profileAsync.valueOrNull;
    final authenticated = user != null;
    final notif = ref.watch(notificationsEnabledProvider);

    final displayName = profile?.fullName?.isNotEmpty == true
        ? profile!.fullName!
        : (user?.email ?? 'Invité');
    final subtitle = authenticated
        ? [
            if (user.email != null) user.email!,
            if (profile?.phone != null && profile!.phone!.isNotEmpty)
              profile.phone!,
          ].join(' · ')
        : 'Connectez-vous pour synchroniser vos données';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(
          'Profil',
          style: AppTypography.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _UserCard(
            authenticated: authenticated,
            displayName: displayName,
            subtitle: subtitle,
          ),
          if (authenticated) ...[
            const SizedBox(height: 16),
            const _IdentityDocsSection(),
          ],
          const SizedBox(height: 20),
          _sectionTitle('Préférences'),
          const SizedBox(height: 10),
          _section(
            children: [
              _tile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: notif
                    ? 'Alertes de disponibilité activées'
                    : 'Notifications désactivées',
                trailing: Switch(
                  value: notif,
                  onChanged: (v) => ref
                      .read(notificationsEnabledProvider.notifier)
                      .setEnabled(v),
                ),
              ),
              _divider(),
              _tile(
                icon: Icons.my_location_rounded,
                title: 'Localisation',
                subtitle: 'Utilisée pour trouver les pharmacies près de vous',
                trailing: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.accentGreen,
                ),
              ),
              _divider(),
              _tile(
                icon: Icons.public_rounded,
                title: 'Pays / devise',
                subtitle: 'Cameroun · FCFA',
                trailing: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.accentGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('Compte'),
          const SizedBox(height: 10),
          _section(
            children: [
              if (authenticated) ...[
                _tile(
                  icon: Icons.person_outline_rounded,
                  title: 'Mon compte',
                  subtitle: user.email,
                  trailing: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.accentGreen,
                  ),
                ),
                _divider(),
                _tile(
                  icon: Icons.logout_rounded,
                  title: 'Se déconnecter',
                  titleColor: AppColors.error,
                  onTap: () async {
                    await AuthService.instance.signOut();
                    ref.invalidate(profileProvider);
                  },
                ),
                _divider(),
                _tile(
                  icon: Icons.delete_forever_rounded,
                  title: 'Supprimer mon compte',
                  subtitle: 'Efface définitivement vos données',
                  titleColor: AppColors.error,
                  onTap: () => _confirmDeleteAccount(context, ref),
                ),
              ] else
                _tile(
                  icon: Icons.login_rounded,
                  title: 'Se connecter',
                  subtitle: 'Accédez à vos commandes et favoris',
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle('Activité'),
          const SizedBox(height: 10),
          _section(
            children: [
              _tile(
                icon: Icons.history_rounded,
                title: 'Historique',
                subtitle: 'Recherches et pharmacies consultées',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HistoryScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'InstaPharm',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer mon compte'),
      content: const Text(
        'Cette action est définitive : votre profil et vos données liées '
        'seront effacés. Continuer ?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await AuthService.instance.deleteMyAccount();
    ref.invalidate(profileProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte supprimé')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

class _UserCard extends StatelessWidget {
  final bool authenticated;
  final String displayName;
  final String subtitle;

  const _UserCard({
    required this.authenticated,
    required this.displayName,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.10),
            AppColors.accentGreen.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                authenticated
                    ? Icons.person_rounded
                    : Icons.person_outline_rounded,
                size: 32,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTypography.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      title,
      style: AppTypography.textTheme.labelLarge?.copyWith(
        color: AppColors.textTertiary,
        letterSpacing: 0.6,
      ),
    ),
  );
}

Widget _section({required List<Widget> children}) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

Widget _divider() => const Divider(height: 1, indent: 56);

Widget _tile({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  Color? titleColor,
  VoidCallback? onTap,
}) {
  return ListTile(
    onTap: onTap,
    leading: Icon(icon, color: AppColors.primaryBlue),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: titleColor ?? AppColors.textPrimary,
      ),
    ),
    subtitle: subtitle != null
        ? Text(subtitle, style: const TextStyle(color: AppColors.textSecondary))
        : null,
    trailing: trailing,
  );
}

/// Dépôt des pièces d’identité pour validation admin (pharmacien / livreur).
class _IdentityDocsSection extends StatefulWidget {
  const _IdentityDocsSection();

  @override
  State<_IdentityDocsSection> createState() => _IdentityDocsSectionState();
}

class _IdentityDocsSectionState extends State<_IdentityDocsSection> {
  Map<String, dynamic>? _app;
  bool _loading = true;
  bool _uploadingId = false;
  bool _uploadingPro = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final app =
          await VerificationDocsService.instance.myLatestApplication();
      if (!mounted) return;
      setState(() {
        _app = app;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _app = null;
        _loading = false;
      });
    }
  }

  Future<void> _upload({required bool isId}) async {
    final uid = SupabaseService.client.auth.currentUser?.id;
    final appId = _app?['id']?.toString();
    if (uid == null || appId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune demande en cours. Inscrivez-vous comme pharmacien ou livreur.',
          ),
        ),
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
      final url = await pickAndUploadVerificationDoc(context, folder: uid);
      if (url == null) return;
      await VerificationDocsService.instance.attachToApplication(
        applicationId: appId,
        idDocumentUrl: isId ? url : (_app?['id_document_url']?.toString()),
        professionalDocumentUrl: isId
            ? (_app?['professional_document_url']?.toString())
            : url,
      );
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _uploadingId = false;
          _uploadingPro = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_app == null) return const SizedBox.shrink();

    final status = _app!['status']?.toString() ?? 'PENDING';
    final idUrl = _app!['id_document_url']?.toString();
    final proUrl = _app!['professional_document_url']?.toString();
    final role = _app!['role_requested']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Documents d’identité',
          style: AppTypography.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status == 'APPROVED'
              ? 'Compte validé.'
              : 'Déposez vos pièces pour que l’admin puisse vous approuver '
                  '(${role == 'pharmacist' ? 'pharmacien' : 'livreur'} · $status).',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        DocumentDropButton(
          title: 'Pièce d’identité',
          subtitle: 'CNI, passeport… (JPG, PNG ou PDF)',
          uploading: _uploadingId,
          done: idUrl != null && idUrl.isNotEmpty,
          onPressed: status == 'APPROVED' ? null : () => _upload(isId: true),
        ),
        const SizedBox(height: 10),
        DocumentDropButton(
          title: 'Document professionnel',
          subtitle: role == 'pharmacist'
              ? 'Agrément / licence pharmacie'
              : 'Permis / attestation livreur',
          uploading: _uploadingPro,
          done: proUrl != null && proUrl.isNotEmpty,
          onPressed: status == 'APPROVED' ? null : () => _upload(isId: false),
        ),
      ],
    );
  }
}

