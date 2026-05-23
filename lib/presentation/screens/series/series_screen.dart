import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/presentation/widgets/ui/empty_state.dart';
import 'package:lifeostv/core/tv_focus/grid_screen_back_resolver.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_branches.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_provider.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_registry.dart';
import 'package:lifeostv/core/tv_focus/tv_poster_grid.dart';
import 'package:lifeostv/core/tv_focus/tv_poster_grid_controller.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/widgets/ai/cast_deep_dive_sheet.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/ai/ai_similar_section.dart';
import 'package:lifeostv/presentation/widgets/ai/plot_enriched_view.dart';
import 'package:lifeostv/presentation/widgets/ai/series_recap_inline.dart';
import 'package:lifeostv/presentation/widgets/content/backdrop_trailer.dart';
import 'package:lifeostv/presentation/widgets/content/expanded_trailer_dialog.dart';
import 'package:lifeostv/presentation/widgets/content/favorite_button.dart';
import 'package:lifeostv/presentation/widgets/content/search_dialog.dart';
import 'package:lifeostv/presentation/widgets/content/watchlist_button.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/utils/responsive.dart';
import 'package:lifeostv/utils/sort_mode.dart';
import 'package:lifeostv/utils/genre_filter.dart';
import 'package:lifeostv/utils/youtube_trailer.dart';
import 'package:lifeostv/presentation/widgets/content/sort_dropdown.dart';
import 'package:lifeostv/presentation/widgets/content/genre_dropdown.dart';

// ─── Special virtual category IDs ────────────────────────────────────────────
const _kFavoritesId = '__favorites__';
const _kHistoryId = '__history__';

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key});
  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedCategoryId;
  String _searchQuery = '';
  bool _categoriesCollapsed = isMobilePlatform;

  // Hero: hovered poster shows big hero (NO API call on hover)
  Channel? _hoveredChannel;

  // Detail
  Channel? _detailChannel;
  Map<String, dynamic>? _seriesInfo;
  bool _loadingDetail = false;
  int _activeSeason = 1;

  // Continue watching for series. Semantics:
  //  * `_lastEpisodeProgress` is the row we surfaced (latest by updatedAt).
  //  * `_lastEpisodeId` / `_lastEpisodeExt` / `_lastEpisodeLabel` describe
  //    the episode the resume button will play — NOT necessarily the
  //    episode `_lastEpisodeProgress` belongs to. If the latest watched
  //    episode was finished, we advance the button target to the next
  //    episode (with no resume position) so "Devam Et" actually moves
  //    the user forward instead of bouncing them back to a stale partial.
  //  * `_lastEpisodeResumeFromMs` is non-zero only when we're resuming
  //    mid-episode; for "play next" we keep it at 0.
  PlaybackProgressData? _lastEpisodeProgress;
  int? _lastEpisodeId;
  String? _lastEpisodeExt;
  String _lastEpisodeLabel = '';
  int _lastEpisodeResumeFromMs = 0;

  /// AI-generated mini-recaps for episodes whose `info.plot` is
  /// empty in the Xtream payload. Key shape: `"$season:$epNum"`.
  ///
  /// Populated lazily when the active season's episode panel
  /// renders — see [_fetchEpisodeAiSummariesForActiveSeason]. Cache
  /// survives only as long as the detail page is open; closing
  /// and reopening triggers a fresh fetch.
  final Map<String, String> _episodeAiSummaries = {};

  /// Seasons that have already been (or are currently being)
  /// summarised, to prevent duplicate Gemini calls when the user
  /// taps the same tab repeatedly.
  final Set<int> _episodeSummaryRequestedSeasons = {};

  // Focus scope for category sidebar (to receive focus when sidebar opens)
  final FocusScopeNode _categorySidebarScope = FocusScopeNode();
  // Focus node for detail view back button
  final FocusNode _detailBackFocusNode = FocusNode();
  // Focus node for detail view play button (primary action)
  final FocusNode _detailPlayFocusNode = FocusNode();

  /// Index-based D-pad navigation + lazy-mount-safe focus restore for
  /// the series poster grid. Outlives detail open/close so the
  /// previously focused streamId survives.
  final TvPosterGridController _gridController = TvPosterGridController();

  /// Stable closures for [TvFocusRegistry] register/unregister identity.
  late final VoidFocusCallback _branchPrimaryCb;
  VoidFocusCallback? _detailOverlayCb;

  @override
  void initState() {
    super.initState();
    _branchPrimaryCb = _focusGrid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _registerBackHandler();
      ref.read(tvFocusRegistryProvider).registerBranchPrimary(
            TvBranchIndex.series,
            _branchPrimaryCb,
          );
    });
  }

  @override
  void dispose() {
    ref.read(tvFocusRegistryProvider)
        .unregisterBranchPrimary(TvBranchIndex.series, _branchPrimaryCb);
    final overlay = _detailOverlayCb;
    if (overlay != null) {
      ref.read(tvFocusRegistryProvider).popOverlayPrimary(overlay);
    }
    _categorySidebarScope.dispose();
    _detailBackFocusNode.dispose();
    _detailPlayFocusNode.dispose();
    super.dispose();
  }

  /// Series back ladder — same shared resolver as Movies.
  ///
  /// detail → close
  /// grid → category panel (when open) → main sidebar → Dashboard / exit
  void _registerBackHandler() {
    ref.read(backHandlerProvider.notifier).set(() {
      final action = resolveGridScreenBackAction(
        detailOpen: _detailChannel != null,
        mainSidebarFocused:
            ref.read(tvFocusRegistryProvider).isMainSidebarFocused,
        categoriesCollapsed: _categoriesCollapsed,
        categoryScopeFocused: _categorySidebarScope.hasFocus,
      );
      switch (action) {
        case GridScreenBackAction.closeDetail:
          _closeDetail();
          return true;
        case GridScreenBackAction.bounceToCategory:
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _categorySidebarScope.requestFocus();
          });
          return true;
        case GridScreenBackAction.handToShell:
          return false;
      }
    });
  }

  void _openSearch(AppLocalizations l10n) async {
    final result = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) => SearchDialog(
          hintText: l10n.searchSeries,
          initialQuery: _searchQuery,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
    if (result != null && mounted) {
      setState(() => _searchQuery = result.toLowerCase());
    }
  }

  void _onPosterHover(Channel ch) {
    // Only update hovered channel for hero display - NO API call
    if (mounted) setState(() => _hoveredChannel = ch);
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  bool _hasSeriesDetailPayload(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return false;
    final info = _asStringKeyMap(raw['info']);
    final eps = raw['episodes'];

    var hasEpisodes = false;
    if (eps is Map) {
      for (final value in eps.values) {
        if (value is List && value.isNotEmpty) {
          hasEpisodes = true;
          break;
        }
      }
    } else if (eps is List) {
      hasEpisodes = eps.isNotEmpty;
    }

    final hasMeaningfulInfo =
        info != null &&
        ((info['plot']?.toString().isNotEmpty ?? false) ||
            (info['genre']?.toString().isNotEmpty ?? false) ||
            (info['cast']?.toString().isNotEmpty ?? false) ||
            (info['director']?.toString().isNotEmpty ?? false));

    return hasEpisodes || hasMeaningfulInfo;
  }

  Future<Map<String, dynamic>?> _fetchSeriesInfoWithFallback(
    Account acc,
    Channel base,
  ) async {
    final api = ref.read(xtreamApiServiceProvider);
    final primary = await api.getSeriesInfo(
      acc.url,
      acc.username ?? '',
      acc.password ?? '',
      base.streamId,
    );
    if (_hasSeriesDetailPayload(primary)) return primary;

    // Dashboard kaynaklı yanlış/boş streamId vakaları için isimden eşleşip tekrar dene.
    final candidates = await ref
        .read(contentRepositoryProvider)
        .searchChannelsByType(base.name, 'series', limit: 40);

    Channel? best;
    final normalized = base.name.trim().toLowerCase();
    for (final c in candidates) {
      if (c.streamId == base.streamId) continue;
      if (c.name.trim().toLowerCase() == normalized) {
        best = c;
        break;
      }
    }
    if (best == null) {
      for (final c in candidates) {
        if (c.streamId != base.streamId) {
          best = c;
          break;
        }
      }
    }
    if (best == null) return primary;

    final secondary = await api.getSeriesInfo(
      acc.url,
      acc.username ?? '',
      acc.password ?? '',
      best.streamId,
    );
    if (_hasSeriesDetailPayload(secondary)) {
      if (mounted) {
        setState(() => _detailChannel = best);
      }
      return secondary;
    }
    return primary ?? secondary;
  }

  /// Stable callback used for the registry overlay slot. Captured once
  /// in [_openDetail] so push/pop identity matches.
  void _focusDetailPlayCallback() {
    if (_detailPlayFocusNode.canRequestFocus) {
      _detailPlayFocusNode.requestFocus();
    }
  }

  void _openDetail(Channel ch) async {
    // Push the detail's primary action as the active overlay focus
    // target in the registry. Takes precedence over the grid for any
    // sidebar/back jump while the detail panel is open.
    final cb = _focusDetailPlayCallback;
    _detailOverlayCb = cb;
    ref.read(tvFocusRegistryProvider).pushOverlayPrimary(cb);
    _categorySidebarScope.canRequestFocus = false;
    final hasCachedInfo =
        ch.genre != null ||
        ch.plot != null ||
        ch.backdropPath != null ||
        ch.youtubeTrailer != null ||
        ch.director != null ||
        ch.cast != null;
    if (hasCachedInfo) {
      final cachedInfo = _buildBasicSeriesInfo(ch);
      setState(() {
        _detailChannel = ch;
        _loadingDetail = false;
        _seriesInfo = cachedInfo;
        _activeSeason = 1;
        _lastEpisodeProgress = null;
        _lastEpisodeId = null;
        _lastEpisodeExt = null;
        _lastEpisodeLabel = '';
        _lastEpisodeResumeFromMs = 0;
        _episodeAiSummaries.clear();
        _episodeSummaryRequestedSeasons.clear();
      });
      _focusDetailBackButton();
      _fetchLastEpisodeProgress(cachedInfo);
      _refreshDetailInBackground(ch);
      return;
    }

    setState(() {
      _detailChannel = ch;
      _loadingDetail = true;
      _seriesInfo = null;
      _activeSeason = 1;
      _lastEpisodeProgress = null;
      _lastEpisodeId = null;
      _lastEpisodeExt = null;
      _lastEpisodeLabel = '';
      _lastEpisodeResumeFromMs = 0;
      _episodeAiSummaries.clear();
      _episodeSummaryRequestedSeasons.clear();
    });
    _focusDetailBackButton();

    final acc =
        ref.read(currentAccountProvider).value ??
        await ref.read(currentAccountProvider.future);
    if (acc == null) {
      if (mounted) {
        setState(() {
          _seriesInfo = _buildBasicSeriesInfo(ch);
          _loadingDetail = false;
        });
      }
      return;
    }
    if (acc.type == 'm3u') {
      // M3U accounts don't have series API — show basic info
      if (mounted) {
        setState(() {
          _seriesInfo = _buildBasicSeriesInfo(ch);
          _loadingDetail = false;
        });
      }
      return;
    }
    try {
      final info = await _fetchSeriesInfoWithFallback(acc, ch);
      final resolvedInfo = info ?? _buildBasicSeriesInfo(ch);
      if (mounted) {
        final resolvedChannel = _detailChannel ?? ch;
        setState(() {
          _seriesInfo = resolvedInfo;
          _loadingDetail = false;
        });
        _cacheMetadata(resolvedChannel, resolvedInfo);
        _fetchLastEpisodeProgress(resolvedInfo);
        // Mark new episodes as seen now that user opened the series
        ref
            .read(contentRepositoryProvider)
            .markNewEpisodesSeen(resolvedChannel.streamId);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _seriesInfo ??= _buildBasicSeriesInfo(ch);
          _loadingDetail = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildBasicSeriesInfo(Channel ch) {
    return <String, dynamic>{
      'info': <String, dynamic>{
        'name': ch.name,
        'plot': ch.plot ?? '',
        'genre': ch.genre ?? '',
        'director': ch.director ?? '',
        'cast': ch.cast ?? '',
        'rating': ch.rating?.toStringAsFixed(1) ?? '',
        'youtube_trailer': ch.youtubeTrailer ?? '',
        if (ch.backdropPath != null) 'backdrop_path': [ch.backdropPath],
        if (ch.backdropPath != null) 'cover': ch.backdropPath,
        if (ch.streamIcon != null && ch.backdropPath == null)
          'cover': ch.streamIcon,
        if (ch.year != null) 'release_date': ch.year,
      },
      'episodes': <String, dynamic>{},
      'seasons': <dynamic>[],
    };
  }

  /// Silently refresh detail from API and update cache (no loading indicator)
  void _refreshDetailInBackground(Channel ch) async {
    final acc =
        ref.read(currentAccountProvider).value ??
        await ref.read(currentAccountProvider.future);
    if (acc == null || acc.type == 'm3u') return;
    try {
      final info = await _fetchSeriesInfoWithFallback(acc, ch);
      if (!mounted || info == null || _detailChannel == null) {
        return;
      }
      final current = _detailChannel!;
      final sameRequest =
          current.streamId == ch.streamId ||
          current.name.trim().toLowerCase() == ch.name.trim().toLowerCase();
      if (!sameRequest) return;
      setState(() => _seriesInfo = info);
      _cacheMetadata(current, info);
      _fetchLastEpisodeProgress(info);
      // First-open AI episode summaries for whichever season the
      // UI is parking on (initially S1, or whatever the season
      // resolver picked).
      _fetchEpisodeAiSummariesForActiveSeason();
      ref.read(contentRepositoryProvider).markNewEpisodesSeen(current.streamId);
    } catch (_) {}
  }

  /// Fetch progress for the "Devam Et" button.
  ///
  /// Strategy: ask the player repo for the most-recently-touched
  /// progress row across this series' episodes (any state — finished
  /// or not). Then decide what the button should do:
  ///   * If the latest row is **unfinished**, resume it mid-episode.
  ///   * If the latest row is **finished**, advance to the next
  ///     episode in season/ep-number order with start-position 0.
  ///   * If the latest row is finished and there's no next episode,
  ///     hide the button (no `_lastEpisodeId`).
  ///
  /// This fixes the case where a stale partially-watched episode (say
  /// S1E5) would surface even after the user had finished S1E6–E9.
  Future<void> _fetchLastEpisodeProgress(
    Map<String, dynamic>? seriesInfo,
  ) async {
    if (seriesInfo == null) return;

    // Use the same sort order as next/prev episode navigation so the
    // "play next" advance is consistent with what auto-advance does.
    final allEpsSorted = _getAllEpisodesSorted();
    if (allEpsSorted.isEmpty) return;

    // Project to a typed view of (id, season, epNum, ext) so the
    // lookups below are clearer than reaching into dynamic maps.
    final allEpisodes = <({int id, String season, String epNum, String ext})>[];
    for (final epMap in allEpsSorted) {
      final id = _episodeIdOf(epMap);
      if (id <= 0) continue;
      allEpisodes.add((
        id: id,
        season: epMap['_season']?.toString() ?? '1',
        epNum: epMap['episode_num']?.toString() ?? '',
        ext: epMap['container_extension']?.toString() ?? 'mp4',
      ));
    }
    if (allEpisodes.isEmpty) return;

    try {
      final progress = await ref
          .read(playerRepositoryProvider)
          .getLatestSeriesProgress(allEpisodes.map((e) => e.id).toList());
      if (progress == null || !mounted) return;

      // Where does this progress sit in the sorted list?
      final lastIdx = allEpisodes.indexWhere((e) => e.id == progress.streamId);
      if (lastIdx == -1) return; // progress row is for an episode we no longer see

      final last = allEpisodes[lastIdx];

      if (progress.isFinished) {
        // Episode complete — propose the next one if there is one.
        if (lastIdx + 1 >= allEpisodes.length) {
          // Already at the season finale; surface nothing so the UI
          // falls back to a plain "Play" of the first available episode.
          return;
        }
        final next = allEpisodes[lastIdx + 1];
        setState(() {
          _lastEpisodeProgress = progress;
          _lastEpisodeId = next.id;
          _lastEpisodeExt = next.ext;
          _lastEpisodeLabel = 'S${next.season}E${next.epNum}';
          _lastEpisodeResumeFromMs = 0;
        });
      } else {
        // Mid-episode — resume from where we left off.
        setState(() {
          _lastEpisodeProgress = progress;
          _lastEpisodeId = last.id;
          _lastEpisodeExt = last.ext;
          _lastEpisodeLabel = 'S${last.season}E${last.epNum}';
          _lastEpisodeResumeFromMs = progress.position;
        });
      }
    } catch (_) {}
  }

  /// Resolve the user's UI locale to an ISO-639-1 language code so
  /// Gemini's reply matches whatever the rest of the app is
  /// rendering in.
  String _userLanguageCode() {
    final appLang = ref.read(settingsProvider).language;
    if (appLang == AppLanguage.system) {
      return Localizations.localeOf(context).languageCode;
    }
    return appLang.name;
  }

  /// Fire-and-forget batch fetch of AI-generated mini-recaps for
  /// the active season's episodes — but only the ones whose Xtream
  /// `info.plot` field is empty. We never override real metadata;
  /// the AI fill-in is purely a gap filler.
  ///
  /// Called from the season picker handler (each tap on a tab) and
  /// from `_fetchLastEpisodeProgress` once `_seriesInfo` is
  /// populated. Guarded by `_episodeSummaryRequestedSeasons` so the
  /// same season never gets fetched twice in one detail-page open.
  Future<void> _fetchEpisodeAiSummariesForActiveSeason() async {
    final ch = _detailChannel;
    if (ch == null) return;
    final season = _activeSeason;
    if (_episodeSummaryRequestedSeasons.contains(season)) return;

    // Cheap pre-check: only spend Gemini calls when there's
    // actually nothing to fill in for this season.
    final epsRaw = _seriesInfo?['episodes'];
    final eps = _asStringKeyMap(epsRaw);
    if (eps == null) return;
    final seasonList = eps['$season'] is List
        ? eps['$season'] as List
        : <dynamic>[];
    final missing = <int>[];
    for (final raw in seasonList) {
      final epMap = _asStringKeyMap(raw);
      if (epMap == null) continue;
      final epPlot =
          (_asStringKeyMap(epMap['info'])?['plot']?.toString() ?? '')
              .trim();
      if (epPlot.isNotEmpty) continue; // Xtream gave us real text — skip
      final epNum = int.tryParse(epMap['episode_num']?.toString() ?? '');
      if (epNum != null) missing.add(epNum);
    }
    if (missing.isEmpty) return;

    // Only round-trip Gemini if we actually have a key. Don't
    // mark the season as "requested" when AI is off, so toggling
    // the key on mid-session can trigger a fetch on the next
    // season switch.
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) return;
    _episodeSummaryRequestedSeasons.add(season);

    final result = await gemini.summarizeEpisodes(
      seriesTitle: ch.name,
      seriesYear: ch.year,
      seriesGenre: ch.genre,
      season: season,
      episodeNumbers: missing,
      targetLanguage: _userLanguageCode(),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      for (final entry in result.entries) {
        _episodeAiSummaries['$season:${entry.key}'] = entry.value;
      }
    });
  }

  void _cacheMetadata(Channel ch, Map<String, dynamic>? seriesInfo) {
    if (seriesInfo == null) return;
    final infoRaw = seriesInfo['info'];
    final info = _asStringKeyMap(infoRaw);
    if (info == null) return;
    String? backdrop;
    if (info['backdrop_path'] is List &&
        (info['backdrop_path'] as List).isNotEmpty) {
      backdrop = info['backdrop_path'][0]?.toString();
    } else if (info['cover'] != null && info['cover'].toString().isNotEmpty) {
      backdrop = info['cover'].toString();
    }
    final trailer = _extractTrailerUrl(info, raw: seriesInfo);
    final genre = info['genre']?.toString();
    final plot = info['plot']?.toString() ?? info['description']?.toString();
    final director = info['director']?.toString();
    final castInfo = info['cast']?.toString();
    // Cache all metadata to DB (serve from cache next time, no API call needed)
    if (backdrop != null ||
        (trailer != null && trailer.isNotEmpty) ||
        (genre != null && genre.isNotEmpty) ||
        (plot != null && plot.isNotEmpty) ||
        (director != null && director.isNotEmpty) ||
        (castInfo != null && castInfo.isNotEmpty)) {
      ref
          .read(contentRepositoryProvider)
          .updateChannelMetadata(
            ch.streamId,
            'series',
            backdropPath: backdrop,
            youtubeTrailer: (trailer != null && trailer.isNotEmpty)
                ? trailer
                : null,
            genre: (genre != null && genre.isNotEmpty) ? genre : null,
            plot: (plot != null && plot.isNotEmpty) ? plot : null,
            director: (director != null && director.isNotEmpty)
                ? director
                : null,
            castInfo: (castInfo != null && castInfo.isNotEmpty)
                ? castInfo
                : null,
          );
    }
  }

  /// Read an episode's `id` field defensively. Xtream API normally
  /// returns int, but some providers ship strings ("123") or even
  /// non-numeric junk in malformed responses. Returns -1 as the
  /// "couldn't parse" sentinel; callers skip episodes with -1
  /// instead of pushing /player with a bogus id.
  static int _episodeIdOf(Map<String, dynamic> ep) {
    final raw = ep['id'];
    if (raw is int) return raw;
    if (raw == null) return -1;
    return int.tryParse(raw.toString()) ?? -1;
  }

  /// Build a flat list of all episodes across all seasons (sorted by season → episode)
  List<Map<String, dynamic>> _getAllEpisodesSorted() {
    final epsRaw2 = _seriesInfo?['episodes'];
    final eps = _asStringKeyMap(epsRaw2);
    if (eps == null) return [];

    final allEps = <Map<String, dynamic>>[];
    final seasonNums = eps.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    for (final season in seasonNums) {
      final seasonEpsRaw = eps[season];
      final seasonEps = seasonEpsRaw is List ? seasonEpsRaw : <dynamic>[];
      for (final ep in seasonEps) {
        final epMap = _asStringKeyMap(ep);
        if (epMap != null) {
          allEps.add({...epMap, '_season': season});
        }
      }
    }
    return allEps;
  }

  void _playEpisode(int epId, String ext, {Duration? startPosition}) {
    _playEpisodeInternal(epId, ext, startPosition: startPosition);
  }

  Future<void> _playEpisodeInternal(
    int epId,
    String ext, {
    Duration? startPosition,
  }) async {
    final acc =
        ref.read(currentAccountProvider).value ??
        await ref.read(currentAccountProvider.future);
    if (acc == null) return;
    if (!mounted) return;

    // Extract series metadata for pause info badge
    final infoRaw2 = _seriesInfo?['info'];
    final info = _asStringKeyMap(infoRaw2);
    final ratingStr =
        info?['rating']?.toString() ??
        _detailChannel?.rating?.toStringAsFixed(1);
    final ratingVal = ratingStr != null ? double.tryParse(ratingStr) : null;

    // Build flat episode list for next/prev navigation
    final allEpisodes = _getAllEpisodesSorted();
    final currentIdx = allEpisodes.indexWhere((ep) {
      final id = _episodeIdOf(ep);
      return id == epId;
    });

    // Derive an "S1E5 • Episode title" label for the player chrome so
    // the user can actually tell which episode they're watching. Falls
    // back to just the series name if we can't locate the episode
    // (corrupt Xtream payload, race against a series refresh, etc.).
    final seriesName = _detailChannel?.name ?? '';
    String fullTitle = seriesName;
    if (currentIdx >= 0) {
      final curEp = allEpisodes[currentIdx];
      final curSeason = curEp['_season']?.toString() ?? '';
      final curEpNum = curEp['episode_num']?.toString() ?? '';
      final curEpName = curEp['title']?.toString().trim() ?? '';
      final sxe =
          (curSeason.isNotEmpty && curEpNum.isNotEmpty) ? 'S${curSeason}E$curEpNum' : '';
      final parts = <String>[
        if (seriesName.isNotEmpty) seriesName,
        if (sxe.isNotEmpty) sxe,
        if (curEpName.isNotEmpty && curEpName != seriesName) curEpName,
      ];
      fullTitle = parts.join(' • ');
    }

    // Find next episode info — skip the "next" link entirely if the
    // candidate episode has no parseable id (corrupted Xtream JSON)
    // rather than pushing /player with a bogus id that yields 404.
    String? nextEpTitle;
    VoidCallback? onNextEp;
    if (currentIdx >= 0 && currentIdx < allEpisodes.length - 1) {
      final nextEp = allEpisodes[currentIdx + 1];
      final nextId = _episodeIdOf(nextEp);
      if (nextId != -1) {
        final nextExt = nextEp['container_extension']?.toString() ?? 'mp4';
        final nextNum = nextEp['episode_num']?.toString() ?? '';
        final nextSeason = nextEp['_season']?.toString() ?? '';
        nextEpTitle = 'S${nextSeason}E$nextNum ${nextEp['title'] ?? ''}';
        onNextEp = () async {
          // Pop current player, then wait briefly so its native media_kit
          // resources (SurfaceTexture, decoder) are fully released before
          // the next Player is created. Pushing immediately on Android can
          // leave two live Players contending for GPU/decoder slots.
          if (context.canPop()) context.pop();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;
          _playEpisode(nextId, nextExt);
        };
      }
    }

    // Find previous episode callback — same guard.
    VoidCallback? onPrevEp;
    if (currentIdx > 0) {
      final prevEp = allEpisodes[currentIdx - 1];
      final prevId = _episodeIdOf(prevEp);
      if (prevId != -1) {
        final prevExt = prevEp['container_extension']?.toString() ?? 'mp4';
        onPrevEp = () async {
          if (context.canPop()) context.pop();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;
          _playEpisode(prevId, prevExt);
        };
      }
    }

    context.push(
      '/player',
      extra: {
        'url':
            '${acc.url}/series/${acc.username}/${acc.password}/$epId.${ext.isNotEmpty ? ext : 'mp4'}',
        'title': fullTitle,
        'type': VideoType.series,
        'logo': _detailChannel?.streamIcon,
        'startPosition': startPosition,
        'parentStreamId': _detailChannel?.streamId,
        'introDefaultSeconds':
            ref.read(settingsProvider).introSkipDefaultSeconds,
        'plot': info?['plot'] ?? _detailChannel?.plot,
        'genre': info?['genre'] ?? _detailChannel?.genre,
        'year':
            info?['releaseDate']?.toString().split('-').firstOrNull ??
            _detailChannel?.year,
        'director': info?['director'] ?? _detailChannel?.director,
        'cast': info?['cast'] ?? _detailChannel?.cast,
        'rating': ratingVal,
        'nextEpisodeTitle': nextEpTitle,
        'onNextEpisode': onNextEp,
        'onPrevEpisode': onPrevEp,
      },
    );
  }

  void _closeDetail() {
    setState(() {
      _detailChannel = null;
      _seriesInfo = null;
    });
    final overlay = _detailOverlayCb;
    if (overlay != null) {
      ref.read(tvFocusRegistryProvider).popOverlayPrimary(overlay);
      _detailOverlayCb = null;
    }
    _categorySidebarScope.canRequestFocus = true;
    // Restore focus to the previously focused poster — only on
    // desktop/TV. On mobile, Offstage preserves scroll position;
    // imperatively requesting focus would scroll the grid.
    if (!isMobilePlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridController.focusCurrentOrFirst();
      });
    }
  }

  /// Select category (sidebar stays open, user closes via toggle button)
  void _selectCategory(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
  }

  /// Toggle category sidebar open/closed
  void _toggleCategorySidebar() {
    if (isMobilePlatform) {
      _showCategoryBottomSheet();
      return;
    }
    setState(() => _categoriesCollapsed = !_categoriesCollapsed);
    if (_categoriesCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridController.focusCurrentOrFirst();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _categorySidebarScope.requestFocus();
      });
    }
  }

  void _showCategoryBottomSheet() {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.read(_seriesCatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark
          ? AppColors.surfaceElevated(context)
          : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textTertiary(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.tv_outlined, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.categories,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? AppColors.text(context) : AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildMobileCatTile(
                    '⭐ ${l10n.myFavorites}',
                    _selectedCategoryId == _kFavoritesId,
                    () {
                      Navigator.pop(ctx);
                      _selectCategory(_kFavoritesId);
                    },
                  ),
                  _buildMobileCatTile(
                    '📺 ${l10n.watchHistory}',
                    _selectedCategoryId == _kHistoryId,
                    () {
                      Navigator.pop(ctx);
                      _selectCategory(_kHistoryId);
                    },
                  ),
                  _buildMobileCatTile(
                    l10n.allSeries,
                    _selectedCategoryId == null,
                    () {
                      Navigator.pop(ctx);
                      _selectCategory(null);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ...categoriesAsync.when(
                    data: (cats) => cats.map(
                      (cat) => _buildMobileCatTile(
                        cat.name,
                        cat.id == _selectedCategoryId,
                        () {
                          Navigator.pop(ctx);
                          _selectCategory(cat.id);
                        },
                      ),
                    ),
                    loading: () => [
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ],
                    error: (e, _) => [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('$e'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileCatTile(String name, bool isSelected, VoidCallback onTap) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedColor: AppColors.primary,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
      leading: isSelected
          ? const Icon(Icons.check_circle, size: 18)
          : Icon(
              Icons.circle_outlined,
              size: 18,
              color: AppColors.textTertiary(context),
            ),
      title: Text(
        name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      onTap: onTap,
    );
  }

  /// Move focus to the poster grid via the controller (D-pad right
  /// from category sidebar / right-arrow from main sidebar via
  /// registry). Prefers the previously focused poster.
  void _focusGrid() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gridController.focusCurrentOrFirst();
    });
  }

  /// Open category sidebar (called from grid left edge D-pad)
  void _openCategorySidebar() {
    if (!_categoriesCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _categorySidebarScope.requestFocus();
      });
      return;
    }
    _toggleCategorySidebar();
  }

  /// Focus the detail view play button (primary action for better TV UX)
  void _focusDetailBackButton() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusDetailPlayCallback();
    });
  }

  /// Focus the main AppSidebar via [TvFocusRegistry] — the sidebar
  /// lives in a sibling subtree under StatefulShellRoute.indexedStack
  /// so findAncestorStateOfType could not reach it.
  void _focusMainSidebar() {
    final ok = ref.read(tvFocusRegistryProvider).requestMainSidebar();
    if (!ok) {
      // First-frame fallback before the sidebar finished registering.
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.left);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for pending detail from dashboard navigation
    final pendingChannel = ref.watch(pendingDetailChannelProvider);
    if (pendingChannel != null &&
        pendingChannel.type == 'series' &&
        _detailChannel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detailChannel == null) {
          ref.read(pendingDetailChannelProvider.notifier).clear();
          _openDetail(pendingChannel);
        }
      });
    }

    final categoriesAsync = ref.watch(_seriesCatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final showDetail = _detailChannel != null;

    return Scaffold(
      body: Stack(
        children: [
          // Keep the list alive behind detail view so scroll position is preserved
          Offstage(
            offstage: showDetail,
            child: isMobilePlatform
                ? _buildContentArea(isDark, l10n)
                : Row(
                    children: [
                      _buildCategoriesPanel(categoriesAsync, isDark, l10n),
                      Expanded(child: _buildContentArea(isDark, l10n)),
                    ],
                  ),
          ),
          if (showDetail)
            PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _closeDetail();
              },
              child: FocusScope(
                autofocus: true,
                child: _buildDetailView(isDark, l10n),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel(
    AsyncValue<List<Category>> categoriesAsync,
    bool isDark,
    AppLocalizations l10n,
  ) {
    // Fully hidden when collapsed — content takes full width
    if (_categoriesCollapsed) {
      return const SizedBox.shrink();
    }

    return FocusScope(
      node: _categorySidebarScope,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isDark ? AppColors.background(context) : AppColors.backgroundLight,
          border: Border(
            right: BorderSide(
              color: isDark ? AppColors.border(context) : AppColors.borderLight,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.tv_outlined, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.series,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? AppColors.text(context) : AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            // ⭐ Favorites
            _buildCatItem(
              '⭐ ${l10n.myFavorites}',
              _selectedCategoryId == _kFavoritesId,
              () => _selectCategory(_kFavoritesId),
              isDark,
            ),
            // 📺 History
            _buildCatItem(
              '📺 ${l10n.watchHistory}',
              _selectedCategoryId == _kHistoryId,
              () => _selectCategory(_kHistoryId),
              isDark,
            ),
            // All series
            _buildCatItem(
              l10n.allSeries,
              _selectedCategoryId == null,
              () => _selectCategory(null),
              isDark,
            ),
            Divider(
              color: isDark ? AppColors.border(context) : AppColors.borderLight,
              height: 1,
              indent: 12,
              endIndent: 12,
            ),
            Expanded(
              child: categoriesAsync.when(
                data: (cats) => ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: cats.length,
                  itemBuilder: (_, i) => _buildCatItem(
                    cats[i].name,
                    cats[i].id == _selectedCategoryId,
                    () => _selectCategory(cats[i].id),
                    isDark,
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    '$e',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatItem(
    String name,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: _FocusableCatItem(
        name: name,
        isSelected: isSelected,
        isDark: isDark,
        onTap: onTap,
        onRightPressed: _focusGrid,
        onLeftPressed: _focusMainSidebar,
      ),
    );
  }

  Widget _buildContentArea(bool isDark, AppLocalizations l10n) {
    // No parent Focus wrapper — the poster grid items own their own
    // FocusNodes via TvPosterGrid. A parent Focus would intercept D-pad
    // before the items could handle row/column math.
    return Column(
        children: [
          // Hero banner (Tauri style: backdrop + info)
          if (_hoveredChannel != null &&
              (_hoveredChannel!.backdropPath ?? _hoveredChannel!.streamIcon) !=
                  null)
            _buildHeroBanner(_hoveredChannel!, isDark, l10n)
          else
            const SizedBox(height: 8),
          // Search bar + back-to-categories button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                // Toggle category sidebar open/close
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FocusableIconButton(
                    icon: _categoriesCollapsed ? Icons.menu : Icons.menu_open,
                    tooltip: l10n.categories,
                    onTap: _toggleCategorySidebar,
                  ),
                ),
                Expanded(
                  child: _SearchButton(
                    hintText: _searchQuery.isNotEmpty
                        ? _searchQuery
                        : l10n.searchSeries,
                    isActive: _searchQuery.isNotEmpty,
                    onTap: () => _openSearch(l10n),
                    onClear: _searchQuery.isNotEmpty
                        ? () => setState(() => _searchQuery = '')
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                // Genre filter (only renders when there are genres in DB)
                Consumer(
                  builder: (context, ref, _) {
                    final all = ref.watch(_allSeriesProvider).value ?? const [];
                    return GenreDropdown(
                      value: ref.watch(seriesGenreFilterProvider),
                      genres: extractGenres(all),
                      onChanged: (g) =>
                          ref.read(seriesGenreFilterProvider.notifier).set(g),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Sort picker (newest / rating / name)
                Consumer(
                  builder: (context, ref, _) => SortDropdown(
                    value: ref.watch(seriesSortModeProvider),
                    onChanged: (m) =>
                        ref.read(seriesSortModeProvider.notifier).set(m),
                  ),
                ),
              ],
            ),
          ),
          // Grid
          Expanded(child: _buildGrid(l10n)),
        ],
      );
  }

  Widget _buildGrid(AppLocalizations l10n) {
    if (_selectedCategoryId == _kFavoritesId) {
      return _FavoritesGridView(
        gridController: _gridController,
        searchQuery: _searchQuery,
        onHover: _onPosterHover,
        onTap: _openDetail,
        onLeftEdge: _openCategorySidebar,
        l10n: l10n,
      );
    }
    if (_selectedCategoryId == _kHistoryId) {
      return _HistoryGridView(
        gridController: _gridController,
        searchQuery: _searchQuery,
        onHover: _onPosterHover,
        onTap: _openDetail,
        onLeftEdge: _openCategorySidebar,
        l10n: l10n,
      );
    }
    if (_selectedCategoryId != null) {
      return _SeriesGridView(
        gridController: _gridController,
        categoryId: _selectedCategoryId!,
        searchQuery: _searchQuery,
        onHover: _onPosterHover,
        onTap: _openDetail,
        onLeftEdge: _openCategorySidebar,
        l10n: l10n,
      );
    }
    return _AllSeriesGridView(
      gridController: _gridController,
      searchQuery: _searchQuery,
      onHover: _onPosterHover,
      onTap: _openDetail,
      onLeftEdge: _openCategorySidebar,
      l10n: l10n,
    );
  }

  Widget _buildHeroBanner(Channel ch, bool isDark, AppLocalizations l10n) {
    final hasBackdrop = ch.backdropPath != null;
    final imgUrl = hasBackdrop ? ch.backdropPath! : ch.streamIcon;

    return GestureDetector(
      onTap: () => _openDetail(ch),
      child: SizedBox(
        height: isMobilePlatform ? 200 : 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imgUrl != null)
              CachedNetworkImage(
                imageUrl: imgUrl,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.3),
                errorWidget: (_, _, _) =>
                    Container(color: AppColors.surface(context)),
              ),
            // Left gradient (lighter to show more poster)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.background(context).withValues(alpha: 0.85),
                    AppColors.background(context).withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 0.7],
                ),
              ),
            ),
            // Bottom gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.background(context),
                    AppColors.background(context).withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.2, 0.5],
                ),
              ),
            ),
            // Content
            Positioned(
              left: 24,
              bottom: 20,
              right: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.seriesLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (ch.rating != null && ch.rating! > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: AppColors.gold,
                                size: 12,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                ch.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (ch.year != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ch.year!,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ch.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ch.genre != null && ch.genre!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: ch.genre!
                          .split(',')
                          .take(4)
                          .map(
                            (g) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Text(
                                g.trim(),
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (ch.plot != null && ch.plot!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ch.plot!.length > 150
                          ? '${ch.plot!.substring(0, 150)}...'
                          : ch.plot!,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openDetail(ch),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: Text(l10n.details),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                        ),
                      ),
                      if (ch.youtubeTrailer != null &&
                          ch.youtubeTrailer!.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            final tid = ch.youtubeTrailer!;
                            final url = tid.startsWith('http')
                                ? tid
                                : 'https://www.youtube.com/watch?v=$tid';
                            launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.play_circle_outline, size: 16),
                          label: Text(l10n.trailer),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Mini poster (bottom right)
            if (ch.streamIcon != null && hasBackdrop)
              Positioned(
                right: 24,
                bottom: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: ch.streamIcon!,
                    width: 100,
                    height: 150,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Detail View ──────────────────────────────────────────────────────────

  Widget _buildDetailView(bool isDark, AppLocalizations l10n) {
    final ch = _detailChannel!;
    final infoRaw = _seriesInfo?['info'];
    final info = _asStringKeyMap(infoRaw);
    final epsRaw = _seriesInfo?['episodes'];
    final eps = _asStringKeyMap(epsRaw);
    final title = info?['name'] ?? ch.name;
    final plot = info?['plot'] ?? '';
    final cast = info?['cast'] ?? '';
    final director = info?['director'] ?? '';
    final genre = info?['genre'] ?? '';
    final rating = info?['rating'] ?? ch.rating?.toStringAsFixed(1) ?? '';
    // Server / DB cache first; if neither has a real URL fall back to a
    // YouTube search query so every series has a working trailer button.
    final trailerUrl = _extractTrailerUrl(
          info,
          fallback: ch.youtubeTrailer,
          raw: _seriesInfo,
        ) ??
        youtubeSearchTrailerUrl(ch.name, year: ch.year);
    final backdrop =
        (info?['backdrop_path'] is List &&
            (info!['backdrop_path'] as List).isNotEmpty)
        ? info['backdrop_path'][0]
        : info?['cover'] ?? ch.backdropPath ?? ch.streamIcon ?? '';
    final seasonNums = eps?.keys.toList() ?? [];
    seasonNums.sort(
      (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
    );
    if (seasonNums.isNotEmpty &&
        !seasonNums.contains(_activeSeason.toString())) {
      _activeSeason = int.tryParse(seasonNums.first) ?? 1;
    }
    final activeEpsRaw = eps?[_activeSeason.toString()];
    final activeEpisodes = activeEpsRaw is List ? activeEpsRaw : <dynamic>[];
    final favIds = ref
        .watch(_favSeriesIdsProvider)
        .when(
          data: (v) => v,
          loading: () => const <int>[],
          error: (_, _) => const <int>[],
        );
    final favoriteSeries = favIds.isEmpty
        ? const <Channel>[]
        : ref
              .watch(_favChannelsProvider(favIds))
              .when(
                data: (v) => v,
                loading: () => const <Channel>[],
                error: (_, _) => const <Channel>[],
              );
    final historySeries = ref
        .watch(_continueWatchingSeriesProvider)
        .when(
          data: (v) => v,
          loading: () => const <Channel>[],
          error: (_, _) => const <Channel>[],
        );
    final allSeriesAsync = ref.watch(_allSeriesProvider);
    final similarSeries = allSeriesAsync.when(
      data: (all) => _selectSimilarContent(
        current: ch,
        all: all,
        genreText: genre.toString().isNotEmpty ? genre.toString() : ch.genre,
        baseDirector: director.toString().isNotEmpty
            ? director.toString()
            : ch.director,
        baseCast: cast.toString().isNotEmpty ? cast.toString() : ch.cast,
        basePlot: plot.toString().isNotEmpty ? plot.toString() : ch.plot,
        personalizationSeed: [...favoriteSeries, ...historySeries],
      ),
      loading: () => const <Channel>[],
      error: (_, _) => const <Channel>[],
    );

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Stack(
        children: [
          // Static backdrop fills the page as the base visual layer.
          Positioned.fill(
            child: backdrop.toString().isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: backdrop.toString(),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: Colors.black),
                  )
                : const ColoredBox(color: Colors.black),
          ),
          // Gradients
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.background(context).withValues(alpha: 0.6),
                    AppColors.background(context),
                  ],
                  stops: const [0.0, 0.35, 0.65],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.background(context).withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
          ),

          // Back button + Favorite button
          Positioned(
            top: 16,
            left: 16,
            child: _FocusableActionButton(
              icon: Icons.arrow_back,
              label: '',
              isPrimary: false,
              backgroundColor: Colors.black45,
              onTap: _closeDetail,
              focusNode: _detailBackFocusNode,
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WatchlistButton(
                  streamId: ch.streamId,
                  type: 'series',
                  name: ch.name,
                  thumbnail: ch.streamIcon,
                ),
                const SizedBox(width: 8),
                FavoriteButton(
                  streamId: ch.streamId,
                  type: 'series',
                  name: ch.name,
                  thumbnail: ch.streamIcon,
                ),
              ],
            ),
          ),

          // Content
          Positioned(
            left: isMobilePlatform ? 16 : 40,
            top: isMobilePlatform ? 56 : 80,
            right: isMobilePlatform ? 16 : 40,
            bottom: 0,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // On narrow/portrait screens stack poster on top of info.
                  // On wider screens keep the side-by-side layout.
                  Builder(builder: (context) {
                    Widget buildPoster(double w, double h) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 40,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ch.streamIcon != null
                              ? CachedNetworkImage(
                                  imageUrl: ch.streamIcon!,
                                  width: w,
                                  height: h,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => Container(
                                    width: w,
                                    height: h,
                                    color: AppColors.surface(context),
                                    child: Center(
                                      child: Icon(
                                        Icons.tv,
                                        color: AppColors.textTertiary(context),
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: w,
                                  height: h,
                                  color: AppColors.surface(context),
                                  child: Center(
                                    child: Icon(
                                      Icons.tv,
                                      color: AppColors.textTertiary(context),
                                      size: 48,
                                    ),
                                  ),
                                ),
                        ),
                      );
                    }

                    Widget buildInfoBody() {
                      if (_loadingDetail) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 20),
                                  // Badges row (pill shaped)
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.shade700,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.tv,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              l10n.seriesLabel,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (rating.toString().isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.gold.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.star,
                                                color: AppColors.gold,
                                                size: 12,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                rating.toString(),
                                                style: const TextStyle(
                                                  color: AppColors.gold,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  // Title
                                  Text(
                                    title.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 30,
                                      letterSpacing: -0.5,
                                      height: 1.15,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Meta row with dot separators
                                  _buildMetaRow(
                                    genre.toString(),
                                    seasonNums.isNotEmpty
                                        ? l10n.seasonCount(seasonNums.length)
                                        : '',
                                  ),
                                  const SizedBox(height: 20),
                                  // Action buttons (D-pad focusable)
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      if (_lastEpisodeProgress != null &&
                                          _lastEpisodeId != null)
                                        _FocusableActionButton(
                                          icon: Icons.play_arrow,
                                          // Two phrasings:
                                          //  * `_lastEpisodeResumeFromMs > 0`
                                          //    means mid-episode resume —
                                          //    show "Devam Et 48:57 S1E5"
                                          //  * otherwise the previous episode
                                          //    is finished and the button
                                          //    advances to the next one —
                                          //    show "Sonraki Bölüm S1E10".
                                          label: _lastEpisodeResumeFromMs > 0
                                              ? '${l10n.continueFrom(_formatDuration(Duration(milliseconds: _lastEpisodeResumeFromMs)))} $_lastEpisodeLabel'
                                              // Finished previous episode → button advances to the next.
                                              // Reuse existing localised "Play" verb + the SxxExx label
                                              // (e.g. "İzle S1E10") instead of inventing a new key.
                                              : '${l10n.play} $_lastEpisodeLabel',
                                          isPrimary: true,
                                          focusNode: _detailPlayFocusNode,
                                          maxWidth: isMobilePlatform
                                              ? 200
                                              : null,
                                          onTap: () => _playEpisode(
                                            _lastEpisodeId!,
                                            _lastEpisodeExt ?? 'mp4',
                                            startPosition:
                                                _lastEpisodeResumeFromMs > 0
                                                    ? Duration(
                                                        milliseconds:
                                                            _lastEpisodeResumeFromMs,
                                                      )
                                                    : null,
                                          ),
                                        )
                                      else if (activeEpisodes.isNotEmpty)
                                        _FocusableActionButton(
                                          icon: Icons.play_arrow,
                                          label: l10n.play,
                                          isPrimary: true,
                                          focusNode: _detailPlayFocusNode,
                                          onTap: () {
                                            final ep = activeEpisodes.first;
                                            final epId = ep['id'] is int
                                                ? ep['id'] as int
                                                : int.parse(
                                                    ep['id'].toString(),
                                                  );
                                            final ext =
                                                ep['container_extension']
                                                    ?.toString() ??
                                                'mp4';
                                            _playEpisode(epId, ext);
                                          },
                                        ),
                                      _FocusableActionButton(
                                        icon: Icons.play_circle_outline,
                                        label: l10n.watchTrailer,
                                        isPrimary: false,
                                        backgroundColor: Colors.red.shade900
                                            .withValues(alpha: 0.3),
                                        // Mobile: skip the external launch
                                        // and open the in-app fullscreen
                                        // trailer dialog — the floating PiP
                                        // is hidden on mobile so this is
                                        // the only path to the trailer.
                                        // Desktop/TV keeps the existing
                                        // `_openTrailer` (external) so this
                                        // change is mobile-only.
                                        onTap: () => isMobilePlatform
                                            ? showExpandedTrailer(
                                                context,
                                                directTrailerRef:
                                                    ch.youtubeTrailer,
                                                searchTitle: ch.name,
                                                searchYear: ch.year,
                                                channelType: ch.type,
                                              )
                                            : _openTrailer(trailerUrl),
                                      ),
                                      _FocusableActionButton(
                                        icon: Icons.open_in_new,
                                        label: 'IMDB',
                                        isPrimary: false,
                                        onTap: () =>
                                            _openImdb(title.toString(), ''),
                                      ),
                                    ],
                                  ),
                                  // Inline AI series recap — only renders
                                  // when an AI key is set AND the user has
                                  // a "next episode" target from
                                  // continue-watching state. Sits between
                                  // the action buttons and the plot so
                                  // it's discoverable without screaming.
                                  if (_lastEpisodeProgress != null &&
                                      _lastEpisodeLabel.isNotEmpty)
                                    SeriesRecapInline(
                                      series: ch,
                                      nextEpisodeLabel: _lastEpisodeLabel,
                                    ),
                                  const SizedBox(height: 24),
                                  // Plot (max-width constrained for readability).
                                  // AI-aware wrapper — pixel-identical to
                                  // a plain Text when no Gemini key is
                                  // configured, but gains inline
                                  // translate / spoiler-free-summary /
                                  // fill-in links when the user opts in.
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 600,
                                    ),
                                    child: PlotEnrichedView(
                                      channel: ch,
                                      plotText: plot.toString(),
                                      textStyle: TextStyle(
                                        color: AppColors.textSecondary(context),
                                        fontSize: 14,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  // Credits (label-value pairs)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 600,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (director.toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 80,
                                                  child: Text(
                                                    l10n.director,
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textTertiaryDark,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    director.toString(),
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textSecondaryDark,
                                                      fontSize: 13,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (cast.toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 80,
                                                  child: Text(
                                                    l10n.cast,
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textTertiaryDark,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: CastChipRow(
                                                    raw: cast.toString(),
                                                    currentTitle: ch.name,
                                                    onChannelTap: (c) {
                                                      setState(() =>
                                                          _hoveredChannel = c);
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (genre.toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 80,
                                                  child: Text(
                                                    l10n.genre,
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textTertiaryDark,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    genre.toString(),
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textSecondaryDark,
                                                      fontSize: 13,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                    }

                    if (isMobilePlatform) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Center(child: buildPoster(140, 210)),
                          const SizedBox(height: 12),
                          buildInfoBody(),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildPoster(180, 270),
                        const SizedBox(width: 32),
                        Expanded(child: buildInfoBody()),
                      ],
                    );
                  }),

                  // Season tabs + Episode list (shown for both mobile & desktop)
                  if (seasonNums.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: seasonNums.map((s) {
                              final num = int.tryParse(s) ?? 0;
                              final isActive = num == _activeSeason;
                              return _FocusableSeasonTab(
                                label: '${l10n.season} $num',
                                isActive: isActive,
                                onTap: () {
                                  setState(() => _activeSeason = num);
                                  // Lazy-fetch AI summaries for this
                                  // season's empty-plot episodes. The
                                  // method is idempotent per (series,
                                  // season) so retapping the same tab is
                                  // free.
                                  _fetchEpisodeAiSummariesForActiveSeason();
                                },
                              );
                            }).toList(),
                          ),
                        ),
                        // ── Season-level "mark as watched" toggle ──
                        // One tap marks every episode in the active
                        // season as finished. Useful when the user
                        // watched a season on another device / before
                        // the catalog was synced and wants the rail
                        // to advance past those titles.
                        _SeasonMarkWatchedButton(
                          episodes: activeEpisodes,
                          season: _activeSeason,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...activeEpisodes.map((ep) => _buildEpisodeItem(ep, l10n)),
                  ],
                  const SizedBox(height: 36),
                  AiSimilarSection(
                    current: ch,
                    onTap: (target) => _openDetail(target),
                    fallbackBuilder: (_) => similarSeries.isNotEmpty
                        ? _buildSimilarSection(similarSeries)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),

          // Compact picture-in-picture YouTube trailer in the upper-right
          // empty area. Placed LAST in the Stack so it sits on top of
          // the content scroll view for hit-testing — otherwise the
          // scroll view's gesture arena swallows taps inside the PiP
          // rect. Tap opens it fullscreen with sound.
          //
          // Mobile-only: skip rendering the floating PiP entirely. At
          // 384×216 fixed pixels it overflows narrow phone viewports
          // and stamps right under the header. The shared "Fragman
          // İzle" action button below opens the same dialog on mobile.
          //
          // Also gated on the user's `showTrailer` setting.
          if (!isMobilePlatform &&
              ref.watch(settingsProvider).showTrailer)
            Positioned(
              top: 88,
              right: 32,
              child: SizedBox(
                width: 384,
                height: 216,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: Colors.black54,
                          child: BackdropTrailer(
                            backdropUrl: null,
                            directTrailerRef: ch.youtubeTrailer,
                            searchTitle: ch.name,
                            searchYear: ch.year,
                            channelType: ch.type,
                            showBackdrop: false,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => showExpandedTrailer(
                              context,
                              directTrailerRef: ch.youtubeTrailer,
                              searchTitle: ch.name,
                              searchYear: ch.year,
                              channelType: ch.type,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String genre, String seasonCount) {
    final items = <String>[
      if (genre.isNotEmpty) genre,
      if (seasonCount.isNotEmpty) seasonCount,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '·',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Flexible(
            child: Text(
              items[i],
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEpisodeItem(dynamic ep, AppLocalizations l10n) {
    final epNum = ep['episode_num']?.toString() ?? '';
    final epTitle = ep['title']?.toString() ?? '${l10n.episode} $epNum';
    final epInfoRaw = ep['info'];
    final epInfo = _asStringKeyMap(epInfoRaw);
    final epPlot = epInfo?['plot']?.toString() ?? '';
    final epDuration = epInfo?['duration']?.toString() ?? '';
    final epThumb = epInfo?['movie_image']?.toString() ?? '';
    final epId = ep['id'] is int
        ? ep['id'] as int
        : int.parse(ep['id'].toString());
    final ext = ep['container_extension']?.toString() ?? 'mp4';

    // Look up the AI-generated fill-in by (season, epNum). Only
    // consumed by the card when the Xtream plot is empty.
    final epNumInt = int.tryParse(epNum);
    final aiSummary = epNumInt != null
        ? _episodeAiSummaries['$_activeSeason:$epNumInt']
        : null;

    return _EpisodeCard(
      epNum: epNum,
      title: epTitle,
      plot: epPlot,
      duration: epDuration,
      thumbnail: epThumb,
      onTap: () => _playEpisode(epId, ext),
      l10n: l10n,
      aiSummary: aiSummary,
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _openTrailer(String trailer) {
    final url = _normalizeTrailerUrl(trailer);
    if (url == null) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openImdb(String title, String year) {
    final query = Uri.encodeComponent(year.isNotEmpty ? '$title $year' : title);
    launchUrl(
      Uri.parse('https://www.imdb.com/find/?q=$query&s=tt'),
      mode: LaunchMode.externalApplication,
    );
  }

  String? _extractTrailerUrl(
    Map<String, dynamic>? info, {
    String? fallback,
    Map<String, dynamic>? raw,
  }) {
    final candidates = <String?>[
      info?['youtube_trailer']?.toString(),
      raw?['youtube_trailer']?.toString(),
      info?['trailer']?.toString(),
      raw?['trailer']?.toString(),
      info?['trailer_url']?.toString(),
      raw?['trailer_url']?.toString(),
      info?['youtube']?.toString(),
      raw?['youtube']?.toString(),
      fallback,
    ];
    for (final raw in candidates) {
      final normalized = _normalizeTrailerUrl(raw);
      if (normalized != null) return normalized;
    }
    return null;
  }

  String? _normalizeTrailerUrl(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;

    final lower = value.toLowerCase();
    if (lower == 'null' || lower == 'n/a' || lower == 'none' || lower == '0') {
      return null;
    }

    if (value.contains('<iframe')) {
      final srcMatch = RegExp(r'''src=["']([^"']+)["']''').firstMatch(value);
      if (srcMatch != null && srcMatch.groupCount > 0) {
        value = srcMatch.group(1)!.trim();
      }
    }

    if (value.startsWith('//')) {
      value = 'https:$value';
    }

    if (value.startsWith('http')) {
      try {
        final uri = Uri.parse(value);
        final host = uri.host.toLowerCase();

        if (host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
          return 'https://www.youtube.com/watch?v=${uri.pathSegments.first}';
        }

        if (host.contains('youtube.com') ||
            host.contains('youtube-nocookie.com')) {
          final queryVideoId = uri.queryParameters['v'];
          if (queryVideoId != null && queryVideoId.isNotEmpty) {
            return 'https://www.youtube.com/watch?v=$queryVideoId';
          }
          final segments = uri.pathSegments;
          final embedIndex = segments.indexOf('embed');
          if (embedIndex >= 0 && embedIndex + 1 < segments.length) {
            return 'https://www.youtube.com/watch?v=${segments[embedIndex + 1]}';
          }
        }

        return value;
      } catch (_) {
        return null;
      }
    }

    final idMatch = RegExp(r'^[A-Za-z0-9_-]{6,}$').firstMatch(value);
    if (idMatch != null) {
      return 'https://www.youtube.com/watch?v=$value';
    }

    final queryMatch = RegExp(r'[?&]v=([A-Za-z0-9_-]{6,})').firstMatch(value);
    if (queryMatch != null) {
      return 'https://www.youtube.com/watch?v=${queryMatch.group(1)!}';
    }

    return null;
  }

  List<Channel> _selectSimilarContent({
    required Channel current,
    required List<Channel> all,
    String? genreText,
    String? baseDirector,
    String? baseCast,
    String? basePlot,
    List<Channel> personalizationSeed = const [],
    int limit = 12,
  }) {
    final baseGenres = _genreTokens(genreText ?? current.genre ?? '');
    final baseDirectors = _textTokens(baseDirector ?? current.director ?? '');
    final baseCastTokens = _textTokens(
      baseCast ?? current.cast ?? '',
      minLength: 4,
    );
    // Plot keyword set — drives thematic-overlap scoring so series
    // with related premise float up even when genre/cast don't
    // overlap. See `_plotTokens` for stopword handling.
    final basePlotTokens =
        _plotTokens(basePlot ?? current.plot ?? '');
    final seedItems = personalizationSeed
        .where((c) => c.streamId != current.streamId)
        .toList();
    final seedIds = seedItems.map((c) => c.streamId).toSet();
    final prefGenres = <String>{};
    final prefDirectors = <String>{};
    final prefCast = <String>{};
    for (final item in seedItems) {
      prefGenres.addAll(_genreTokens(item.genre ?? ''));
      prefDirectors.addAll(_textTokens(item.director ?? ''));
      prefCast.addAll(_textTokens(item.cast ?? '', minLength: 4));
    }
    final scored = <MapEntry<Channel, int>>[];

    for (final channel in all) {
      if (channel.streamId == current.streamId) continue;

      var score = 0;
      if (channel.categoryId == current.categoryId) score += 2;
      if (current.year != null && channel.year == current.year) score += 1;

      final itemGenres = _genreTokens(channel.genre ?? '');
      if (baseGenres.isNotEmpty && itemGenres.isNotEmpty) {
        final overlap = itemGenres.where(baseGenres.contains).length;
        score += overlap * 4;
      }

      final itemDirectors = _textTokens(channel.director ?? '');
      if (baseDirectors.isNotEmpty &&
          itemDirectors.any(baseDirectors.contains)) {
        score += 5;
      }

      final itemCast = _textTokens(channel.cast ?? '', minLength: 4);
      if (baseCastTokens.isNotEmpty && itemCast.isNotEmpty) {
        final castOverlap = itemCast.where(baseCastTokens.contains).length;
        score += (castOverlap * 2).clamp(0, 6).toInt();
      }

      // Plot keyword overlap — thematic match independent of
      // genre/cast/director.
      if (basePlotTokens.isNotEmpty) {
        final itemPlotTokens = _plotTokens(channel.plot ?? '');
        if (itemPlotTokens.isNotEmpty) {
          final plotOverlap =
              itemPlotTokens.where(basePlotTokens.contains).length;
          score += plotOverlap.clamp(0, 5);
        }
      }

      if (prefGenres.isNotEmpty && itemGenres.isNotEmpty) {
        final prefGenreOverlap = itemGenres.where(prefGenres.contains).length;
        score += prefGenreOverlap * 2;
      }

      if (prefDirectors.isNotEmpty &&
          itemDirectors.any(prefDirectors.contains)) {
        score += 3;
      }

      if (prefCast.isNotEmpty && itemCast.isNotEmpty) {
        final prefCastOverlap = itemCast.where(prefCast.contains).length;
        score += prefCastOverlap.clamp(0, 4).toInt();
      }

      if (seedIds.contains(channel.streamId)) {
        score += 2;
      }

      if ((channel.rating ?? 0) > 0) {
        score += (((channel.rating ?? 0) * 10).round().clamp(0, 10) ~/ 5);
      }

      if (score > 0) {
        scored.add(MapEntry(channel, score));
      }
    }

    if (scored.isEmpty) {
      return all
          .where((c) => c.streamId != current.streamId)
          .take(limit)
          .toList();
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return (b.key.rating ?? 0).compareTo(a.key.rating ?? 0);
    });

    // Diversity cap — keep no more than half the slots for any
    // single primary genre. Without this, the top-N tends to be a
    // single-genre block (all "Drama" or all "Polisiye").
    final picked = <Channel>[];
    final genreCount = <String, int>{};
    final maxPerGenre = (limit / 2).ceil();
    for (final entry in scored) {
      final ch = entry.key;
      final primary = (_genreTokens(ch.genre ?? '').isNotEmpty)
          ? _genreTokens(ch.genre ?? '').first
          : '__nogenre__';
      final count = genreCount[primary] ?? 0;
      if (count >= maxPerGenre) continue;
      picked.add(ch);
      genreCount[primary] = count + 1;
      if (picked.length >= limit) break;
    }
    if (picked.length < limit) {
      for (final entry in scored) {
        if (picked.contains(entry.key)) continue;
        picked.add(entry.key);
        if (picked.length >= limit) break;
      }
    }
    return picked;
  }

  /// Plot tokens for thematic similarity. Lowercase, longer than
  /// 3 chars, alphabetic, with a Turkish + English stopword filter
  /// so common connectives don't pollute the signal.
  Set<String> _plotTokens(String raw) {
    if (raw.trim().isEmpty) return const {};
    return raw
        .toLowerCase()
        .split(RegExp(r'[^a-zçğıöşü0-9]+'))
        .where((w) => w.length > 3 && !_plotStopwords.contains(w))
        .toSet();
  }

  static const _plotStopwords = {
    // English
    'this', 'that', 'with', 'from', 'they', 'their', 'them', 'have',
    'will', 'when', 'what', 'where', 'which', 'while', 'into', 'about',
    'after', 'before', 'because', 'against', 'between', 'through',
    'during', 'above', 'below', 'over', 'under', 'than', 'just',
    'only', 'also', 'even', 'some', 'such', 'each', 'most', 'more',
    'much', 'many', 'other', 'another', 'these', 'those', 'there',
    'been', 'being', 'were', 'would', 'could', 'should', 'might',
    'must', 'film', 'movie', 'series', 'story', 'tale',
    // Turkish
    'için', 'olan', 'olarak', 'bir', 'ile', 'gibi', 'ama', 'fakat',
    'ancak', 'çünkü', 'eğer', 'değil', 'olur', 'olabilir', 'üzerine',
    'kadar', 'sonra', 'önce', 'bunu', 'bunun', 'şunu', 'onun', 'onlar',
    'biri', 'kendisi', 'kendi', 'her', 'tüm', 'tümü', 'birçok',
    'dizi', 'hikaye', 'hikayesi', 'konu', 'konusu', 'karakter',
    'karakteri', 'karakterler', 'kişi', 'kişisi', 'olduğu', 'olduğunu',
    'olduğunda', 'sırasında', 'üzerinde', 'altında', 'arasında',
  };

  Set<String> _genreTokens(String raw) {
    return raw
        .toLowerCase()
        .split(RegExp(r'[,/|]'))
        .map((g) => g.trim())
        .where((g) => g.length > 2)
        .toSet();
  }

  Set<String> _textTokens(String raw, {int minLength = 3}) {
    return raw
        .toLowerCase()
        .split(RegExp(r'[,/|;&]'))
        .map((v) => v.trim())
        .where((v) => v.length >= minLength)
        .toSet();
  }

  Widget _buildSimilarSection(List<Channel> items) {
    final title = AppLocalizations.of(context)!.similarSeries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final channel = items[index];
              return _buildSimilarCard(channel);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSimilarCard(Channel channel) {
    return GestureDetector(
      onTap: () {
        _onPosterHover(channel);
        _openDetail(channel);
      },
      child: SizedBox(
        width: 118,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: channel.streamIcon != null
                    ? CachedNetworkImage(
                        imageUrl: channel.streamIcon!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, _, _) =>
                            Container(color: AppColors.surface(context)),
                      )
                    : Container(color: AppColors.surface(context)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              channel.name,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Episode Card ─────────────────────────────────────────────────────────────

class _EpisodeCard extends StatefulWidget {
  final String epNum;
  final String title;
  final String plot;
  final String duration;
  final String thumbnail;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  /// Spoiler-free one-sentence summary supplied by Gemini for
  /// episodes whose Xtream `info.plot` came back empty. Only
  /// consulted when [plot] is empty — real metadata wins.
  final String? aiSummary;

  const _EpisodeCard({
    required this.epNum,
    required this.title,
    required this.plot,
    required this.duration,
    required this.thumbnail,
    required this.onTap,
    required this.l10n,
    this.aiSummary,
  });

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Focus(
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
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.surfaceElevated(context)
                    : AppColors.surface(context),
                borderRadius: BorderRadius.circular(10),
                border: _isFocused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 120,
                        height: 70,
                        color: AppColors.surfaceElevated(context),
                        child: widget.thumbnail.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.thumbnail,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white24,
                                    size: 28,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.play_circle_outline,
                                  color: isActive
                                      ? AppColors.primary
                                      : Colors.white24,
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.l10n.episode.substring(0, 1)}${widget.epNum}',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.plot.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.plot.length > 100
                                  ? '${widget.plot.substring(0, 100)}...'
                                  : widget.plot,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ] else if (widget.aiSummary != null) ...[
                            // Xtream gave us nothing for this episode
                            // and Gemini filled the gap. Rendered in
                            // primary-tinted italic with a small ✨
                            // glyph so power users can distinguish
                            // AI-generated text from real metadata.
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 10,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.aiSummary!,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (widget.duration.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  color: AppColors.textTertiary(context),
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.duration,
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: isActive ? AppColors.primary : Colors.white24,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Focusable Action Button (D-pad + Mouse + Touch) ────────────────────────

class _FocusableActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;
  final bool autofocus;
  final Color? backgroundColor;
  final FocusNode? focusNode;
  final double? maxWidth;

  const _FocusableActionButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    this.onTap,
    this.autofocus = false,
    this.backgroundColor,
    this.focusNode,
    this.maxWidth,
  });

  @override
  State<_FocusableActionButton> createState() => _FocusableActionButtonState();
}

class _FocusableActionButtonState extends State<_FocusableActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.label.isEmpty ? 10 : 18,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color:
                widget.backgroundColor ??
                (widget.isPrimary
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.maxWidth ?? double.infinity,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 18),
                if (widget.label.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Focusable Season Tab (D-pad navigable) ─────────────────────────────────

/// Small text button shown next to the season tabs that toggles
/// "Sezonu izlendi olarak işaretle" / "İşareti kaldır". One tap
/// upserts a finished-progress row for every episode in the active
/// season; tapping again clears them.
///
/// Lives in the series detail page only — episode-level toggles
/// already exist on the [_EpisodeCard] long-press menu. This widget
/// is the bulk shortcut so the user doesn't have to long-press
/// 20 episodes for a finished season.
class _SeasonMarkWatchedButton extends ConsumerStatefulWidget {
  final List<dynamic> episodes;
  final int season;

  const _SeasonMarkWatchedButton({
    required this.episodes,
    required this.season,
  });

  @override
  ConsumerState<_SeasonMarkWatchedButton> createState() =>
      _SeasonMarkWatchedButtonState();
}

class _SeasonMarkWatchedButtonState
    extends ConsumerState<_SeasonMarkWatchedButton> {
  int _finishedCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(_SeasonMarkWatchedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.season != widget.season ||
        oldWidget.episodes.length != widget.episodes.length) {
      _refresh();
    }
  }

  /// Pull only the streamIds we can resolve from the episode list —
  /// some Xtream payloads ship episodes without a numeric id, those
  /// don't have a PlaybackProgress row to update.
  List<int> get _ids => widget.episodes
      .map((e) => (e is Map ? e['id'] : null))
      .map((v) =>
          v is int ? v : (v is String ? int.tryParse(v) : null))
      .whereType<int>()
      .toList();

  Future<void> _refresh() async {
    final ids = _ids;
    if (ids.isEmpty) {
      setState(() {
        _finishedCount = 0;
        _loading = false;
      });
      return;
    }
    final count =
        await ref.read(playerRepositoryProvider).finishedCount(ids);
    if (!mounted) return;
    setState(() {
      _finishedCount = count;
      _loading = false;
    });
  }

  Future<void> _toggle() async {
    final ids = _ids;
    if (ids.isEmpty) return;
    final repo = ref.read(playerRepositoryProvider);
    final allDone = _finishedCount == ids.length;
    if (allDone) {
      await repo.unmarkEpisodes(ids);
    } else {
      await repo.markEpisodesAsWatched(ids);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    if (_loading || ids.isEmpty) return const SizedBox.shrink();
    final allDone = _finishedCount == ids.length;
    return TextButton.icon(
      onPressed: _toggle,
      icon: Icon(
        allDone ? Icons.replay_rounded : Icons.done_all_rounded,
        size: 16,
        color: allDone ? AppColors.textSecondaryDark : AppColors.primary,
      ),
      label: Text(
        allDone ? 'İşareti kaldır' : 'Sezonu izlendi işaretle',
        style: TextStyle(
          color: allDone ? AppColors.textSecondaryDark : AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

class _FocusableSeasonTab extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FocusableSeasonTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FocusableSeasonTab> createState() => _FocusableSeasonTabState();
}

class _FocusableSeasonTabState extends State<_FocusableSeasonTab> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isActive || _isFocused;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive ? AppColors.primary : AppColors.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isFocused
                  ? AppColors.primary
                  : (widget.isActive
                        ? AppColors.primary
                        : AppColors.border(context)),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: highlight ? Colors.white : AppColors.textSecondary(context),
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Focusable Category Item ────────────────────────────────────────────────

class _FocusableCatItem extends StatefulWidget {
  final String name;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onRightPressed;
  final VoidCallback? onLeftPressed;
  const _FocusableCatItem({
    required this.name,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.onRightPressed,
    this.onLeftPressed,
  });
  @override
  State<_FocusableCatItem> createState() => _FocusableCatItemState();
}

class _FocusableCatItemState extends State<_FocusableCatItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isFocused;
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // D-pad Right → collapse sidebar and go to content
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (widget.onRightPressed != null) {
              widget.onRightPressed!();
            } else {
              node.nextFocus();
            }
            return KeyEventResult.handled;
          }
          // D-pad Left → go to main sidebar
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onLeftPressed?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused
                    ? AppColors.primary
                    : (widget.isSelected
                          ? AppColors.primary
                          : Colors.transparent),
                width: _isFocused ? 2 : (widget.isSelected ? 1.5 : 0),
              ),
            ),
            child: Text(
              widget.name,
              style: TextStyle(
                color: isActive
                    ? AppColors.primary
                    : (widget.isDark
                          ? AppColors.textSecondary(context)
                          : AppColors.textSecondaryLight),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grid Views ──────────────────────────────────────────────────────────────

class _SeriesGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String categoryId;
  final String searchQuery;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _SeriesGridView({
    required this.gridController,
    required this.categoryId,
    required this.searchQuery,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_seriesChannelsProvider(categoryId));
    return channelsAsync.when(
      data: (channels) {
        final filtered = searchQuery.isEmpty
            ? channels
            : channels
                  .where((c) => c.name.toLowerCase().contains(searchQuery))
                  .toList();
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              l10n.noSeriesFound,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        return _PosterGrid(
          controller: gridController,
          channels: sortChannels(
            filterByGenre(filtered, ref.watch(seriesGenreFilterProvider)),
            ref.watch(seriesSortModeProvider),
          ),
          onHover: onHover,
          onTap: onTap,
          onLeftEdge: onLeftEdge,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _AllSeriesGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String searchQuery;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _AllSeriesGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_allSeriesProvider);
    return channelsAsync.when(
      data: (channels) {
        final filtered = searchQuery.isEmpty
            ? channels
            : channels
                  .where((c) => c.name.toLowerCase().contains(searchQuery))
                  .toList();
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              l10n.noSeriesFound,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        return _PosterGrid(
          controller: gridController,
          channels: sortChannels(
            filterByGenre(filtered, ref.watch(seriesGenreFilterProvider)),
            ref.watch(seriesSortModeProvider),
          ),
          onHover: onHover,
          onTap: onTap,
          onLeftEdge: onLeftEdge,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _FavoritesGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String searchQuery;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _FavoritesGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIdsAsync = ref.watch(_favSeriesIdsProvider);
    return favIdsAsync.when(
      data: (ids) {
        if (ids.isEmpty) {
          return EmptyState.favorites(
            title: l10n.noFavorites,
            subtitle:
                'Bir dizinin yanındaki ♥︎ ikonuna dokunarak favorilere ekleyin.',
          );
        }
        final channelsAsync = ref.watch(_favChannelsProvider(ids));
        return channelsAsync.when(
          data: (channels) {
            final filtered = searchQuery.isEmpty
                ? channels
                : channels
                      .where((c) => c.name.toLowerCase().contains(searchQuery))
                      .toList();
            if (filtered.isEmpty) {
              return EmptyState.search(
                title: l10n.noFavorites,
                subtitle:
                    '"$searchQuery" aramasıyla eşleşen favori dizi bulunamadı.',
              );
            }
            return _PosterGrid(
              controller: gridController,
              channels: sortChannels(
            filterByGenre(filtered, ref.watch(seriesGenreFilterProvider)),
            ref.watch(seriesSortModeProvider),
          ),
              onHover: onHover,
              onTap: onTap,
              onLeftEdge: onLeftEdge,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _HistoryGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String searchQuery;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _HistoryGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  void _clearAllHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated(context),
        title: Text(
          l10n.clearHistory,
          style: TextStyle(color: AppColors.text(context)),
        ),
        content: Text(
          l10n.clearHistoryConfirm,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(playerRepositoryProvider).clearAllProgress('series');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.historyCleared),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(
              l10n.clearHistory,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _removeFromHistory(
    BuildContext context,
    WidgetRef ref,
    Channel channel,
  ) {
    ref
        .read(playerRepositoryProvider)
        .deleteProgress(channel.streamId, 'series');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.removedFromHistory),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_continueWatchingSeriesProvider);
    return channelsAsync.when(
      data: (channels) {
        if (channels.isEmpty) {
          return Center(
            child: Text(
              l10n.noHistory,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        final filtered = searchQuery.isEmpty
            ? channels
            : channels
                  .where((c) => c.name.toLowerCase().contains(searchQuery))
                  .toList();
        if (filtered.isEmpty) {
          return Center(
            child: Text(
              l10n.noHistory,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        return Column(
          children: [
            // Clear history button bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _clearAllHistory(context, ref),
                    icon: const Icon(
                      Icons.delete_sweep,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: Text(
                      l10n.clearHistory,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _PosterGrid(
                controller: gridController,
                channels: sortChannels(
            filterByGenre(filtered, ref.watch(seriesGenreFilterProvider)),
            ref.watch(seriesSortModeProvider),
          ),
                onHover: onHover,
                onTap: onTap,
                onLeftEdge: onLeftEdge,
                onLongPress: (ch) => _removeFromHistory(context, ref, ch),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

/// Thin wrapper around [TvPosterGrid] that keeps two series-specific
/// behaviors: auto-hover-first-channel for the initial hero banner,
/// and per-tile "new episode" badge lookup from
/// [_newEpisodeSeriesIdsProvider]. Focus/D-pad lives in TvPosterGrid.
class _PosterGrid extends ConsumerStatefulWidget {
  final TvPosterGridController controller;
  final List<Channel> channels;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final Function(Channel)? onLongPress;
  const _PosterGrid({
    required this.controller,
    required this.channels,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    this.onLongPress,
  });

  @override
  ConsumerState<_PosterGrid> createState() => _PosterGridState();
}

class _PosterGridState extends ConsumerState<_PosterGrid> {
  bool _autoHovered = false;

  @override
  void initState() {
    super.initState();
    _maybeAutoHover();
  }

  @override
  void didUpdateWidget(covariant _PosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_autoHovered && widget.channels.isNotEmpty) {
      _maybeAutoHover();
    }
  }

  void _maybeAutoHover() {
    if (widget.channels.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoHovered) return;
      _autoHovered = true;
      widget.onHover(widget.channels.first);
    });
  }

  @override
  Widget build(BuildContext context) {
    final newEpIds = ref.watch(_newEpisodeSeriesIdsProvider).value ?? <int>{};
    return TvPosterGrid<Channel>(
      controller: widget.controller,
      items: widget.channels,
      streamIdOf: (ch) => ch.streamId,
      columns: context.gridColumns,
      childAspectRatio: 0.65,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      padding: EdgeInsets.fromLTRB(
          context.horizontalPadding, 4, context.horizontalPadding, 60),
      onActivate: (ch) => widget.onTap(ch),
      onLeftEdge: widget.onLeftEdge,
      onFocusGained: (ch) => widget.onHover(ch),
      itemBuilder: (ctx, ch, isFocused) => _PosterCardVisual(
        channel: ch,
        isFocused: isFocused,
        showNewBadge: newEpIds.contains(ch.streamId),
        onTap: () => widget.onTap(ch),
        onHover: () => widget.onHover(ch),
        onLongPress: widget.onLongPress == null
            ? null
            : () => widget.onLongPress!(ch),
      ),
    );
  }
}

/// Series poster visual. Focus/D-pad come from [TvPosterGrid]; this
/// widget only renders, tracks mouse-hover, and reads `isFocused` from
/// its parent.
class _PosterCardVisual extends StatefulWidget {
  final Channel channel;
  final bool isFocused;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showNewBadge;
  const _PosterCardVisual({
    required this.channel,
    required this.isFocused,
    required this.onHover,
    required this.onTap,
    this.onLongPress,
    this.showNewBadge = false,
  });
  @override
  State<_PosterCardVisual> createState() => _PosterCardVisualState();
}

class _PosterCardVisualState extends State<_PosterCardVisual>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween(
      begin: 1.0,
      end: PlatformHelper.focusedScale,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _syncAnim();
  }

  @override
  void didUpdateWidget(covariant _PosterCardVisual old) {
    super.didUpdateWidget(old);
    if (widget.isFocused != old.isFocused) _syncAnim();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _syncAnim() {
    if (widget.isFocused || _isHovered) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isFocused || _isHovered;
    return MouseRegion(
        // No mouse on TV — drop hover handlers so they don't race
        // the focus state. Focus alone drives the active look.
        cursor: PlatformHelper.useHoverEffects
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: PlatformHelper.useHoverEffects
            ? (_) {
                if (!mounted) return;
                setState(() => _isHovered = true);
                _syncAnim();
                widget.onHover();
              }
            : null,
        onExit: PlatformHelper.useHoverEffects
            ? (_) {
                if (!mounted) return;
                setState(() => _isHovered = false);
                _syncAnim();
              }
            : null,
        child: GestureDetector(
          onTap: () {
            widget.onHover();
            widget.onTap();
          },
          onLongPress: widget.onLongPress,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (_, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? AppColors.primary : Colors.transparent,
                  width: active ? PlatformHelper.focusRingWidth : 0,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                              alpha: PlatformHelper.focusRingGlowAlpha),
                          blurRadius: PlatformHelper.focusRingGlowBlur,
                        ),
                      ]
                    : [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.channel.streamIcon != null
                        ? CachedNetworkImage(
                            imageUrl: widget.channel.streamIcon!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _ph(),
                          )
                        : _ph(),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.85),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Play overlay on hover
                    if (active)
                      Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    // Series badge
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.seriesLabel ?? 'SERIES',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    // New episodes badge
                    if (widget.showNewBadge)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            AppLocalizations.of(context)?.newLabel ?? 'NEW',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (widget.channel.rating != null &&
                        widget.channel.rating! > 0 &&
                        !widget.showNewBadge)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: AppColors.gold,
                                size: 10,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.channel.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.channel.year != null)
                      Positioned(
                        bottom: 24,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.channel.year!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _ph() {
    final i = widget.channel.name.isNotEmpty
        ? widget.channel.name
              .substring(0, widget.channel.name.length.clamp(0, 2))
              .toUpperCase()
        : '?';
    return Container(
      color: AppColors.surfaceElevated(context),
      child: Center(
        child: Text(
          i,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final _seriesCatsProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(contentRepositoryProvider).watchCategories('series');
});

final _seriesChannelsProvider = StreamProvider.family<List<Channel>, String>((
  ref,
  categoryId,
) {
  return ref
      .watch(contentRepositoryProvider)
      .watchChannels(categoryId, type: 'series');
});

final _allSeriesProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchAllChannelsByType('series');
});

final _favSeriesIdsProvider = StreamProvider<List<int>>((ref) {
  return ref
      .watch(favoritesRepositoryProvider)
      .watchFavoriteStreamIds('series');
});

final _favChannelsProvider = StreamProvider.family<List<Channel>, List<int>>((
  ref,
  ids,
) {
  return ref
      .watch(contentRepositoryProvider)
      .watchFavoriteChannels('series', ids);
});

final _continueWatchingSeriesProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchContinueWatching('series');
});

/// Provides set of series IDs that have new episodes
final _newEpisodeSeriesIdsProvider = StreamProvider<Set<int>>((ref) {
  return ref
      .watch(contentRepositoryProvider)
      .watchSeriesWithNewEpisodes()
      .map((list) => list.map((t) => t.seriesId).toSet());
});

// ─── Focusable Icon Button (for category sidebar toggle etc.) ──────────────

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _FocusableIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surface(context),
                borderRadius: BorderRadius.circular(10),
                border: _isFocused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: isActive
                    ? AppColors.primary
                    : AppColors.textSecondary(context),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Search Button (TV-friendly, replaces inline TextField) ──────────────

class _SearchButton extends StatefulWidget {
  final String hintText;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _SearchButton({
    required this.hintText,
    this.isActive = false,
    required this.onTap,
    this.onClear,
  });
  @override
  State<_SearchButton> createState() => _SearchButtonState();
}

class _SearchButtonState extends State<_SearchButton> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isFocused
                ? AppColors.surfaceElevated(context)
                : AppColors.surface(context),
            borderRadius: BorderRadius.circular(10),
            border: _isFocused
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                color: widget.isActive
                    ? AppColors.primary
                    : AppColors.textTertiary(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.hintText,
                  style: TextStyle(
                    color: widget.isActive
                        ? AppColors.text(context)
                        : AppColors.textTertiary(context),
                    fontSize: 14,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClear != null)
                GestureDetector(
                  onTap: widget.onClear,
                  child: Icon(
                    Icons.close,
                    color: AppColors.textTertiary(context),
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
