import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/config/theme.dart';

/// Custom desktop title bar (Windows/Linux/macOS).
///
/// macOS: window controls on the LEFT (platform convention).
/// Windows/Linux: window controls on the RIGHT.
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
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    } catch (_) {
      // Some Linux WMs may not support isMaximized reliably
    }
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _doMinimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  Future<void> _doToggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  Future<void> _doClose() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }

  Future<void> _startDragging() async {
    try {
      await windowManager.startDragging();
    } catch (_) {
      // Wayland / some Linux compositors may not support drag
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    final isMac = Platform.isMacOS;
    final windowControls = _buildWindowControls(isMac);

    return GestureDetector(
      onPanStart: (_) => _startDragging(),
      onDoubleTap: _doToggleMaximize,
      child: Container(
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.backgroundDark,
          border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          children: [
            // Title (centered)
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
            // Window controls
            Align(
              // macOS: left side; Windows/Linux: right side
              alignment: isMac ? Alignment.centerLeft : Alignment.centerRight,
              child: windowControls,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowControls(bool isMac) {
    if (isMac) {
      // macOS-style traffic light buttons (close, minimize, maximize) on the left
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MacTrafficLight(
            color: const Color(0xFFFF5F57),
            hoverColor: const Color(0xFFFF5F57),
            onTap: _doClose,
          ),
          const SizedBox(width: 8),
          _MacTrafficLight(
            color: const Color(0xFFFFBD2E),
            hoverColor: const Color(0xFFFFBD2E),
            onTap: _doMinimize,
          ),
          const SizedBox(width: 8),
          _MacTrafficLight(
            color: const Color(0xFF28C840),
            hoverColor: const Color(0xFF28C840),
            onTap: _doToggleMaximize,
          ),
        ],
      );
    }

    // Windows/Linux: standard icon buttons on the right
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowActionButton(
          icon: Icons.remove,
          onTap: _doMinimize,
        ),
        const SizedBox(width: 4),
        _WindowActionButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          onTap: _doToggleMaximize,
        ),
        const SizedBox(width: 4),
        _WindowActionButton(
          icon: Icons.close,
          hoverColor: const Color(0xFFCF3D3D),
          onTap: _doClose,
        ),
      ],
    );
  }
}

/// macOS-style round traffic light button.
class _MacTrafficLight extends StatefulWidget {
  final Color color;
  final Color hoverColor;
  final VoidCallback onTap;

  const _MacTrafficLight({
    required this.color,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  State<_MacTrafficLight> createState() => _MacTrafficLightState();
}

class _MacTrafficLightState extends State<_MacTrafficLight> {
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
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovering ? widget.hoverColor : widget.color.withValues(alpha: 0.8),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
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
