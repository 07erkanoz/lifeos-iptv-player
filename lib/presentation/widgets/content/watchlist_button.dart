import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/watchlist_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Bookmark-style toggle to add/remove a movie or series from the user's
/// "watch later" list. Live channels do not use this widget — watchlist is
/// only meaningful for VOD.
class WatchlistButton extends ConsumerWidget {
  final int streamId;
  final String type;
  final String name;
  final String? thumbnail;
  final double size;

  const WatchlistButton({
    super.key,
    required this.streamId,
    required this.type,
    required this.name,
    this.thumbnail,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inListStream = ref.watch(_isInWatchlistProvider((streamId: streamId, type: type)));
    final inList = inListStream.when(
      data: (v) => v,
      loading: () => false,
      error: (_, _) => false,
    );
    final l10n = AppLocalizations.of(context)!;

    return _WatchlistIconButton(
      inWatchlist: inList,
      size: size,
      onToggle: () async {
        final added = await ref
            .read(watchlistRepositoryProvider)
            .toggle(streamId, type, name, thumbnail);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(added ? l10n.addedToWatchlist : l10n.removedFromWatchlist),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.surfaceElevatedDark,
            ),
          );
        }
      },
    );
  }
}

class _WatchlistIconButton extends StatefulWidget {
  final bool inWatchlist;
  final double size;
  final VoidCallback onToggle;

  const _WatchlistIconButton({
    required this.inWatchlist,
    required this.size,
    required this.onToggle,
  });

  @override
  State<_WatchlistIconButton> createState() => _WatchlistIconButtonState();
}

class _WatchlistIconButtonState extends State<_WatchlistIconButton>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant _WatchlistIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bounce only on the add side; removal stays subtle.
    if (widget.inWatchlist != oldWidget.inWatchlist && widget.inWatchlist) {
      _animCtrl.forward().then((_) => _animCtrl.reverse());
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: widget.inWatchlist ? l10n.removeFromWatchlist : l10n.addToWatchlist,
      child: Focus(
        onFocusChange: (f) => setState(() => _isFocused = f),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onToggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isFocused
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: _isFocused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: AnimatedBuilder(
              animation: _scaleAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _scaleAnim.value, child: child),
              child: Icon(
                widget.inWatchlist ? Icons.bookmark : Icons.bookmark_border,
                color: widget.inWatchlist ? AppColors.primary : Colors.white70,
                size: widget.size,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final _isInWatchlistProvider =
    StreamProvider.family<bool, ({int streamId, String type})>((ref, params) {
  return ref
      .watch(watchlistRepositoryProvider)
      .watchIsInWatchlist(params.streamId, params.type);
});
