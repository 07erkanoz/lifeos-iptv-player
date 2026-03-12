import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/widgets/layout/desktop_title_bar.dart';
import 'package:lifeostv/presentation/widgets/layout/sidebar.dart';
import 'package:lifeostv/utils/platform_utils.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<AppSidebarState> _sidebarKey = GlobalKey<AppSidebarState>();
  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    final canSystemPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: canSystemPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: isDesktopPlatform ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

  // ===========================================================================
  //  Desktop layout: sidebar + content (+ floating PiP on Windows/macOS)
  // ===========================================================================

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          Column(
            children: [
              const DesktopTitleBar(),
              Expanded(
                child: Row(
                  children: [
                    AppSidebar(
                      key: _sidebarKey,
                      navigationShell: widget.navigationShell,
                    ),
                    Expanded(child: widget.navigationShell),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  //  Mobile layout: content + bottom navigation bar
  // ===========================================================================

  Widget _buildMobileLayout() {
    final l10n = AppLocalizations.of(context)!;
    final currentIndex = widget.navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(child: widget.navigationShell),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.sidebarBgDark,
          border: Border(
            top: BorderSide(color: AppColors.sidebarBorderDark, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _MobileNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: l10n.home,
                  isSelected: currentIndex == 0,
                  onTap: () => _onMobileNavTap(0),
                ),
                _MobileNavItem(
                  icon: Icons.live_tv_outlined,
                  activeIcon: Icons.live_tv,
                  label: l10n.liveTV,
                  isSelected: currentIndex == 1,
                  onTap: () => _onMobileNavTap(1),
                ),
                _MobileNavItem(
                  icon: Icons.movie_outlined,
                  activeIcon: Icons.movie,
                  label: l10n.movies,
                  isSelected: currentIndex == 2,
                  onTap: () => _onMobileNavTap(2),
                ),
                _MobileNavItem(
                  icon: Icons.tv_outlined,
                  activeIcon: Icons.tv,
                  label: l10n.series,
                  isSelected: currentIndex == 3,
                  onTap: () => _onMobileNavTap(3),
                ),
                _MobileNavItem(
                  icon: Icons.search,
                  activeIcon: Icons.search,
                  label: l10n.search,
                  isSelected: false,
                  onTap: () => context.push('/search'),
                ),
                _MobileNavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: l10n.settings,
                  isSelected: currentIndex == 4,
                  onTap: () => _onMobileNavTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMobileNavTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  // ===========================================================================
  //  Back handler
  // ===========================================================================

  void _handleBack() {
    // 0. Check if current screen has a back handler (e.g., close detail panel)
    final handler = ref.read(backHandlerProvider);
    if (handler != null && handler()) return;

    // 1. Desktop: If sidebar is focused → move focus to content area
    if (isDesktopPlatform) {
      final sidebarState = _sidebarKey.currentState;
      if (sidebarState != null && sidebarState.hasFocus) {
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.right);
        return;
      }
    }

    // 2. If not on Dashboard (index 0), go to Dashboard
    if (widget.navigationShell.currentIndex != 0) {
      widget.navigationShell.goBranch(0);
      return;
    }

    // 3. On Dashboard: double-back to exit
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Uygulamadan çıkmak için tekrar basın'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.surfaceElevatedDark,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: isMobilePlatform ? 70 : 50,
          left: 50,
          right: 50,
        ),
      ),
    );
  }
}

// =============================================================================
//  Mobile Nav Item
// =============================================================================

class _MobileNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _MobileNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondaryDark,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textTertiaryDark,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
