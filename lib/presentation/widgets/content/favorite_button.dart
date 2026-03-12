import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class FavoriteButton extends ConsumerWidget {
  final int streamId;
  final String type;
  final String name;
  final String? thumbnail;
  final double size;

  const FavoriteButton({
    super.key,
    required this.streamId,
    required this.type,
    required this.name,
    this.thumbnail,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavStream = ref.watch(_isFavoriteProvider((streamId: streamId, type: type)));
    final isFav = isFavStream.when(data: (v) => v, loading: () => false, error: (_, __) => false);
    final l10n = AppLocalizations.of(context)!;

    return _FavoriteIconButton(
      isFavorite: isFav,
      size: size,
      onToggle: () async {
        final repo = ref.read(favoritesRepositoryProvider);
        final added = await repo.toggleFavorite(streamId, type, name, thumbnail);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(added ? l10n.addedToFavorites : l10n.removedFromFavorites),
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

/// Internal stateful widget for animation + D-pad focus
class _FavoriteIconButton extends StatefulWidget {
  final bool isFavorite;
  final double size;
  final VoidCallback onToggle;

  const _FavoriteIconButton({
    required this.isFavorite,
    required this.size,
    required this.onToggle,
  });

  @override
  State<_FavoriteIconButton> createState() => _FavoriteIconButtonState();
}

class _FavoriteIconButtonState extends State<_FavoriteIconButton> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(covariant _FavoriteIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFavorite != oldWidget.isFavorite && widget.isFavorite) {
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
    return Focus(
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
            border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: AnimatedBuilder(
            animation: _scaleAnim,
            builder: (_, child) => Transform.scale(scale: _scaleAnim.value, child: child),
            child: Icon(
              widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.isFavorite ? Colors.red : Colors.white70,
              size: widget.size,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final _isFavoriteProvider = StreamProvider.family<bool, ({int streamId, String type})>((ref, params) {
  return ref.watch(favoritesRepositoryProvider).watchIsFavorite(params.streamId, params.type);
});
