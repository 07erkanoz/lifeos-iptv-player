import 'package:flutter/material.dart';

import 'package:lifeostv/config/theme.dart';

/// A TV control with a visible focus state and a short label for remote users.
class TvPlayerActionButton extends StatelessWidget {
  const TvPlayerActionButton({
    super.key,
    required this.icon,
    this.label,
    required this.onPressed,
    this.focusNode,
    this.primary = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: label == null ? 56 : 82,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            focusNode: focusNode,
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon, size: primary ? 30 : 24),
            style: ButtonStyle(
              fixedSize: const WidgetStatePropertyAll(Size(50, 50)),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return AppColors.primary;
                }
                return primary
                    ? AppColors.primary.withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.10);
              }),
            ),
          ),
          if (label != null)
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
        ],
      ),
    );
  }
}
