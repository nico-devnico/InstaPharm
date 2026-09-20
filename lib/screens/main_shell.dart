import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'orders_screen.dart';
import 'favorites_screen.dart';
import 'profile_screen.dart';

final shellIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _navItems = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Accueil'),
    (icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: 'Recherche'),
    (icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping_rounded, label: 'Commandes'),
    (icon: Icons.favorite_border_rounded, activeIcon: Icons.favorite_rounded, label: 'Favoris'),
    (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profil'),
  ];

  /// Onglets déjà visités — n’instancie Search/Orders/etc. qu’au premier accès.
  final _built = <int>{0};

  Widget _screenAt(int i) {
    switch (i) {
      case 0:
        return const HomeScreen();
      case 1:
        return const SearchScreen();
      case 2:
        return const OrdersScreen();
      case 3:
        return const FavoritesScreen();
      default:
        return const ProfileScreen();
    }
  }

  Widget _lazyBody(int index) {
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < 5; i++)
          _built.contains(i) ? _screenAt(i) : const SizedBox.shrink(),
      ],
    );
  }

  void _select(int i) {
    if (!_built.contains(i)) setState(() => _built.add(i));
    ref.read(shellIndexProvider.notifier).state = i;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellIndexProvider);
    final wide = Responsive.isWide(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _select,
              extended: Responsive.isDesktop(context) ||
                  (kIsWeb && Responsive.width(context) >= 900),
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.primaryBlue.withValues(alpha: 0.12),
              selectedIconTheme: const IconThemeData(
                color: AppColors.primaryBlue,
              ),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.textTertiary,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w700,
              ),
              destinations: [
                for (final item in _navItems)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.activeIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: _lazyBody(index)),
          ],
        ),
      );
    }

    return Scaffold(
      body: _lazyBody(index),
      bottomNavigationBar: _ModernNavBar(
        index: index,
        navItems: _navItems,
        isSmall: Responsive.isSmall(context),
        onTap: _select,
      ),
    );
  }
}

class _ModernNavBar extends StatelessWidget {
  final int index;
  final List<({IconData icon, IconData activeIcon, String label})> navItems;
  final bool isSmall;
  final ValueChanged<int> onTap;

  const _ModernNavBar({
    required this.index,
    required this.navItems,
    required this.isSmall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.navShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 4 : 8,
            vertical: isSmall ? 6 : 8,
          ),
          child: Row(
            children: [
              for (var i = 0; i < navItems.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: navItems[i].icon,
                    activeIcon: navItems[i].activeIcon,
                    label: navItems[i].label,
                    isActive: i == index,
                    isSmall: isSmall,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool isSmall;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.isSmall,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = isSmall ? 20.0 : 22.0;
    final fontSize = isSmall ? 9.5 : 10.5;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isActive ? (isSmall ? 12 : 16) : (isSmall ? 8 : 10),
              vertical: isActive ? 7 : 5,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primaryBlue.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isActive ? activeIcon : icon,
              size: iconSize,
              color: isActive ? AppColors.primaryBlue : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? AppColors.primaryBlue : AppColors.textTertiary,
              letterSpacing: 0.1,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
