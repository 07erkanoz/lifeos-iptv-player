import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/config/theme.dart';

class PlayerToolbarAction {
  const PlayerToolbarAction({
    required this.id,
    required this.label,
    this.icon,
    this.onPressed,
    this.focusNode,
    this.primary = false,
    this.showLabel = false,
    this.tint,
    this.child,
  });
  final String id, label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool primary, showLabel;
  final Color? tint;
  final Widget? child;
}

/// Labels yield to icons before wrapping. Controls never disappear into a
/// clipped horizontal strip, and stable action IDs preserve focus on resize.
class ResponsivePlayerToolbar extends StatelessWidget {
  const ResponsivePlayerToolbar({
    super.key,
    required this.actions,
    this.touch = false,
  });
  final List<PlayerToolbarAction> actions;
  final bool touch;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final minHit = touch ? 44.0 : 36.0;
      final spacing = width >= 900 ? 8.0 : 4.0;
      final gaps = spacing * (actions.length - 1).clamp(0, actions.length);
      final hit = actions.isEmpty
          ? 44.0
          : ((width - gaps) / actions.length).clamp(minHit, 44.0);
      final scaler = MediaQuery.textScalerOf(context);
      final textStyle = DefaultTextStyle.of(context).style.merge(
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      );
      final labelWidths = [
        for (final action in actions)
          if (action.showLabel)
            _measure(
                  action.label,
                  textStyle,
                  scaler,
                  Directionality.of(context),
                ) +
                14
          else
            0.0,
      ];
      final labels = labelWidths.fold<double>(0, (a, b) => a + b);
      final showLabels = actions.length * minHit + gaps + labels <= width;
      final labelHit = actions.isEmpty
          ? 44.0
          : ((width - gaps - labels) / actions.length).clamp(minHit, 48.0);
      final baseHit = showLabels ? labelHit : hit;
      return Wrap(
        spacing: spacing,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < actions.length; i++)
            _ToolbarButton(
              key: ValueKey('player-action-${actions[i].id}'),
              action: actions[i],
              width: (baseHit + (showLabels ? labelWidths[i] : 0)).clamp(
                0,
                width,
              ),
              height: touch ? 48 : 44,
              compact: baseHit < 40,
              showLabel: showLabels && actions[i].showLabel,
              textStyle: textStyle,
            ),
        ],
      );
    },
  );
  static double _measure(
    String text,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    super.key,
    required this.action,
    required this.width,
    required this.height,
    required this.compact,
    required this.showLabel,
    required this.textStyle,
  });
  final PlayerToolbarAction action;
  final double width, height;
  final bool compact, showLabel;
  final TextStyle textStyle;
  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  final _ownedFocus = FocusNode();
  bool _focused = false, _hovered = false;
  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: action.child != null
          ? Center(child: action.child)
          : Semantics(
              button: true,
              label: action.label,
              enabled: action.onPressed != null,
              child: Tooltip(
                message: action.label,
                excludeFromSemantics: true,
                child: Focus(
                  focusNode: action.focusNode ?? _ownedFocus,
                  canRequestFocus: action.onPressed != null,
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.select)) {
                      action.onPressed?.call();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: GestureDetector(
                      onTap: action.onPressed,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: action.primary
                              ? AppColors.primary
                              : Colors.white.withValues(
                                  alpha: _focused || _hovered ? 0.2 : 0.08,
                                ),
                          border: Border.all(
                            color: _focused
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              action.icon,
                              size: action.primary
                                  ? widget.compact
                                        ? 22
                                        : 26
                                  : widget.compact
                                  ? 20
                                  : 22,
                              color: action.tint ?? Colors.white,
                            ),
                            if (widget.showLabel) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  action.label,
                                  style: widget.textStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
