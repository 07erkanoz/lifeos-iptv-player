import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/hero_billboard_provider.dart';
import 'package:lifeostv/presentation/state/personalized_picks_provider.dart';

/// One-shot onboarding sheet that solves the AI cold-start problem.
///
/// Triggered when:
///   * the user has just configured a Gemini API key, AND
///   * the taste-wizard flag in settings is still false, AND
///   * the user has < 3 favourites + < 5 history rows (so the AI
///     providers truly have nothing to ground recommendations on).
///
/// Shows a 4-column grid of diverse, high-rated posters from the
/// library. The user taps the ones they "love or want to watch".
/// On finish each selection is written to the favourites table —
/// the same signal the AI providers already consult, so no schema
/// migration is needed. A clear copy line tells the user that
/// picks become favourites and can be removed later.
///
/// Dismissing without choosing still flips the wizard-completed
/// flag so the prompt doesn't reappear every dashboard load.
class TasteWizardSheet extends ConsumerStatefulWidget {
  const TasteWizardSheet({super.key});

  /// Public helper that opens the wizard as a modal bottom sheet
  /// pinned to nearly-full height. Returns the number of picks the
  /// user committed (0 when dismissed without choosing).
  static Future<int> show(BuildContext context) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Allow the sheet to occupy almost the whole screen — taste
      // picking benefits from showing 20+ posters at once.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      builder: (ctx) => const TasteWizardSheet(),
    );
    return result ?? 0;
  }

  @override
  ConsumerState<TasteWizardSheet> createState() => _TasteWizardSheetState();
}

class _TasteWizardSheetState extends ConsumerState<TasteWizardSheet> {
  /// Pulled once on first build; cached so the grid doesn't reshuffle
  /// every rebuild.
  List<Channel>? _candidates;
  bool _loading = true;
  bool _committing = false;
  String? _error;

  /// streamId+type → selected. We key on a "$type:$streamId" string
  /// so a movie and a series with the same numeric id don't collide.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCandidates());
  }

  String _selectionKey(Channel c) => '${c.type}:${c.streamId}';

  /// Number of posters to surface in one wizard view. 48 gives the
  /// user enough breadth to find 3+ titles they actually love without
  /// scrolling becoming a chore. The "Karıştır" button reshuffles.
  static const _gridSize = 48;

  Future<void> _loadCandidates() async {
    try {
      final db = ref.read(appDatabaseProvider);

      // Pull a wide swath of VOD joined with categories. We need the
      // category label as the actual diversity signal because
      // `channels.genre` is mostly NULL on Xtream catalogues — the
      // genre data lives in category names like "KOMEDi & ROMANTiK"
      // or "AKSiYON & MACERA". Bucketing by the empty `genre` column
      // dumped everything into one "other" bucket, defeating the
      // diversity logic. Joining categories fixes that completely.
      final rows = await (db.select(db.channels).join([
        db.accountInnerJoin(
          db.categories,
          db.categories.id.equalsExp(db.channels.categoryId) &
              db.categories.type.equalsExp(db.channels.type),
        ),
      ])
            ..where((db.channels.type.equals('movie') |
                    db.channels.type.equals('series')) &
                db.categories.isHidden.equals(false))
            ..orderBy([
              OrderingTerm(
                  expression: db.channels.rating,
                  mode: OrderingMode.desc),
            ])
            ..limit(2500))
          .get();

      // Bucket by category name + apply hard filters in one pass.
      final byCategory = <String, List<Channel>>{};
      final adultRegex = RegExp(r'adult|erotic|xxx|porn|dorcel|brazzers',
          caseSensitive: false);
      for (final r in rows) {
        final ch = r.readTable(db.channels);
        final cat = r.readTable(db.categories);
        // Drop posterless rows — empty tiles look broken in the grid.
        if (ch.streamIcon == null || ch.streamIcon!.isEmpty) continue;
        // Drop adult content from the wizard (the user can still
        // favourite those manually if they want).
        final catName = cat.name;
        if (adultRegex.hasMatch(catName)) continue;
        if (ch.name.toLowerCase().startsWith('adlt')) continue;
        byCategory.putIfAbsent(catName, () => []).add(ch);
      }

      if (byCategory.isEmpty) {
        if (!mounted) return;
        setState(() {
          _candidates = const [];
          _loading = false;
        });
        return;
      }

      // Shuffle category order so the wizard doesn't always lead
      // with the alphabetically-first category. The "Karıştır"
      // button re-calls this same method which re-shuffles → fresh
      // grid each tap.
      final categories = byCategory.keys.toList()..shuffle();

      // Round-robin pull: take 1 item from each category per pass.
      // Posters are roughly rating-sorted within each bucket (we
      // ordered by rating DESC in SQL), so passes 1-3 are top-tier
      // and later passes broaden into the long tail.
      final interleaved = <Channel>[];
      var pass = 0;
      while (interleaved.length < _gridSize) {
        var added = false;
        for (final cat in categories) {
          final list = byCategory[cat]!;
          if (pass < list.length) {
            interleaved.add(list[pass]);
            added = true;
            if (interleaved.length >= _gridSize) break;
          }
        }
        if (!added) break;
        pass++;
      }

      // Two-key dedupe (title + poster URL) so the multi-category
      // Xtream re-listing case (e.g. "Inception" appearing under
      // both DRAM and AKSiYON) doesn't show twice in the grid.
      final seenTitle = <String>{};
      final seenPoster = <String>{};
      final unique = <Channel>[];
      for (final c in interleaved) {
        final tKey = c.name.trim().toLowerCase();
        final pKey = (c.streamIcon ?? '').toLowerCase();
        if (tKey.isNotEmpty && !seenTitle.add(tKey)) continue;
        if (pKey.isNotEmpty && !seenPoster.add(pKey)) continue;
        unique.add(c);
      }

      // Light shuffle of the final list so the grid doesn't visibly
      // descend by rating top-left → bottom-right.
      unique.shuffle();

      if (!mounted) return;
      setState(() {
        _candidates = unique;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// "Karıştır" — reshuffle the grid with a fresh round of picks
  /// from different categories. Clears the user's selections so
  /// they don't accidentally commit something from the previous
  /// view.
  void _reshuffle() {
    setState(() {
      _candidates = null;
      _loading = true;
      _selected.clear();
    });
    _loadCandidates();
  }

  Future<void> _commit() async {
    if (_committing || _candidates == null) return;
    setState(() => _committing = true);
    final favs = ref.read(favoritesRepositoryProvider);
    var added = 0;
    for (final ch in _candidates!) {
      if (!_selected.contains(_selectionKey(ch))) continue;
      try {
        await favs.addFavorite(
            ch.streamId, ch.type, ch.name, ch.streamIcon);
        added++;
      } catch (_) {
        // Best-effort; missing one row shouldn't block the others.
      }
    }
    // Flip the wizard flag regardless — the user has now seen it.
    final current = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).updateSettings(
        current.copyWith(tasteWizardCompleted: true));
    // Nudge the AI providers so the new favourites are picked up.
    ref.invalidate(personalizedPicksProvider);
    ref.invalidate(heroBillboardProvider);
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  Future<void> _skip() async {
    final current = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).updateSettings(
        current.copyWith(tasteWizardCompleted: true));
    if (!mounted) return;
    Navigator.of(context).pop(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canCommit = _selected.length >= 3 && !_committing;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tasteWizardTitle,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tasteWizardSubtitle,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    color: AppColors.primary,
                    onPressed:
                        (_committing || _loading) ? null : _reshuffle,
                    tooltip: l10n.tasteWizardShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.textTertiary(context),
                    onPressed: _committing ? null : _skip,
                    tooltip: l10n.tasteWizardSkip,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body.
            Expanded(
              child: _buildBody(l10n, isDark),
            ),
            // Footer: selection count + commit button.
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? l10n.tasteWizardHint
                          : l10n.tasteWizardSelectedCount(
                              _selected.length),
                      style: TextStyle(
                        color: _selected.isEmpty
                            ? AppColors.textTertiary(context)
                            : AppColors.primary,
                        fontSize: 13,
                        fontWeight: _selected.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _committing ? null : _skip,
                    child: Text(
                      l10n.tasteWizardSkip,
                      style: TextStyle(
                          color: AppColors.textTertiary(context)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: canCommit ? _commit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary
                          .withValues(alpha: 0.3),
                    ),
                    child: _committing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.tasteWizardConfirm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, bool isDark) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            l10n.tasteWizardError,
            style: TextStyle(color: AppColors.textTertiary(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final list = _candidates ?? const [];
    if (list.isEmpty) {
      return Center(
        child: Text(
          l10n.tasteWizardEmpty,
          style: TextStyle(color: AppColors.textTertiary(context)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 720
            ? 6
            : constraints.maxWidth >= 480
                ? 4
                : 3;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 2 / 3.4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final ch = list[i];
            final key = _selectionKey(ch);
            final selected = _selected.contains(key);
            return _PosterTile(
              channel: ch,
              isSelected: selected,
              isDark: isDark,
              onTap: () {
                setState(() {
                  if (selected) {
                    _selected.remove(key);
                  } else {
                    _selected.add(key);
                  }
                });
              },
            );
          },
        );
      },
    );
  }
}

class _PosterTile extends StatefulWidget {
  final Channel channel;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _PosterTile({
    required this.channel,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Focus + key handler so Android TV D-pad can land on the tile
    // and Select / Enter toggles the selection. Without this the
    // wizard was unusable on TV — D-pad couldn't traverse the grid.
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary
                  : (_focused
                      ? AppColors.primary.withValues(alpha: 0.6)
                      : Colors.transparent),
              width: widget.isSelected
                  ? 2.5
                  : (_focused ? 2.0 : 0),
            ),
            boxShadow: (widget.isSelected || _focused)
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: widget.channel.streamIcon!,
                  fit: BoxFit.cover,
                  memCacheWidth: 720,
                  errorWidget: (_, _, _) => Container(
                    color: AppColors.surfaceElevatedDark,
                    child: const Icon(Icons.movie_outlined,
                        color: AppColors.textTertiaryDark),
                  ),
                ),
                // Bottom title overlay.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      widget.channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (widget.isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.check,
                          size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
