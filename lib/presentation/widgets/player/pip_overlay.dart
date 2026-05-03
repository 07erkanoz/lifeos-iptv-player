import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';

// =============================================================================
//  PiP Overlay — Full Window Mode (all desktop platforms)
//  Host window is resized to PiP dimensions (see PipNotifier), this widget
//  fills the entire window with the video.
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

// FloatingPipOverlay was removed. Earlier the Win/macOS PiP path stacked
// a small draggable widget on top of the running app, but users reported
// the rest of the app stayed visible behind the overlay — not the
// "popped out" experience expected from PiP. The replacement (see
// PipNotifier._shrinkWindowToPip) shrinks the host window itself and
// renders PipOverlay full-window, so the entire screen is the mini
// player. Same code path now serves Windows + macOS + Linux.

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
