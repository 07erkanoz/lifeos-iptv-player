import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Search button at the bottom of the sidebar – pushes /search route
class SidebarSearchButton extends StatefulWidget {
  final bool isExpanded;
  const SidebarSearchButton({super.key, required this.isExpanded});

  @override
  State<SidebarSearchButton> createState() => _SidebarSearchButtonState();
}

class _SidebarSearchButtonState extends State<SidebarSearchButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  void _openSearch() {
    context.push('/search');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = _isFocused || _isHovered;

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          _openSearch();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.right);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: _openSearch,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: _isFocused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: widget.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search,
                  color: isActive ? AppColors.primary : AppColors.textSecondaryDark,
                  size: 22,
                ),
                if (widget.isExpanded) ...[
                  const SizedBox(width: 14),
                  Text(
                    l10n.search,
                    style: TextStyle(
                      color: isActive ? AppColors.primary : AppColors.textSecondaryDark,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
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
