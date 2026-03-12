import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/config/theme.dart';

/// Custom desktop title bar (Windows/Linux/macOS).
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  static const double _windowControlsWidth = 92;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.backgroundDark,
          border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          children: [
            const Align(
              alignment: Alignment.center,
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _windowControlsWidth + 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tv, size: 14, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'LifeOs TV',
                        style: TextStyle(
                          color: AppColors.textSecondaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WindowActionButton(
                    icon: Icons.remove,
                    onTap: () => windowManager.minimize(),
                  ),
                  const SizedBox(width: 4),
                  _WindowActionButton(
                    icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                    onTap: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  _WindowActionButton(
                    icon: Icons.close,
                    hoverColor: const Color(0xFFCF3D3D),
                    onTap: () => windowManager.close(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowActionButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverColor;

  const _WindowActionButton({
    required this.icon,
    required this.onTap,
    this.hoverColor,
  });

  @override
  State<_WindowActionButton> createState() => _WindowActionButtonState();
}

class _WindowActionButtonState extends State<_WindowActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 28,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: _hovering
                ? (widget.hoverColor ?? AppColors.surfaceHoverDark).withValues(alpha: 0.9)
                : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 14,
            color: AppColors.textSecondaryDark,
          ),
        ),
      ),
    );
  }
}
