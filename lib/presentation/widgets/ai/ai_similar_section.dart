import 'package:lifeostv/presentation/state/locale_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
// `hide Column` so Flutter's widget `Column` resolves below — drift
// exports a Column type for its DSL that would otherwise shadow it.
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/similar_group.dart';
import 'package:lifeostv/data/repositories/ai_similar_cache_repository.dart';
import 'package:lifeostv/data/repositories/content_enrichment_repository.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/data/services/semantic_search_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Replacement for the token-overlap "Similar content" rail on movie
/// and series detail pages, used when the user has a Gemini key
/// configured.
///
/// Shows a header (✨ "Sana özel benzer içerikler") followed by
/// axis-grouped sub-sections. Each axis has a label + optional
/// subtitle and a horizontal scrolling row of poster cards, every
/// card carrying a one-sentence justification specific to that axis:
///
///   ┌── Aynı yönetmenden ── Hong Sung-chang ──────────┐
///   │  [📽 Memories of Murder]  [📽 Memories]       │
///   │  Aynı yönetmenin ödüllü...  Hong'un 2003 yapımı │
///   └─────────────────────────────────────────────────┘
///   ┌── Aynı oyuncularla ── Yoo Yeon-seok ────────────┐
///   │  [📽 ...]                                       │
///   └─────────────────────────────────────────────────┘
///
/// On AI failure, renders nothing and trusts the parent to fall back
/// to the existing simple similar grid (the caller passes a
/// [fallbackBuilder] so this widget never decides UX policy alone).
class AiSimilarSection extends ConsumerStatefulWidget {
  /// The detail item we're looking at.
  final Channel current;

  /// Optional caller hook: when the AI path produces no usable
  /// result (no key / Gemini errored / empty groups), this builder
  /// is called to render whatever the screen used to show.
  final Widget Function(BuildContext context)? fallbackBuilder;

  /// Called when a similar-item poster is tapped.
  final void Function(Channel channel) onTap;

  const AiSimilarSection({
    super.key,
    required this.current,
    required this.onTap,
    this.fallbackBuilder,
  });

  @override
  ConsumerState<AiSimilarSection> createState() => _AiSimilarSectionState();
}

class _AiSimilarSectionState extends ConsumerState<AiSimilarSection> {
  /// Cache key — when this differs from the current channel's id we
  /// kick off a fresh fetch on next build.
  int? _cachedFor;

  /// AI result. `null` means "haven't fetched yet". Empty list means
  /// "fetched, AI returned nothing useful → fall back".
  List<SimilarGroup>? _groups;

  bool _loading = false;
  bool _failed = false;

  /// Resolves ids back into Channel rows, populated alongside
  /// [_groups]. We pre-resolve so the horizontal cards can render
  /// without N async lookups during scroll.
  Map<int, Channel> _channelsById = const {};

  /// Build a semantic-similarity group from the on-device embedding
  /// index. This is the part that actually reflects catalog
  /// enrichment: the vectors are built from genre + themes + mood, so
  /// neighbours here are "same vibe", not just "same genre word". It's
  /// offline, instant, and per-title — so we always show it as the
  /// first group, even when Gemini also returns axis groups below.
  ///
  /// Returns a null group when the anchor isn't embedded yet or there
  /// aren't at least 2 resolvable neighbours (caller just skips it).
  Future<({SimilarGroup? group, Map<int, Channel> channels})>
  _embeddingGroup() async {
    // Capture l10n before any await so we don't touch context across
    // an async gap.
    final l10n = AppLocalizations.of(context)!;
    try {
      final hits = await ref
          .read(semanticSearchServiceProvider)
          .similarTo(
            widget.current.streamId,
            widget.current.type,
            k: 14,
            restrictType: widget.current.type,
          );
      if (hits.isEmpty) {
        return (group: null, channels: const <int, Channel>{});
      }
      final db = ref.read(appDatabaseProvider);
      final ids = hits.map((h) => h.streamId).toList();
      final rows = await (db.select(
        db.channels,
      )..where((t) => t.streamId.isIn(ids))).get();
      final byId = {
        for (final r in rows)
          if (r.type == widget.current.type) r.streamId: r,
      };
      final items = <SimilarItem>[];
      for (final h in hits) {
        if (h.streamId == widget.current.streamId) continue;
        if (byId[h.streamId] == null) continue;
        items.add(
          SimilarItem(
            streamId: h.streamId,
            reason: l10n.aiSimilarSemanticReason,
          ),
        );
        if (items.length >= 10) break;
      }
      if (items.length < 2) {
        return (group: null, channels: const <int, Channel>{});
      }
      return (
        group: SimilarGroup(
          axisLabel: l10n.aiSimilarSemanticAxis,
          axisSubtitle: null,
          items: items,
        ),
        channels: byId,
      );
    } catch (_) {
      return (group: null, channels: const <int, Channel>{});
    }
  }

  Future<void> _fetchSimilar() async {
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _failed = false;
      _groups = null;
    });

    // Semantic (embedding) group — offline, instant, enrichment-aware.
    // Computed once up-front and prepended to whatever the Gemini /
    // cache path produces, so the rail ALWAYS reflects catalog
    // enrichment (themes/mood live in the vectors).
    final emb = await _embeddingGroup();
    if (!mounted) return;

    // ─── Drift cache fast path ───────────────────────────────
    // Same (title, taste) pair as a previous open → instant hit,
    // skipping the 5-10 s Gemini round-trip entirely. We compute
    // the fingerprint up-front because we also need it on miss
    // (to store the freshly-fetched result back under the same
    // key).
    final cacheRepo = ref.read(aiSimilarCacheRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final favIdsForKey =
        await (db.select(db.favorites)
              ..where((t) => t.streamType.equals(widget.current.type)))
            .get()
            .then((rows) => rows.map((r) => r.streamId).toList());
    final cacheKey = AiSimilarCacheRepository.fingerprint(
      streamId: widget.current.streamId,
      type: widget.current.type,
      favouriteIds: favIdsForKey,
    );
    final cached = await cacheRepo.lookup(
      streamId: widget.current.streamId,
      type: widget.current.type,
      sourceHash: cacheKey,
    );
    if (cached != null) {
      // Re-hydrate the JSON list back into SimilarGroup objects.
      // Wrapped in try/catch so a malformed legacy row falls through
      // to the live fetch instead of breaking the rail.
      try {
        final groups = cached
            .map((e) => SimilarGroup.fromJson(e as Map<String, dynamic>))
            .whereType<SimilarGroup>()
            .toList();
        if (groups.isEmpty) throw const FormatException('empty cache');
        // Pull the same library sample we'd have built for prompt
        // context so the cards have full Channel rows to render.
        // Cheap query; bounded by the existing sampleLibraryForAi
        // caller below would have done it anyway.
        final sampleByType = await ref
            .read(contentRepositoryProvider)
            .sampleLibraryForAi(
              moviesPerType: widget.current.type == 'movie' ? 500 : 30,
              seriesPerType: widget.current.type == 'series' ? 500 : 30,
              livePerType: widget.current.type == 'live' ? 80 : 10,
            );
        if (!mounted) return;
        setState(() {
          _loading = false;
          _failed = false;
          _groups = [if (emb.group != null) emb.group!, ...groups];
          _channelsById = {
            for (final c in sampleByType) c.streamId: c,
            ...emb.channels,
          };
          _cachedFor = widget.current.streamId;
        });
        return;
      } catch (_) {
        // fall through to live fetch
      }
    }

    final repo = ref.read(contentRepositoryProvider);
    // Pull a much bigger same-type sample of the library. 80 was
    // not enough for catalogues over a few hundred items — the
    // top-rated tail rarely overlapped with what would actually
    // make a great match (niche or mid-tier titles AI knows by
    // name). 500 items keeps the prompt ~30 KB / ~7.5 K tokens
    // in the new pipe-separated compact form.
    final sampleByType = await repo.sampleLibraryForAi(
      moviesPerType: widget.current.type == 'movie' ? 500 : 30,
      seriesPerType: widget.current.type == 'series' ? 500 : 30,
      livePerType: widget.current.type == 'live' ? 80 : 10,
    );
    // Skip the current item itself.
    final sample = sampleByType
        .where((c) => c.streamId != widget.current.streamId)
        .toList();

    // Personalisation signal: pull the user's most-recently-watched
    // items + a few favourites. AI uses these as a taste hint —
    // "this user leans into Korean drama / 90 dk under films / etc."
    // We compute these from the SAME library sample so the result
    // is just a subset already in the prompt; no extra tokens.
    //
    // For a fresh user with no history / favourites this stays
    // empty and AI falls back to pure item-similarity matching.
    // (Note: `db` is the same AppDatabase instance we used for the
    // cache fingerprint above — Riverpod keepAlive provider, single
    // shared connection, no shadowing needed.)
    final favoritesSample = <Channel>[];
    try {
      // Up to 10 favourite items matching the current type. Cheap
      // join, single query, runs in parallel with the sample fetch
      // semantically.
      final favRows =
          await (db.select(db.channels).join([
                  db.accountInnerJoin(
                    db.favorites,
                    db.favorites.streamId.equalsExp(db.channels.streamId) &
                        db.favorites.streamType.equalsExp(db.channels.type),
                  ),
                ])
                ..where(db.channels.type.equals(widget.current.type))
                ..orderBy([
                  OrderingTerm(
                    expression: db.favorites.addedAt,
                    mode: OrderingMode.desc,
                  ),
                ])
                ..limit(10))
              .get();
      favoritesSample.addAll(favRows.map((row) => row.readTable(db.channels)));
    } catch (_) {
      // Favourites query failure isn't fatal — drop the taste
      // signal and proceed with item-only matching.
    }

    Map<String, dynamic> compact(Channel ch) => {
      'streamId': ch.streamId,
      'title': ch.name,
      'type': ch.type,
      if (ch.genre != null && ch.genre!.isNotEmpty) 'genre': ch.genre,
      if (ch.year != null && ch.year!.isNotEmpty) 'year': ch.year,
      if (ch.director != null && ch.director!.isNotEmpty)
        'director': ch.director,
      if (ch.cast != null && ch.cast!.isNotEmpty) 'cast': ch.cast,
      if (ch.rating != null) 'rating': ch.rating,
    };

    // Enrichment for the CURRENT item — feeds Gemini the themes/mood
    // it can't read off the raw provider metadata, so axis picks like
    // "same theme" / "similar tone" actually have signal to work with.
    final curEnrich = await ref
        .read(contentEnrichmentRepositoryProvider)
        .lookup(widget.current.streamId, widget.current.type);

    final effGenre =
        (widget.current.genre != null && widget.current.genre!.isNotEmpty)
        ? widget.current.genre
        : curEnrich?.genres;

    final groups = await gemini.findSimilarContent(
      currentTitle: widget.current.name,
      currentType: widget.current.type,
      currentYear: widget.current.year,
      currentGenre: effGenre,
      currentPlot: widget.current.plot,
      currentDirector: widget.current.director,
      currentCast: widget.current.cast,
      currentThemes: curEnrich?.themes,
      currentMood: curEnrich?.moodTags,
      librarySample: sample.map(compact).toList(),
      favorites: favoritesSample.map(compact).toList(),
      targetLanguage: _userLanguageCode(),
    );

    if (!mounted) return;

    if (groups == null || groups.isEmpty) {
      // Gemini gave nothing — but if we have a semantic group we can
      // still show a genuinely useful, enrichment-aware rail instead
      // of dropping to the metadata fallback.
      if (emb.group != null) {
        setState(() {
          _loading = false;
          _failed = false;
          _groups = [emb.group!];
          _channelsById = emb.channels;
          _cachedFor = widget.current.streamId;
        });
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
        _groups = const [];
        _cachedFor = widget.current.streamId;
      });
      return;
    }

    final byId = {for (final c in sample) c.streamId: c, ...emb.channels};
    setState(() {
      _loading = false;
      _failed = false;
      _groups = [if (emb.group != null) emb.group!, ...groups];
      _channelsById = byId;
      _cachedFor = widget.current.streamId;
    });

    // Write the result to the Drift cache for the next time this
    // title is opened. Fire-and-forget — a cache write failure is
    // a soft regression (the rail still works, just slow next time).
    cacheRepo.store(
      streamId: widget.current.streamId,
      type: widget.current.type,
      sourceHash: cacheKey,
      payload: groups.map((g) => g.toJson()).toList(),
    );
  }

  String _userLanguageCode() {
    return ref.read(resolvedLocaleProvider).languageCode;
  }

  @override
  Widget build(BuildContext context) {
    final hasAiKey = ref.watch(settingsProvider).hasAiKey;
    // On Android TV, AI is fully off (gemini is null) — always use the plain
    // fallback rail so no ✨/AI header or auto-fetch appears here.
    if (!hasAiKey || PlatformHelper.isTV) {
      return widget.fallbackBuilder?.call(context) ?? const SizedBox.shrink();
    }

    // Lazily kick off the fetch on first build (or when the channel
    // changes). We do this from build instead of initState because
    // `ref.read` of a provider that depends on context is safer once
    // we have a real context available.
    if (_cachedFor != widget.current.streamId && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchSimilar();
      });
    }

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Progressive enhancement:
    //   * AI hasn't returned yet (loading) → show the algorithmic
    //     fallback NOW so the rail is never blank. AI fetch keeps
    //     running in the background; when it lands the result will
    //     replace the fallback in the next paint.
    //   * AI failed / returned nothing useful → stay on the
    //     fallback permanently.
    //   * AI returned groups → show those (upgrade from the fallback).
    //
    // Net effect: the user never waits 5-10 s on a spinner. The
    // fallback (`_selectSimilarContent` in movies/series screens)
    // uses category + genre overlap + director + cast + plot
    // keywords — already a strong recommender on its own. AI is
    // additive when the network cooperates, not a requirement for
    // the rail to be useful.
    final aiNotReady =
        _loading || _groups == null || _groups!.isEmpty || _failed;
    if (aiNotReady) {
      final fb = widget.fallbackBuilder?.call(context);
      if (fb != null) return fb;
      // No fallback supplied at all → only then show the spinner.
      // Callers in movies / series screens always pass one, so this
      // branch is the rare "AI assistant page, no algorithm seed"
      // path.
      if (_loading) {
        return _Header(
          title: l10n.aiSimilarTitle,
          subtitle: l10n.aiSimilarLoading,
          isDark: isDark,
          child: const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return _Header(
      title: l10n.aiSimilarTitle,
      subtitle: null,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in _groups!) ...[
            _AxisGroup(
              group: group,
              channelsById: _channelsById,
              onTap: widget.onTap,
              isDark: isDark,
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isDark;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isDark ? AppColors.textDark : AppColors.textLight,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 10),
              Text(
                subtitle!,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _AxisGroup extends StatelessWidget {
  final SimilarGroup group;
  final Map<int, Channel> channelsById;
  final void Function(Channel channel) onTap;
  final bool isDark;

  const _AxisGroup({
    required this.group,
    required this.channelsById,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = <(SimilarItem, Channel)>[];
    for (final item in group.items) {
      final ch = channelsById[item.streamId];
      if (ch != null) resolved.add((item, ch));
    }
    if (resolved.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              group.axisLabel,
              style: TextStyle(
                color: isDark ? AppColors.textDark : AppColors.textLight,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (group.axisSubtitle != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '· ${group.axisSubtitle}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondaryDark,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: resolved.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final (item, ch) = resolved[i];
              return _SimilarCard(
                item: item,
                channel: ch,
                onTap: () => onTap(ch),
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SimilarCard extends StatefulWidget {
  final SimilarItem item;
  final Channel channel;
  final VoidCallback onTap;
  final bool isDark;

  const _SimilarCard({
    required this.item,
    required this.channel,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_SimilarCard> createState() => _SimilarCardState();
}

class _SimilarCardState extends State<_SimilarCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isActive = _hovered || _focused;
    return Focus(
      // TV D-pad navigation: each horizontal axis is a ListView, so
      // left/right naturally scroll through cards via the default
      // scrollable behaviour. select/enter opens the detail.
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          // Ensure focused card stays visible in the horizontal
          // scroller — D-pad navigation can otherwise leave the
          // newly-focused card off-screen.
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PlatformHelper.focusAnim,
            width: 130,
            // No scale transform on TV — the focus border marks selection.
            transform: (isActive && !PlatformHelper.isTV)
                ? (Matrix4.identity()..scaleByDouble(1.04, 1.04, 1.04, 1.0))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              // Visible focus ring so the TV-remote user can see
              // which card is selected at a glance.
              border: _focused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ch.streamIcon!,
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover,
                          memCacheWidth: 320,
                          errorWidget: (_, _, _) => _placeholderPoster(),
                        )
                      : _placeholderPoster(),
                ),
                const SizedBox(height: 6),
                Text(
                  ch.name,
                  style: TextStyle(
                    color: widget.isDark
                        ? AppColors.textDark
                        : AppColors.textLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  widget.item.reason,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderPoster() {
    return Container(
      width: 130,
      height: 130,
      color: AppColors.surfaceElevatedDark,
      child: const Icon(
        Icons.movie_outlined,
        color: AppColors.textTertiaryDark,
        size: 36,
      ),
    );
  }
}
