import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/widgets/layout/sidebar_search_button.dart';

class AppSidebar extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppSidebar({super.key, required this.navigationShell});

  @override
  State<AppSidebar> createState() => AppSidebarState();
}

class AppSidebarState extends State<AppSidebar> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isMouseInside = false;
  late AnimationController _animController;
  late Animation<double> _widthAnimation;
  Timer? _expandTimer;
  Timer? _collapseTimer;

  final List<FocusNode> _itemFocusNodes = [];

  static const _collapsedWidth = 64.0;
  static const _expandedWidth = 200.0;
  // Mouse hover: short delay before expand to prevent accidental brush-past
  static const _hoverExpandDelay = Duration(milliseconds: 150);
  // Collapse: longer delay to prevent flickering
  static const _collapseDelay = Duration(milliseconds: 300);

  List<({IconData icon, IconData activeIcon, String label})> _getMenuItems(AppLocalizations l10n) => [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: l10n.home),
    (icon: Icons.live_tv_outlined, activeIcon: Icons.live_tv, label: l10n.liveTV),
    (icon: Icons.movie_outlined, activeIcon: Icons.movie, label: l10n.movies),
    (icon: Icons.tv_outlined, activeIcon: Icons.tv, label: l10n.series),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: l10n.settings),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _widthAnimation = Tween<double>(begin: _collapsedWidth, end: _expandedWidth).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    for (int i = 0; i < 5; i++) {
      final node = FocusNode();
      node.addListener(_onAnyItemFocusChanged);
      _itemFocusNodes.add(node);
    }
  }

  @override
  void dispose() {
    _expandTimer?.cancel();
    _collapseTimer?.cancel();
    _animController.dispose();
    for (final node in _itemFocusNodes) {
      node.removeListener(_onAnyItemFocusChanged);
      node.dispose();
    }
    super.dispose();
  }

  /// Whether sidebar currently has focus (computed from item focus nodes)
  bool get hasFocus => _itemFocusNodes.any((n) => n.hasFocus);

  /// Whether sidebar should be expanded (has focus OR mouse is inside)
  bool get _shouldBeExpanded => hasFocus || _isMouseInside;

  /// Called whenever any item's focus changes
  void _onAnyItemFocusChanged() {
    _updateExpandState();
  }

  void _onMouseEnter() {
    _isMouseInside = true;
    // Cancel any pending collapse
    _collapseTimer?.cancel();
    _collapseTimer = null;
    // Debounce expand to avoid flash on brush-past
    if (_isExpanded) return; // Already expanded
    _expandTimer?.cancel();
    _expandTimer = Timer(_hoverExpandDelay, () {
      if (mounted && _isMouseInside) {
        _doExpand();
      }
    });
  }

  void _onMouseExit() {
    _isMouseInside = false;
    // Cancel any pending expand
    _expandTimer?.cancel();
    _expandTimer = null;
    _scheduleCollapse();
  }

  /// Immediately expand (used by focus changes)
  void _doExpand() {
    _collapseTimer?.cancel();
    _collapseTimer = null;
    if (_isExpanded) return;
    setState(() => _isExpanded = true);
    _animController.forward();
  }

  /// Schedule collapse with delay
  void _scheduleCollapse() {
    if (!_isExpanded) return;
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted && _isExpanded && !_shouldBeExpanded) {
        setState(() => _isExpanded = false);
        _animController.reverse();
      }
    });
  }

  /// Update expand/collapse based on current state
  void _updateExpandState() {
    if (_shouldBeExpanded) {
      _doExpand();
    } else {
      _scheduleCollapse();
    }
  }

  /// Request focus on the currently selected menu item
  void requestFocus() {
    final idx = widget.navigationShell.currentIndex.clamp(0, _itemFocusNodes.length - 1);
    _itemFocusNodes[idx].requestFocus();
  }

  void _onItemTapped(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    // After selecting, move focus to content area
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.right);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final menuItems = _getMenuItems(l10n);

    return FocusTraversalGroup(
      child: MouseRegion(
        onEnter: (_) => _onMouseEnter(),
        onExit: (_) => _onMouseExit(),
        child: AnimatedBuilder(
          animation: _widthAnimation,
          builder: (context, _) {
            return Container(
              width: _widthAnimation.value,
              decoration: BoxDecoration(
                color: AppColors.sidebarBgDark,
                border: Border(
                  right: BorderSide(color: AppColors.sidebarBorderDark, width: 1),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _buildLogo(),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: AppColors.borderDark, height: 1),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        final isSelected = widget.navigationShell.currentIndex == index;

                        return _SidebarItem(
                          icon: isSelected ? item.activeIcon : item.icon,
                          label: item.label,
                          isSelected: isSelected,
                          isExpanded: _isExpanded,
                          focusNode: _itemFocusNodes[index],
                          onTap: () => _onItemTapped(index),
                        );
                      },
                    ),
                  ),
                  // Search button (pushes /search route)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    child: SidebarSearchButton(isExpanded: _isExpanded),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          if (_isExpanded) ...[
            const Text(
              'Life',
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w300,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 1),
            const Text(
              'OS',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
          ],
          // Red "TV" badge — always visible (collapsed & expanded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE5484D),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'TV',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // D-pad right → move focus to content area
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : isActive
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: _isFocused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : widget.isSelected
                      ? Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1)
                      : null,
            ),
            child: Row(
              mainAxisAlignment: widget.isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: widget.isSelected
                      ? AppColors.primary
                      : isActive
                          ? AppColors.textDark
                          : AppColors.textSecondaryDark,
                  size: 22,
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isSelected
                            ? AppColors.primary
                            : isActive
                                ? AppColors.textDark
                                : AppColors.textSecondaryDark,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
