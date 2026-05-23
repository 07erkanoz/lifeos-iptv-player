import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/search_intent.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/data/repositories/search_history_repository.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/widgets/ui/empty_state.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _textFocus;
  final FocusNode _gridFocus = FocusNode();
  /// Stable focus node for the first result card across rebuilds.
  /// Reassigned to whichever section is currently first non-empty so
  /// the text input's arrow-down bridge always lands on a visible
  /// poster. Created here (not per item builder) so identity survives
  /// list rebuilds — otherwise FocusNode.requestFocus() from the
  /// arrow-down bridge would race the rebuild.
  final FocusNode _firstResultFocus = FocusNode(debugLabel: 'SearchFirstResult');
  Timer? _debounce;
  int _searchRequestId = 0;

  /// Separate debouncer for the AI auto-suggest pipeline. Fires
  /// faster than the main search (300 ms vs 400 ms) so chips appear
  /// before plain results so the user can pivot if they pick a
  /// suggestion mid-stream.
  Timer? _suggestDebounce;
  int _suggestRequestId = 0;
  List<String> _aiSuggestions = const [];
  bool _loadingSuggestions = false;
  List<Channel> _movieResults = [];
  List<Channel> _seriesResults = [];
  List<Channel> _liveResults = [];
  bool _isSearching = false;

  /// True while plain results are on screen *and* a Gemini call is
  /// still in flight that may upgrade them. Drives the small
  /// "AI yorumluyor…" badge so the user knows further refinement
  /// is coming even though the grid already populated.
  bool _aiRefining = false;

  /// Last AI-parsed intent for the active query, or `null` when we
  /// took the plain-search code path (no key, AI failed, or AI
  /// returned no structured filters). When non-null we render an
  /// "AI yorumladı: …" chip row above the results so the user can
  /// see why they got those filters.
  SearchIntent? _activeIntent;

  /// Per-card "AI seçti çünkü…" reason text from the Tier-3 library
  /// curator. Result tiles look up their stream id in this map and
  /// render the reason underneath the poster when present.
  Map<int, String> _curatorReasons = const {};

  bool get _hasResults => _movieResults.isNotEmpty || _seriesResults.isNotEmpty || _liveResults.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Intercept arrow-down on the search field at the FocusNode level
    // (before TextField processes keys) so we can bridge into the
    // results grid. Single-line TextField doesn't use arrow-down for
    // anything, so intercepting it costs nothing.
    _textFocus = FocusNode(
      debugLabel: 'SearchTextInput',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown &&
            _hasResults) {
          _focusFirstResult();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _controller.dispose();
    _textFocus.dispose();
    _gridFocus.dispose();
    _firstResultFocus.dispose();
    super.dispose();
  }

  /// Fire-and-forget AI auto-suggest. Runs in parallel with the main
  /// search debouncer — the chip row appears above the results and
  /// lets the user pivot to a more specific query without thinking
  /// of the phrasing.
  void _scheduleSuggest(String query) {
    _suggestDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      if (_aiSuggestions.isNotEmpty || _loadingSuggestions) {
        setState(() {
          _aiSuggestions = const [];
          _loadingSuggestions = false;
        });
      }
      return;
    }
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) {
      // No AI key — keep chip row hidden entirely.
      return;
    }
    final requestId = ++_suggestRequestId;
    setState(() => _loadingSuggestions = true);
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      final lang = ref.read(settingsProvider).language.name == 'system'
          ? 'tr'
          : ref.read(settingsProvider).language.name;
      final out = await gemini
          .suggestSearchRefinements(
            partialQuery: trimmed,
            targetLanguage: lang,
          )
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (!mounted || requestId != _suggestRequestId) return;
      setState(() {
        _aiSuggestions = out ?? const [];
        _loadingSuggestions = false;
      });
    });
  }

  /// Move focus to the first result card. Called when the user
  /// presses arrow-down (or Enter) from the search input.
  void _focusFirstResult() {
    if (_firstResultFocus.canRequestFocus) {
      _firstResultFocus.requestFocus();
    }
  }

  /// True if [section] is the first non-empty results section in
  /// render order. Used to decide which grid gets the
  /// _firstResultFocus node and the arrowUp→text bridge.
  bool _isFirstSection(List<Channel> section) {
    if (identical(section, _movieResults)) return _movieResults.isNotEmpty;
    if (identical(section, _seriesResults)) {
      return _movieResults.isEmpty && _seriesResults.isNotEmpty;
    }
    if (identical(section, _liveResults)) {
      return _movieResults.isEmpty &&
          _seriesResults.isEmpty &&
          _liveResults.isNotEmpty;
    }
    return false;
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final requestId = ++_searchRequestId;
    // Kick the AI suggest pipeline in parallel — it has its own
    // debouncer and its own request id, so it doesn't fight the
    // main search timeline.
    _scheduleSuggest(query);
    if (query.trim().isEmpty) {
      setState(() {
        _movieResults = [];
        _seriesResults = [];
        _liveResults = [];
        _isSearching = false;
        _aiRefining = false;
        _activeIntent = null;
        _curatorReasons = const {};
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final trimmed = query.trim();

      // Phase 1 — always do the plain LIKE search first and surface
      // its results immediately. Without this, while Gemini was
      // thinking the spinner stayed up for 5-8 seconds and the user
      // saw nothing for queries Xtream metadata could already
      // answer. The spinner now goes away in ~50 ms and the user
      // has *something* to look at even if the AI tier never
      // returns.
      final repo = ref.read(contentRepositoryProvider);
      final plain = await Future.wait([
        repo.searchChannelsByType(trimmed, 'movie', limit: 60),
        repo.searchChannelsByType(trimmed, 'series', limit: 60),
        repo.searchChannelsByType(trimmed, 'live', limit: 60),
      ]);
      if (!mounted || requestId != _searchRequestId) return;
      final gemini = ref.read(geminiServiceProvider);
      setState(() {
        _movieResults = plain[0];
        _seriesResults = plain[1];
        _liveResults = plain[2];
        _isSearching = false;
        // Show the "AI yorumluyor…" badge only when there's actually
        // an AI tier in flight.
        _aiRefining = gemini != null;
        _activeIntent = null;
        _curatorReasons = const {};
      });

      // Phase 2 — opportunistic AI enrichment. If the user has no
      // Gemini key, or the AI call fails/times out, plain results
      // stay on screen.
      if (gemini == null) return;
      final plainAll = [...plain[0], ...plain[1], ...plain[2]];
      final aiResults =
          await _runAiSearch(trimmed, requestId, gemini, plainAll);
      if (!mounted || requestId != _searchRequestId) {
        // Stale request — never leave the spinner stuck even when
        // we bail early.
        if (mounted) setState(() => _aiRefining = false);
        return;
      }
      if (aiResults == null) {
        setState(() => _aiRefining = false);
        return;
      }
      setState(() {
        _movieResults = aiResults.movies;
        _seriesResults = aiResults.series;
        _liveResults = aiResults.live;
        _activeIntent = aiResults.intent;
        _curatorReasons = aiResults.curatorReasons;
        _aiRefining = false;
      });
    });
  }

  /// AI-driven search.
  ///
  /// Returns `null` when the AI call(s) errored / timed out / had
  /// nothing useful to contribute — caller leaves the plain results
  /// on screen.
  ///
  /// Strategy (the bit that matters):
  ///   1. Parse the query to extract structured filters
  ///      (genre / cast / director / theme / type / year).
  ///   2. Build a **wide candidate pool** by union'ing:
  ///        - the plain LIKE hits the caller already produced,
  ///        - everything the parsed intent matches against the
  ///          full local library (e.g. all horror-genre rows for
  ///          "korku"),
  ///        - if the pool is still thin (< 30), a top-rated
  ///          cross-section so the curator always has something
  ///          to grade.
  ///      Cap at 150 entries for the curator's token budget.
  ///   3. Ask the curator to rank + annotate the top 15–25 picks
  ///      from that pool. The curator gets full metadata
  ///      (title/year/genre/cast/director/rating) so it can tell
  ///      "Korku Seansı = horror" apart from "Korkusuz = action",
  ///      something keyword LIKE physically can't.
  ///   4. Merge: curator picks first (with ✨ reasons), then
  ///      intent matches not yet seen, then any remaining plain
  ///      results. Plain set is never shrunk.
  ///
  /// 15-second timeout (was 8) — Gemini Flash 2.5 with a 150-item
  /// JSON sample legitimately runs 5–10 s in Turkey, and a longer
  /// budget is the difference between "AI does something useful"
  /// and "user sees no value".
  Future<_SearchResults?> _runAiSearch(
    String query,
    int requestId,
    GeminiService gemini,
    List<Channel> plainResults,
  ) async {
    final repo = ref.read(contentRepositoryProvider);
    final lang = _userLanguageCode();

    Future<R?> withTimeout<R>(Future<R?> f) =>
        f.timeout(const Duration(seconds: 15), onTimeout: () => null);

    // Step 1 — parse intent. Independent call so we can already
    // start building the candidate pool while it's in flight.
    final intentFuture = withTimeout(gemini.parseSearchQuery(query));

    // Pull genre-filtered matches once the parse lands. These are
    // typically the strongest signal for genre queries because they
    // hit the catalog's genre column directly (e.g. "Korku" rows in
    // a Turkish provider) without depending on name keywords.
    final intent = await intentFuture;
    if (requestId != _searchRequestId) return null;

    final hasIntent =
        intent != null && !intent.isEmpty && intent.hasStructuredFilters;
    final intentChannels = hasIntent
        ? await repo.searchChannelsByIntent(intent, limit: 200)
        : const <Channel>[];
    if (requestId != _searchRequestId) return null;

    // Step 2 — Build the candidate pool. Plain results stay
    // top-of-list because they're the strongest name-match signal
    // when the user is searching by title; intent matches widen
    // the net for genre/cast/director/theme; top-rated padding
    // ensures the pool isn't empty for purely thematic queries.
    final pool = <int, Channel>{};
    for (final ch in plainResults) {
      pool[ch.streamId] = ch;
    }
    for (final ch in intentChannels) {
      pool.putIfAbsent(ch.streamId, () => ch);
    }

    // Thematic queries (no exact name match, but the AI extracted
    // theme/genre keywords) need a *much* bigger cross-section so
    // the curator can recognise titles like "Train to Busan" for
    // "zombi filmleri" even when the catalog doesn't have the word
    // "zombi" anywhere. We previously sampled ~210 top-rated items
    // — for a 5–10k catalogue that's <3% of the library, which is
    // why thematic results felt thin.
    //
    // New strategy: when the pool is small, pad up to 800 with a
    // wide top-rated + recent-added stratification. The compact
    // serialisation below keeps the prompt under ~12 K tokens.
    final isThematic = plainResults.isEmpty &&
        intent != null &&
        ((intent.themeKeywords?.isNotEmpty ?? false) ||
            (intent.genres?.isNotEmpty ?? false));
    final padTarget = isThematic ? 800 : 60;
    if (pool.length < padTarget) {
      final pad = await repo.sampleLibraryForAi(
        moviesPerType: isThematic ? 320 : 35,
        seriesPerType: isThematic ? 320 : 35,
        livePerType: isThematic ? 80 : 15,
      );
      if (requestId != _searchRequestId) return null;
      for (final ch in pad) {
        pool.putIfAbsent(ch.streamId, () => ch);
      }
    }

    // Cap at 800 for the curator's prompt budget. Each row is
    // serialised in an ultra-compact `id|title|year|genre|director`
    // pipe-separated form (~60 bytes each) → 800 × 60 ≈ 48 KB ≈
    // 12 K tokens, well inside Gemini Flash's 1 M context with
    // headroom for the system prompt + query.
    final sampleEntries = pool.values.take(800).toList();
    if (sampleEntries.isEmpty) return null;

    // Compact format trades JSON keys (eight per item × 800 = 6.4 K
    // wasted tokens just on "streamId"/"title"/etc.) for a single
    // pipe-separated string with a leading legend line. AI parses
    // this fine and we fit ~4× more items into the same budget.
    String escape(String? s) =>
        (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
    final compactLines = <String>[
      'id|title|type|year|genre|director|cast|rating',
      for (final c in sampleEntries)
        '${c.streamId}|${escape(c.name)}|${c.type}|${escape(c.year)}|${escape(c.genre)}|${escape(c.director)}|${escape(c.cast)}|${c.rating?.toStringAsFixed(1) ?? ""}',
    ];
    final compactSample = [
      {'_format': 'pipe-separated rows', '_rows': compactLines}
    ];

    // Step 3 — Curator ranks + annotates.
    final curatorPicks = await withTimeout(gemini.curateLibraryByQuery(
      query: query,
      librarySample: compactSample,
      targetLanguage: lang,
    ));
    if (requestId != _searchRequestId) return null;

    final reasonByStreamId = <int, String>{};
    final curatorChannels = <Channel>[];
    if (curatorPicks != null) {
      for (final pick in curatorPicks) {
        final ch = pool[pick.streamId];
        if (ch == null) continue; // hallucinated id; drop
        reasonByStreamId[pick.streamId] = pick.reason;
        curatorChannels.add(ch);
      }
    }

    // Nothing AI could contribute on either front — leave plain
    // results on screen by returning null.
    if (!hasIntent && curatorChannels.isEmpty) return null;

    // Step 4 — Merge. Curator first, then intent matches the
    // curator didn't already include, then any plain hits still
    // unseen. The plain set is never shrunk; AI only reorders + adds
    // reasons.
    final seen = <int>{};
    final merged = <Channel>[];
    for (final ch in curatorChannels) {
      if (seen.add(ch.streamId)) merged.add(ch);
    }
    for (final ch in intentChannels) {
      if (seen.add(ch.streamId)) merged.add(ch);
    }
    for (final ch in plainResults) {
      if (seen.add(ch.streamId)) merged.add(ch);
    }

    final movies = <Channel>[];
    final series = <Channel>[];
    final live = <Channel>[];
    for (final ch in merged) {
      switch (ch.type) {
        case 'movie':
          movies.add(ch);
        case 'series':
          series.add(ch);
        case 'live':
          live.add(ch);
      }
    }
    return _SearchResults(
      movies: movies,
      series: series,
      live: live,
      intent: intent,
      curatorReasons: reasonByStreamId,
    );
  }

  /// User's UI language as an ISO-639-1 code — mirrors the same
  /// resolution rule the other AI surfaces use so Gemini replies in
  /// the language the rest of the app is rendering in.
  String _userLanguageCode() {
    final appLang = ref.read(settingsProvider).language;
    if (appLang == AppLanguage.system) {
      return Localizations.localeOf(context).languageCode;
    }
    return appLang.name;
  }

  void _onResultTap(Channel channel) {
    if (channel.type == 'live') {
      _playLive(channel);
    } else {
      // Set pending detail so the target screen opens the detail panel
      ref.read(pendingDetailChannelProvider.notifier).set(channel);

      // Navigate to the correct branch — this pops search and switches tab
      if (channel.type == 'movie') {
        context.go('/movies');
      } else if (channel.type == 'series') {
        context.go('/series');
      }
    }
  }

  /// Horizontal chip row of AI-generated refinement suggestions.
  /// Hidden when the user has no key, the query is too short, or
  /// Gemini hasn't returned anything yet. While loading, shows a
  /// slim spinner row so the user knows AI is on it without
  /// pushing the result grid down.
  Widget _buildSuggestionRow() {
    final hasAi = ref.watch(geminiServiceProvider) != null;
    if (!hasAi) return const SizedBox.shrink();
    final hasQuery = _controller.text.trim().length >= 2;
    if (!hasQuery) return const SizedBox.shrink();
    if (_aiSuggestions.isEmpty && !_loadingSuggestions) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: SizedBox(
        height: 36,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              if (_loadingSuggestions && _aiSuggestions.isEmpty) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Center(
                  child: Text(
                    AppLocalizations.of(context)!.searchSuggestLoading,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ] else
                for (final s in _aiSuggestions) ...[
                  _SuggestionChip(
                    label: s,
                    onTap: () {
                      _controller.text = s;
                      _controller.selection = TextSelection.collapsed(
                          offset: s.length);
                      _onSearchChanged(s);
                    },
                  ),
                  const SizedBox(width: 6),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildResultGrid(List<Channel> channels) {
    final isMobile = isMobilePlatform;
    final maxCross = isMobile ? 140.0 : 180.0;
    // Whether this section is the first non-empty results group —
    // only its top row gets the arrow-up → text bridge and the
    // stable _firstResultFocus node for the text→grid bridge.
    final isFirst = _isFirstSection(channels);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Match the column count GridView will compute for
        // SliverGridDelegateWithMaxCrossAxisExtent so we can mark
        // exactly the top-row indices.
        final cols = (constraints.maxWidth / maxCross).floor().clamp(1, 50);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCross,
            childAspectRatio: isMobile ? 0.60 : 0.65,
            crossAxisSpacing: isMobile ? 8 : 12,
            mainAxisSpacing: isMobile ? 8 : 12,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final ch = channels[index];
            return _SearchResultCard(
              channel: ch,
              onTap: () => _onResultTap(ch),
              // First section + index 0 → owns the stable focus node
              // for text→grid arrow-down bridge.
              focusNode:
                  (isFirst && index == 0) ? _firstResultFocus : null,
              // First section + top row → arrow-up goes to search
              // input. Subsequent sections' top rows let default
              // directional traversal find the previous section's
              // bottom row.
              onTopEdge: (isFirst && index < cols)
                  ? () => _textFocus.requestFocus()
                  : null,
              // Tier-3 curator picked this card — show the AI's
              // explanation under the poster.
              aiReason: _curatorReasons[ch.streamId],
            );
          },
        );
      },
    );
  }

  void _playLive(Channel channel) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    final quality = ref.read(settingsProvider).streamQuality;
    final url = (account.type == 'm3u' && channel.streamUrl != null && channel.streamUrl!.isNotEmpty)
        ? channel.streamUrl!
        : StreamUrlBuilder.live(account.url, account.username ?? '', account.password ?? '', channel.streamId, quality: quality);
    context.push('/player', extra: {
      'url': url,
      'title': channel.name,
      'type': VideoType.live,
      'logo': channel.streamIcon,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = isMobilePlatform;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Column(
            children: [
              // Search bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 12 : 20,
                  isMobile ? 10 : 16,
                  isMobile ? 12 : 20,
                  isMobile ? 8 : 12,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundDark,
                  border: Border(bottom: BorderSide(color: AppColors.borderDark)),
                ),
                child: Row(
                  children: [
                    // Back button — bigger touch target on mobile
                    _FocusableIconButton(
                      icon: Icons.arrow_back,
                      size: isMobile ? 44 : 36,
                      iconSize: isMobile ? 24 : 20,
                      onTap: _goBack,
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    // Search input
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _textFocus,
                        autofocus: true,
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) async {
                          // Record the (intentional) submission in
                          // search history so the chip row picks it
                          // up next time the user opens search. We
                          // only record on submit, not on every
                          // keystroke, otherwise the history fills
                          // with one-char prefixes.
                          final q = _controller.text.trim();
                          if (q.length >= 2) {
                            await ref
                                .read(searchHistoryRepositoryProvider)
                                .record(q);
                            // Invalidate the live providers so the chip
                            // row sees the new entry instantly.
                            ref.invalidate(recentSearchesProvider);
                            ref.invalidate(trendingSearchesProvider);
                          }
                          // Move focus to the first result. Goes
                          // through the same stable focus node the
                          // arrow-down bridge uses so the landing
                          // tile is identical between Enter and
                          // D-pad down.
                          if (_hasResults) _focusFirstResult();
                        },
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: isMobile ? 16 : 15,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.search,
                          hintStyle: const TextStyle(color: AppColors.textTertiaryDark),
                          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiaryDark, size: 20),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: AppColors.textTertiaryDark, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    _onSearchChanged('');
                                    _textFocus.requestFocus();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: isMobile ? 14 : 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // AI suggestion chips — appear below the search input
              // when the user is typing and Gemini has returned
              // refinement directions. Hidden entirely when there
              // are no suggestions, the user has no AI key, or the
              // query is too short. The chips fill the search field
              // on tap and re-fire the search pipeline.
              _buildSuggestionRow(),

              // Results — grouped by type
              Expanded(
                child: _isSearching
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : !_hasResults
                        // Plain search returned nothing. If AI is
                        // still in flight, show a "Düşünüyor…" panel
                        // instead of the "Kanal bulunamadı" empty
                        // state — otherwise the user gives up before
                        // the AI tier even gets a chance to surface
                        // results (a common case for thematic
                        // queries like "korku dizileri" where plain
                        // LIKE has nothing to grab onto).
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_aiRefining) ...[
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.primary),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    l10n.aiThinking,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ] else if (_controller.text.isEmpty) ...[
                                  // Recent + trending chip rows. Only
                                  // shown on the empty-query landing
                                  // state; when there's an active query
                                  // we want the user focused on results
                                  // and not distracted by history.
                                  _SearchHistoryPanel(
                                    onPick: (q) {
                                      _controller.text = q;
                                      _onSearchChanged(q);
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  EmptyState.search(
                                    title: l10n.search,
                                    fillParent: false,
                                  ),
                                ] else
                                  EmptyState.search(
                                    title: l10n.noChannels,
                                    subtitle:
                                        '"${_controller.text}" için sonuç bulunamadı. Farklı kelimeler dene veya AI asistana sor.',
                                    fillParent: false,
                                  ),
                              ],
                            ),
                          )
                        : Focus(
                            focusNode: _gridFocus,
                            skipTraversal: true,
                            child: ListView(
                              padding: EdgeInsets.all(isMobile ? 12 : 20),
                              children: [
                                // "AI yorumladı: …" chip row, only shown
                                // when the active query was routed
                                // through Gemini AND it produced at
                                // least one structured filter.
                                if (_activeIntent != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _AiIntentChips(intent: _activeIntent!),
                                  ),
                                // Header banner when curator actively
                                // ranked the top of the grid — gives
                                // the user a clear "AI did work for
                                // you" signal so the ✨ reasons on
                                // individual cards aren't easy to
                                // miss when scrolling.
                                if (_curatorReasons.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.auto_awesome,
                                                size: 12,
                                                color: AppColors.primary),
                                            const SizedBox(width: 5),
                                            Text(
                                              'AI tarafından sıralandı · ${_curatorReasons.length} öneri',
                                              style: const TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ]),
                                  ),
                                // While Tier 2/3 are still in flight,
                                // surface a small "AI yorumluyor…"
                                // badge above the plain results so
                                // the user knows further refinement
                                // is coming.
                                if (_aiRefining)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: Row(children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.aiThinking,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ]),
                                  ),
                                // Movies section
                                if (_movieResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.movie_outlined, l10n.movie, AppColors.primary, _movieResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_movieResults),
                                  const SizedBox(height: 24),
                                ],
                                // Series section
                                if (_seriesResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.tv_outlined, l10n.seriesLabel, AppColors.accent, _seriesResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_seriesResults),
                                  const SizedBox(height: 24),
                                ],
                                // Live TV section
                                if (_liveResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.live_tv_outlined, l10n.liveTV, Colors.red, _liveResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_liveResults),
                                ],
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Result Card
// =============================================================================

class _SearchResultCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final VoidCallback? onTopEdge;

  /// Optional AI-generated reason for why this item matched the
  /// current search. Non-null only when the Tier-3 library curator
  /// surfaced this card. Rendered in italic primary-colored text
  /// underneath the type badge.
  final String? aiReason;

  const _SearchResultCard({
    required this.channel,
    required this.onTap,
    this.focusNode,
    this.onTopEdge,
    this.aiReason,
  });

  @override
  State<_SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<_SearchResultCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isActive = _isFocused || _isHovered;
    final l10n = AppLocalizations.of(context)!;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // Top-row cells get an onTopEdge callback so D-pad up from
          // the top of the results lands on the search input instead
          // of doing nothing (no row above to traverse to).
          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
              widget.onTopEdge != null) {
            widget.onTopEdge!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: _isFocused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : isActive
                        ? Border.all(color: AppColors.borderDark, width: 1)
                        : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Poster
                  Expanded(
                    child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: ch.streamIcon!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _placeholderIcon(),
                          )
                        : _placeholderIcon(),
                  ),
                  // Info
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ch.name,
                          style: TextStyle(
                            color: isActive ? AppColors.textDark : AppColors.textSecondaryDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _typeColor(ch.type).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _typeLabel(ch.type, l10n),
                            style: TextStyle(
                              color: _typeColor(ch.type),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // Tier-3 curator reason — italic primary text
                        // right under the type badge. Only renders
                        // when the AI flagged this specific card as a
                        // semantic match.
                        if (widget.aiReason != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 9,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  widget.aiReason!,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 9.5,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: AppColors.surfaceElevatedDark,
      child: Center(
        child: Icon(Icons.tv, color: AppColors.textDisabledDark, size: 32),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'live':
        return Colors.red;
      case 'movie':
        return AppColors.primary;
      case 'series':
        return AppColors.accent;
      default:
        return AppColors.textTertiaryDark;
    }
  }

  String _typeLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'live':
        return l10n.live;
      case 'movie':
        return l10n.movie;
      case 'series':
        return l10n.seriesLabel;
      default:
        return type.toUpperCase();
    }
  }
}

// =============================================================================
// Focusable Icon Button
// =============================================================================

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _FocusableIconButton({
    required this.icon,
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
  });

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
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
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _isFocused ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Icon(
            widget.icon,
            color: _isFocused ? AppColors.primary : AppColors.textSecondaryDark,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}

/// Small read-only chip row that explains *why* the user got the
/// current result set when the active query was routed through
/// Gemini.
///
/// Renders one Material-style chip per structured field on the
/// intent — content type, each genre, year range, rating threshold.
/// The keywords field is intentionally omitted because the user
/// already sees what they typed in the search bar.
class _AiIntentChips extends StatelessWidget {
  final SearchIntent intent;

  const _AiIntentChips({required this.intent});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <Widget>[];

    if (intent.contentType != null) {
      final label = switch (intent.contentType) {
        'movie' => l10n.movie,
        'series' => l10n.series,
        'live' => l10n.live,
        _ => intent.contentType!,
      };
      chips.add(_chip(Icons.category_outlined, label));
    }

    final genres = intent.genres;
    if (genres != null && genres.isNotEmpty) {
      for (final g in genres) {
        chips.add(_chip(Icons.local_movies_outlined, g));
      }
    }

    if (intent.minYear != null || intent.maxYear != null) {
      final years = (intent.minYear != null && intent.maxYear != null)
          ? '${intent.minYear}–${intent.maxYear}'
          : (intent.minYear != null
              ? '${intent.minYear}+'
              : '≤${intent.maxYear}');
      chips.add(_chip(Icons.calendar_today_outlined, years));
    }

    if (intent.minRating != null) {
      chips.add(_chip(Icons.star_outline, '${intent.minRating}+'));
    }

    // Cast / director / theme keywords surface as named chips so the
    // user can see *why* their query matched. Different icons make
    // the three intents distinguishable at a glance.
    if (intent.castContains != null && intent.castContains!.isNotEmpty) {
      chips.add(_chip(Icons.person_outline, intent.castContains!));
    }
    if (intent.directorContains != null &&
        intent.directorContains!.isNotEmpty) {
      chips.add(_chip(Icons.movie_creation_outlined, intent.directorContains!));
    }
    final themes = intent.themeKeywords;
    if (themes != null && themes.isNotEmpty) {
      // Show only the first 1-2 theme keywords to avoid a chip-flood
      // when Gemini emits 5 multilingual synonyms ("kıyamet",
      // "apocalypse", "end of world", …) for one concept.
      for (final t in themes.take(2)) {
        chips.add(_chip(Icons.lightbulb_outline, t));
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.auto_awesome,
            size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: chips,
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}

/// Tuple of partitioned search results plus the optional intent that
/// produced them. File-private (leading underscore).
class _SearchResults {
  final List<Channel> movies;
  final List<Channel> series;
  final List<Channel> live;

  /// `null` when results came from plain SQL search; non-null when
  /// Gemini supplied structured filters that the repository used.
  /// Drives the "AI yorumladı: …" chip row in the UI.
  final SearchIntent? intent;

  /// Map of streamId → AI-generated reason text. Populated only when
  /// the Tier-3 library curator picked specific titles for this
  /// query. Result cards check this map and render the reason
  /// underneath the poster when their id is present.
  final Map<int, String> curatorReasons;

  const _SearchResults({
    required this.movies,
    required this.series,
    required this.live,
    required this.intent,
    required this.curatorReasons,
  });
}

/// Tappable AI-suggestion pill rendered in the chip row above the
/// search results. Tap fills the search field and re-fires the
/// pipeline — no separate handler needed.
class _SuggestionChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _hovered || _focused;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.22)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.35),
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Son aramalar" + "Popüler aramalar" chip rows shown on the search
/// landing state (empty query). Tap a chip to re-run that search,
/// long-press to remove it from history. The "Geçmişi temizle"
/// trailing button wipes both rows.
///
/// Two separate Riverpod providers (recentSearchesProvider +
/// trendingSearchesProvider) keep the two rows independent. Both
/// invalidate on every record() / remove() / clearAll() call so the
/// panel always reflects current state.
class _SearchHistoryPanel extends ConsumerWidget {
  final void Function(String query) onPick;

  const _SearchHistoryPanel({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final recent = ref.watch(recentSearchesProvider);
    final trending = ref.watch(trendingSearchesProvider);

    final recentList = recent.maybeWhen(
      data: (v) => v,
      orElse: () => const <String>[],
    );
    final trendingList = trending.maybeWhen(
      data: (v) => v,
      orElse: () => const <String>[],
    );

    if (recentList.isEmpty && trendingList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recentList.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 14, color: AppColors.textSecondaryDark),
                const SizedBox(width: 6),
                Text(
                  l10n.searchRecent,
                  style: const TextStyle(
                    color: AppColors.textSecondaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                // Trailing "Geçmişi temizle" — wipes everything.
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(searchHistoryRepositoryProvider)
                        .clearAll();
                    ref.invalidate(recentSearchesProvider);
                    ref.invalidate(trendingSearchesProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(l10n.searchHistoryCleared),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined,
                      size: 14, color: AppColors.textTertiaryDark),
                  label: Text(
                    l10n.searchClearHistory,
                    style: const TextStyle(
                      color: AppColors.textTertiaryDark,
                      fontSize: 11,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: recentList
                  .map((q) => _HistoryChip(
                        label: q,
                        icon: Icons.history_rounded,
                        onTap: () => onPick(q),
                        onRemove: () async {
                          await ref
                              .read(searchHistoryRepositoryProvider)
                              .remove(q);
                          ref.invalidate(recentSearchesProvider);
                          ref.invalidate(trendingSearchesProvider);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 18),
          ],
          if (trendingList.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  l10n.searchTrending,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: trendingList
                  .map((q) => _HistoryChip(
                        label: q,
                        icon: Icons.trending_up_rounded,
                        emphasised: true,
                        onTap: () => onPick(q),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single chip in the recent / trending row. Long-press calls
/// [onRemove] when provided — only the "recent" row exposes that
/// path (trending chips can't be removed individually; the user
/// can clear the whole history instead).
///
/// Focus / D-pad behaviour:
///   * Wrapped in a Focus widget so Android TV remote can D-pad onto
///     it, with visual feedback (thicker primary-coloured border +
///     subtle background bump on focus).
///   * select / enter key triggers [onTap].
///   * On D-pad-long-press there's no native equivalent, so [onRemove]
///     stays mouse / touch-long-press only — the user can clear the
///     whole history via the "Geçmişi temizle" button instead.
class _HistoryChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool emphasised;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _HistoryChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onRemove,
    this.emphasised = false,
  });

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.emphasised
        ? AppColors.primary
        : AppColors.textSecondaryDark;
    final bg = widget.emphasised
        ? AppColors.primary.withValues(alpha: 0.12)
        : AppColors.surfaceElevatedDark;
    final border = _focused
        ? AppColors.primary
        : (widget.emphasised
            ? AppColors.primary.withValues(alpha: 0.35)
            : AppColors.borderDark);
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
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onRemove,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _focused
                ? AppColors.primary.withValues(alpha: 0.18)
                : bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.emphasised ? color : AppColors.textDark,
                  fontSize: 12,
                  fontWeight:
                      widget.emphasised ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
