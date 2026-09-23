import 'package:flutter/services.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';

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

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _expand();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                    controls: NoVideoControls,
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
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
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
      ),
    );
  }

  bool _expanding = false;
  Future<void> _expand() async {
    if (_expanding) return;
    _expanding = true;
    try {
      await ref.read(pipProvider.notifier).expandToFullscreen();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.error)),
      );
    } finally {
      _expanding = false;
    }
  }
}

// FloatingPipOverlay was removed. Earlier the Win/macOS PiP path stacked
// a small draggable widget on top of the running app, but users reported
// the rest of the app stayed visible behind the overlay — not the
// "popped out" experience expected from PiP. The replacement (see
// PlayerWindowController.enterPip) shrinks the host window itself and
// renders PipOverlay full-window, so the entire screen is the mini
// player. Same code path now serves Windows + macOS + Linux.

// =============================================================================
//  Shared PiP Controls
// =============================================================================

class _PipControls extends ConsumerStatefulWidget {
  final PipData pipData;
  const _PipControls({required this.pipData});

  @override
  ConsumerState<_PipControls> createState() => _PipControlsState();
}

class _PipControlsState extends ConsumerState<_PipControls> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final pd = widget.pipData;
    // Previously there was a `small` constructor flag that swapped these
    // to 28/16 for a denser layout, but no caller ever used it — the
    // only callsite (line ~101) takes the default. Dropped the flag so
    // the widget's surface matches what the codebase actually uses.
    const btnSize = 32.0;
    const iconSize = 18.0;

    return Row(
      children: [
        // Play/Pause
        StreamBuilder<bool>(
          stream: pd.player.stream.playing,
          initialData: pd.player.state.playing,
          builder: (_, snapshot) => _PipButton(
            icon: snapshot.data == true ? Icons.pause : Icons.play_arrow,
            size: btnSize,
            iconSize: iconSize,
            onTap: _busy ? null : () => _run(pd.player.playOrPause),
          ),
        ),
        const Spacer(),
        // Expand to fullscreen
        _PipButton(
          icon: Icons.open_in_full,
          size: btnSize,
          iconSize: iconSize,
          onTap: _busy ? null : _expandToFullscreen,
        ),
        const SizedBox(width: 6),
        // Close PiP
        _PipButton(
          icon: Icons.close,
          size: btnSize,
          iconSize: iconSize,
          onTap: _busy ? null : _closePip,
        ),
      ],
    );
  }

  /// Keep close/expand mutually exclusive until native restoration completes.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.error)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _expandToFullscreen() => _run(() async {
    await ref.read(pipProvider.notifier).expandToFullscreen();
  });

  void _closePip() => _run(() async {
    final router = GoRouter.of(context);
    await ref.read(pipProvider.notifier).closePip();
    if (mounted && router.canPop()) router.pop();
  });
}

class _PipButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
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
