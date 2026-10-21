import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/core/i18n/app_strings.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// Navigation item descriptor for the primary shell sidebar.
class _NavDestination {
  const _NavDestination({
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

/// Adaptive navigation shell providing a sidebar on TV/Desktop and bottom bar on mobile.
///
/// **What**: Hosts top-level routes (Home, CCTV, Live, Search, Settings) within a persistent
/// navigation frame, preserving state across sub-routes.
///
/// **Why**: On 10-foot TV displays, persistent vertical sidebars allow D-Pad focus
/// to easily transition between the main content grid and navigation menus.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
  });

  final Widget child;

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(
      labelKey: 'nav_home',
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie,
      path: '/',
    ),
    _NavDestination(
      labelKey: 'nav_cctv',
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance,
      path: '/cctv',
    ),
    _NavDestination(
      labelKey: 'nav_live',
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
      path: '/live',
    ),
    _NavDestination(
      labelKey: 'nav_nas',
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage,
      path: '/nas',
    ),
    _NavDestination(
      labelKey: 'nav_search',
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      path: '/search',
    ),
    _NavDestination(
      labelKey: 'nav_settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      path: '/settings',
    ),
  ];

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location == '/cctv') return 1;
    if (location == '/live') return 2;
    if (location == '/nas') return 3;
    if (location == '/search') return 4;
    if (location == '/settings') return 5;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      backgroundColor: colors.backgroundDeep,
      body: Row(
        children: <Widget>[
          // Left TV / Desktop Persistent Navigation Sidebar
          Container(
            width: 80,
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              border: Border(
                right: BorderSide(
                  color: colors.surfaceElevation,
                ),
              ),
            ),
            child: Column(
              children: <Widget>[
                const SizedBox(height: 24),
                // App Logo Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.brandPrimary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.focusGlow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '聚',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Navigation Items
                Expanded(
                  child: ListView.separated(
                    itemCount: _destinations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _destinations[index];
                      final isSelected = selectedIndex == index;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: TvFocusWrapper(
                          onTap: () => context.go(item.path),
                          child: Container(
                            height: 60,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.brandPrimary.withAlpha(40)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? colors.brandPrimary
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  color: isSelected
                                      ? colors.focusBorder
                                      : colors.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  context.tr(item.labelKey),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSelected
                                        ? colors.textPrimary
                                        : colors.textTertiary,
                                    fontSize: 10,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Main Screen Content Area
          Expanded(child: child),
        ],
      ),
    );
  }
}
