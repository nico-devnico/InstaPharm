import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/responsive.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_repository.dart';
import '../profile_screen.dart';
import 'admin_approvals_page.dart';
import 'admin_audit_page.dart';
import 'admin_couriers_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_medicines_page.dart';
import 'admin_orders_page.dart';
import 'admin_pharmacies_page.dart';
import 'admin_pharmacy_map_page.dart';
import 'admin_reports_page.dart';
import 'admin_settings_page.dart';
import 'admin_stocks_page.dart';
import 'admin_users_page.dart';

enum AdminSection {
  dashboard,
  approvals,
  users,
  pharmacies,
  map,
  medicines,
  stocks,
  orders,
  deliveries,
  couriers,
  reports,
  settings,
  audit,
  profile,
}

extension AdminSectionX on AdminSection {
  String get label {
    switch (this) {
      case AdminSection.dashboard:
        return 'Tableau de bord';
      case AdminSection.approvals:
        return 'Validations';
      case AdminSection.users:
        return 'Utilisateurs';
      case AdminSection.pharmacies:
        return 'Pharmacies';
      case AdminSection.map:
        return 'Carte';
      case AdminSection.medicines:
        return 'Médicaments';
      case AdminSection.stocks:
        return 'Stocks';
      case AdminSection.orders:
        return 'Commandes';
      case AdminSection.deliveries:
        return 'Livraisons';
      case AdminSection.couriers:
        return 'Livreurs';
      case AdminSection.reports:
        return 'Signalements';
      case AdminSection.settings:
        return 'Paramètres';
      case AdminSection.audit:
        return 'Audit';
      case AdminSection.profile:
        return 'Profil';
    }
  }

  IconData get icon {
    switch (this) {
      case AdminSection.dashboard:
        return Icons.dashboard_outlined;
      case AdminSection.approvals:
        return Icons.verified_user_outlined;
      case AdminSection.users:
        return Icons.people_outline;
      case AdminSection.pharmacies:
        return Icons.local_pharmacy_outlined;
      case AdminSection.map:
        return Icons.map_outlined;
      case AdminSection.medicines:
        return Icons.medication_outlined;
      case AdminSection.stocks:
        return Icons.inventory_2_outlined;
      case AdminSection.orders:
        return Icons.receipt_long_outlined;
      case AdminSection.deliveries:
        return Icons.local_shipping_outlined;
      case AdminSection.couriers:
        return Icons.delivery_dining_outlined;
      case AdminSection.reports:
        return Icons.flag_outlined;
      case AdminSection.settings:
        return Icons.settings_outlined;
      case AdminSection.audit:
        return Icons.history_outlined;
      case AdminSection.profile:
        return Icons.person_outline;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case AdminSection.dashboard:
        return Icons.dashboard_rounded;
      case AdminSection.approvals:
        return Icons.verified_user_rounded;
      case AdminSection.users:
        return Icons.people_rounded;
      case AdminSection.pharmacies:
        return Icons.local_pharmacy_rounded;
      case AdminSection.map:
        return Icons.map_rounded;
      case AdminSection.medicines:
        return Icons.medication_rounded;
      case AdminSection.stocks:
        return Icons.inventory_2_rounded;
      case AdminSection.orders:
        return Icons.receipt_long_rounded;
      case AdminSection.deliveries:
        return Icons.local_shipping_rounded;
      case AdminSection.couriers:
        return Icons.delivery_dining_rounded;
      case AdminSection.reports:
        return Icons.flag_rounded;
      case AdminSection.settings:
        return Icons.settings_rounded;
      case AdminSection.audit:
        return Icons.history_rounded;
      case AdminSection.profile:
        return Icons.person_rounded;
    }
  }
}

/// Espace administrateur Instapharm — navigation responsive.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  AdminSection _section = AdminSection.dashboard;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _claiming = false;

  static const _sections = AdminSection.values;

  Widget _pageFor(AdminSection s) {
    switch (s) {
      case AdminSection.dashboard:
        return const AdminDashboardPage();
      case AdminSection.approvals:
        return const AdminApprovalsPage();
      case AdminSection.users:
        return const AdminUsersPage();
      case AdminSection.pharmacies:
        return const AdminPharmaciesPage();
      case AdminSection.map:
        return const AdminPharmacyMapPage();
      case AdminSection.medicines:
        return const AdminMedicinesPage();
      case AdminSection.stocks:
        return const AdminStocksPage();
      case AdminSection.orders:
        return const AdminOrdersPage();
      case AdminSection.deliveries:
        return const AdminOrdersPage(deliveriesOnly: true);
      case AdminSection.couriers:
        return const AdminCouriersPage();
      case AdminSection.reports:
        return const AdminReportsPage();
      case AdminSection.settings:
        return const AdminSettingsPage();
      case AdminSection.audit:
        return const AdminAuditPage();
      case AdminSection.profile:
        return const ProfileScreen();
    }
  }

  void _select(AdminSection s) {
    setState(() => _section = s);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _claimBootstrap() async {
    setState(() => _claiming = true);
    try {
      final result = await AdminRepository.instance.claimBootstrap();
      if (result['ok'] != true) {
        final err = result['error']?.toString() ?? 'Échec';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              err == 'ADMIN_EXISTS'
                  ? 'Un administrateur existe déjà. Demandez une promotion.'
                  : 'Impossible : $err',
            ),
          ),
        );
        return;
      }
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous êtes maintenant administrateur.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Impossible de charger le profil.\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null || !profile.isAdmin) {
          return _BootstrapGate(
            claiming: _claiming,
            onClaim: _claimBootstrap,
          );
        }
        return _AdminLayout(
          scaffoldKey: _scaffoldKey,
          section: _section,
          sections: _sections,
          onSelect: _select,
          pageBuilder: _pageFor,
        );
      },
    );
  }
}

class _BootstrapGate extends StatelessWidget {
  final bool claiming;
  final VoidCallback onClaim;

  const _BootstrapGate({required this.claiming, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 56,
                  color: AppColors.primaryBlue.withValues(alpha: 0.8),
                ),
                const SizedBox(height: 16),
                Text(
                  'Accès administrateur',
                  style: AppTypography.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Votre compte n’a pas encore le rôle admin. '
                  'Si aucun administrateur n’existe, vous pouvez revendiquer '
                  'le premier accès.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: claiming ? null : onClaim,
                  icon: claiming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_rounded),
                  label: Text(
                    claiming ? 'Activation…' : 'Devenir administrateur',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLayout extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final AdminSection section;
  final List<AdminSection> sections;
  final ValueChanged<AdminSection> onSelect;
  final Widget Function(AdminSection) pageBuilder;

  const _AdminLayout({
    required this.scaffoldKey,
    required this.section,
    required this.sections,
    required this.onSelect,
    required this.pageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    final pages = sections.map(pageBuilder).toList();
    final index = sections.indexOf(section);

    if (desktop) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            _Sidebar(
              section: section,
              sections: sections,
              onSelect: onSelect,
            ),
            Expanded(
              child: IndexedStack(index: index, children: pages),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          section.label,
          style: AppTypography.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: NavigationDrawer(
        selectedIndex: index,
        onDestinationSelected: (i) => onSelect(sections[i]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
            child: Text(
              'Instapharm Admin',
              style: AppTypography.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          ...sections.map(
            (s) => NavigationDrawerDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.selectedIcon),
              label: Text(s.label),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final AdminSection section;
  final List<AdminSection> sections;
  final ValueChanged<AdminSection> onSelect;

  const _Sidebar({
    required this.section,
    required this.sections,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instapharm',
                  style: AppTypography.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const Text(
                  'Administration',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: [
                for (final s in sections)
                  _NavTile(
                    label: s.label,
                    icon: section == s ? s.selectedIcon : s.icon,
                    selected: section == s,
                    onTap: () => onSelect(s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? AppColors.primaryBlue.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.primaryBlue
                          : AppColors.textPrimary,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
