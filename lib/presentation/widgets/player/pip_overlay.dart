import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/utils/platform_utils.dart';

// =============================================================================
//  PiP Overlay — Full Window Mode (Linux)
//  Window is resized to PiP dimensions, this widget fills the entire window.
// =============================================================================

class PipOverlay extends ConsumerStatefulWidget {
  const PipOverlay({super.key});

  @override
  ConsumerState<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends ConsumerState<PipOverlay> {
  bool _controlsVisible = true;

  @override
  Widget build(BuildContext context) {
    final pipData = ref.watch(pipProvider);

    if (pipData == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onEnter: (_) => setState(() => _controlsVisible = true),
        onExit: (_) => setState(() => _controlsVisible = false),
        child: GestureDetector(
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(
            children: [
              // Video fills the entire window
              Positioned.fill(
                child: Video(
                  controller: pipData.controller,
                  fill: Colors.black,
                ),
              ),

              if (_controlsVisible) ...[
                // Gradient overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                        stops: const [0.0, 0.25, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),

                // Top bar: draggable area + title
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onPanStart: (_) {
                      windowManager.startDragging();
                    },
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Text(
                        pipData.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),

                // Bottom controls
                Positioned(
                  bottom: 8,
                  left: 10,
                  right: 10,
                  child: _PipControls(pipData: pipData),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  Floating PiP Overlay (Windows/macOS)
//  Small draggable widget floating on top of the app content.
// =============================================================================

class FloatingPipOverlay extends ConsumerStatefulWidget {
  const FloatingPipOverlay({super.key});

  @override
  ConsumerState<FloatingPipOverlay> createState() => _FloatingPipOverlayState();
}

class _FloatingPipOverlayState extends ConsumerState<FloatingPipOverlay> {
  Offset _offset = Offset.zero;
  bool _initialized = false;

  static const double _width = 320;
  static const double _height = 180;
  static const double _dragBarHeight = 34;

  void _updateOffset(Offset delta, Size size) {
    setState(() {
      _offset += delta;
      _offset = Offset(
        _offset.dx.clamp(0, size.width - _width),
        _offset.dy.clamp(0, size.height - _height),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pipData = ref.watch(pipProvider);

    if (pipData == null || !isDesktopPipSupported) {
      return const SizedBox.shrink();
    }

    // Initialize position to bottom-right on first build
    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final size = MediaQuery.of(context).size;
          setState(() {
            _offset = Offset(size.width - _width - 20, size.height - _height - 20);
            _initialized = true;
          });
        }
      });
    }

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        shadowColor: Colors.black54,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: _width,
            height: _height,
            child: Stack(
              children: [
                // Video
                Video(
                  controller: pipData.controller,
                  fill: Colors.black,
                ),

                // Gradient overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.5),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // Drag handle area (top only) to avoid stealing taps from controls
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _dragBarHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (details) => _updateOffset(
                      details.delta,
                      MediaQuery.of(context).size,
                    ),
                  ),
                ),

                // Title
                Positioned(
                  top: 6,
                  left: 10,
                  right: 10,
                  child: IgnorePointer(
                    child: Text(
                      pipData.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

                // Bottom controls
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: _PipControls(pipData: pipData, small: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  Shared PiP Controls
// =============================================================================

class _PipControls extends ConsumerStatefulWidget {
  final PipData pipData;
  final bool small;
  const _PipControls({required this.pipData, this.small = false});

  @override
  ConsumerState<_PipControls> createState() => _PipControlsState();
}

class _PipControlsState extends ConsumerState<_PipControls> {
  @override
  Widget build(BuildContext context) {
    final pd = widget.pipData;
    final btnSize = widget.small ? 28.0 : 32.0;
    final iconSize = widget.small ? 16.0 : 18.0;

    return Row(
      children: [
        // Play/Pause
        _PipButton(
          icon: pd.player.state.playing ? Icons.pause : Icons.play_arrow,
          size: btnSize,
          iconSize: iconSize,
          onTap: () {
            pd.player.playOrPause();
            setState(() {});
          },
        ),
        const Spacer(),
        // Expand to fullscreen
        _PipButton(
          icon: Icons.open_in_full,
          size: btnSize,
          iconSize: iconSize,
          onTap: () => _expandToFullscreen(),
        ),
        const SizedBox(width: 6),
        // Close PiP
        _PipButton(
          icon: Icons.close,
          size: btnSize,
          iconSize: iconSize,
          onTap: () {
            ref.read(pipProvider.notifier).closePip();
          },
        ),
      ],
    );
  }

  void _expandToFullscreen() async {
    final router = GoRouter.of(context);
    final data = await ref.read(pipProvider.notifier).expandToFullscreen();
    if (data == null) return;

    await router.push(
      '/player',
      extra: {
        'url': data.url,
        'title': data.title,
        'type': _videoTypeFromName(data.typeName),
        'logo': data.logo,
        'existingPlayer': data.player,
        'existingController': data.controller,
      },
    );
  }

  VideoType _videoTypeFromName(String typeName) {
    switch (typeName.toLowerCase()) {
      case 'movie':
        return VideoType.movie;
      case 'series':
        return VideoType.series;
      default:
        return VideoType.live;
    }
  }
}

class _PipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _PipButton({
    required this.icon,
    required this.onTap,
    this.size = 32,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}
