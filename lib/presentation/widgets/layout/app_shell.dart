import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/widgets/layout/app_shell_back_resolver.dart';
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
    // ALWAYS intercept back at the shell. The shell is the home route,
    // so a system pop here just finishes the activity (closes the app)
    // — which is exactly the bug we're avoiding. Pushed routes (search,
    // player, detail) sit ABOVE the shell on the root navigator and pop
    // themselves before this ever fires, so intercepting here only
    // affects the case where a tab root is visible, where we want our
    // own back ladder (non-home branch → Dashboard, Dashboard → exit
    // confirm) to run instead of the OS closing the app.
    //
    // Relying on `Navigator.of(context).canPop()` was the bug: inside
    // GoRouter's nested-navigator tree it could report `true`, letting
    // the OS pop the shell and close the app from any tab.
    return PopScope(
      canPop: false,
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
      backgroundColor: AppColors.background(context),
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
      backgroundColor: AppColors.background(context),
      body: SafeArea(child: widget.navigationShell),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.sidebarBg(context),
          border: Border(
            top: BorderSide(color: AppColors.sidebarBorder(context), width: 0.5),
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
    // Pure decision (no side effects). Logic stays in
    // [resolveAppShellBackAction] so it's unit-testable end-to-end
    // without standing up a navigation shell.
    // The grid screens (live=1, movies=2, series=3) register a single
    // global back handler, but they all stay mounted in the shell's
    // IndexedStack so the "last to set wins" — a stale handler from a
    // non-visible tab must not eat the back press on Dashboard/Settings.
    // Only consult it when a grid branch is actually visible.
    final idx = widget.navigationShell.currentIndex;
    final onGridBranch = idx == 1 || idx == 2 || idx == 3;
    final handler = ref.read(backHandlerProvider);
    final screenHandled = onGridBranch && handler != null && handler();
    final sidebarState = _sidebarKey.currentState;
    final now = DateTime.now();

    final action = resolveAppShellBackAction(
      screenHandlerHandled: screenHandled,
      isDesktopPlatform: isDesktopPlatform,
      sidebarMounted: sidebarState != null,
      sidebarHasFocus: sidebarState?.hasFocus ?? false,
      currentBranchIndex: widget.navigationShell.currentIndex,
      lastBackPress: _lastBackPress,
      now: now,
    );

    switch (action) {
      case AppShellBackAction.consumed:
        return;
      case AppShellBackAction.focusSidebar:
        sidebarState!.requestFocus();
        return;
      case AppShellBackAction.goToDashboard:
        widget.navigationShell.goBranch(0);
        return;
      case AppShellBackAction.exit:
        SystemNavigator.pop();
        return;
      case AppShellBackAction.showExitConfirm:
        break;
    }

    _lastBackPress = now;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.exitConfirm),
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
              color: isSelected
                  ? AppColors.primary
                  : AppColors.textSecondary(context),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textTertiary(context),
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
