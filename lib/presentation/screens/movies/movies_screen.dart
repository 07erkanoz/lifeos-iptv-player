import 'package:lifeostv/data/services/media_request.dart';
import 'package:lifeostv/data/services/playback_url_resolver.dart';
import 'dart:async';
import 'dart:math';

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
import 'package:lifeostv/data/services/semantic_search_service.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/widgets/ai/cast_deep_dive_sheet.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/ai/ai_similar_section.dart';
import 'package:lifeostv/presentation/widgets/ai/plot_enriched_view.dart';
import 'package:lifeostv/presentation/widgets/content/backdrop_trailer.dart';
import 'package:lifeostv/presentation/widgets/content/expanded_trailer_dialog.dart';
import 'package:lifeostv/presentation/widgets/content/favorite_button.dart';
import 'package:lifeostv/presentation/widgets/content/search_dialog.dart';
import 'package:lifeostv/presentation/widgets/content/watchlist_button.dart';
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

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});
  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  String? _selectedCategoryId;
  String _searchQuery = '';
  bool _categoriesCollapsed =
      isMobilePlatform; // collapsed by default on mobile

  // Hero: hovered poster shows big hero (NO API call on hover)
  Channel? _hoveredChannel;

  // Detail modal
  Channel? _detailChannel;
  Map<String, dynamic>? _vodInfo;
  bool _loadingDetail = false;

  // Memoised "similar" rail. _selectSimilarContent is an O(N) main-isolate
  // token-scoring pass; the detail view rebuilds many times (it watches ~6
  // streams) and the candidate list grows as the grid pages in, so without
  // a memo it re-scored thousands of items per frame → ANR/jank on weak TV.
  // Computed once per opened title (keyed by streamId), over a bounded set.
  int? _similarCacheKey;
  List<Channel> _similarCache = const [];

  // Focus scope for category sidebar (to receive focus when sidebar opens)
  final FocusScopeNode _categorySidebarScope = FocusScopeNode();
  // Node attached to the SELECTED category item — entering the sidebar
  // focuses this real item instead of the bare scope (which traps focus
  // → "no key works").
  final FocusNode _selectedCatFocusNode = FocusNode(
    debugLabel: 'MoviesSelectedCat',
  );
  // Node on the always-visible "Favorites" row. When the SELECTED category
  // lives off-screen in the scrolling list its node isn't mounted, so we
  // land focus here instead — a real, focusable item rather than the bare
  // scope (which would orphan focus).
  final FocusNode _favCatFocusNode = FocusNode(debugLabel: 'MoviesFavCat');
  // Focus node for detail view back button
  final FocusNode _detailBackFocusNode = FocusNode();
  // Focus node for detail view play button (primary action)
  final FocusNode _detailPlayFocusNode = FocusNode(
    debugLabel: 'MovieDetailPlay',
  );

  /// Controls index-based D-pad navigation and lazy-mount-safe focus
  /// restore for the poster grid. Outlives detail open/close so the
  /// previously focused streamId can be re-focused on detail dismiss.
  final TvPosterGridController _gridController = TvPosterGridController();

  /// Stable closures kept for register/unregister identity matching
  /// with [TvFocusRegistry].
  late final VoidFocusCallback _branchPrimaryCb;
  VoidFocusCallback? _detailOverlayCb;

  /// Debounce for focus-driven category-panel collapse (TV). See
  /// [_onCategoryScopeFocusChange].
  Timer? _categoryCollapseTimer;

  late final TvFocusRegistry _focusRegistry;

  @override
  void initState() {
    super.initState();
    _focusRegistry = ref.read(tvFocusRegistryProvider);
    _branchPrimaryCb = _focusGrid;
    // Collapse the category panel when D-pad focus leaves it (TV), the
    // same focus-driven way the main sidebar collapses.
    _categorySidebarScope.addListener(_onCategoryScopeFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _registerBackHandler();
      _focusRegistry.registerBranchPrimary(
        TvBranchIndex.movies,
        _branchPrimaryCb,
      );
    });
  }

  /// Auto-collapse the category panel ~300ms after D-pad focus leaves it
  /// — mirrors the main sidebar's collapse-on-blur (sidebar.dart:161).
  /// Android TV only: desktop keeps the panel open until an explicit
  /// toggle/select, preserving its mouse-driven behaviour.
  void _onCategoryScopeFocusChange() {
    if (!PlatformHelper.isTV) return;
    if (_categorySidebarScope.hasFocus) return; // still inside the panel
    if (_categoriesCollapsed) return; // already closed
    if (_detailChannel != null) return; // detail overlay owns focus
    _categoryCollapseTimer?.cancel();
    _categoryCollapseTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_categorySidebarScope.hasFocus) return; // focus came back
      if (_categoriesCollapsed || _detailChannel != null) return;
      setState(() => _categoriesCollapsed = true);
    });
  }

  @override
  void dispose() {
    _focusRegistry.unregisterBranchBack(TvBranchIndex.movies, _branchBackCb);
    // De-register before nodes disappear so registry callbacks can't
    // race a dispose. Identity-checked: a stale callback (from a hot
    // reload) can't wipe a freshly-registered live one.
    _focusRegistry.unregisterBranchPrimary(
      TvBranchIndex.movies,
      _branchPrimaryCb,
    );
    final overlay = _detailOverlayCb;
    if (overlay != null) {
      _focusRegistry.popOverlayPrimary(TvBranchIndex.movies, overlay);
    }
    _categoryCollapseTimer?.cancel();
    _categorySidebarScope.removeListener(_onCategoryScopeFocusChange);
    _categorySidebarScope.dispose();
    _selectedCatFocusNode.dispose();
    _favCatFocusNode.dispose();
    _detailBackFocusNode.dispose();
    _detailPlayFocusNode.dispose();
    super.dispose();
  }

  /// Movies back ladder lives in [resolveGridScreenBackAction] so the
  /// decision is pure-function unit-tested. This wires the inputs and
  /// dispatches the outcome.
  ///
  /// detail → close
  /// grid → category panel (when open) → main sidebar → Dashboard / exit
  late final bool Function() _branchBackCb = _handleScreenBack;

  void _registerBackHandler() {
    _focusRegistry.registerBranchBack(TvBranchIndex.movies, _branchBackCb);
  }

  bool _handleScreenBack() {
    final action = resolveGridScreenBackAction(
      detailOpen: _detailChannel != null,
      mainSidebarFocused: _focusRegistry.isMainSidebarFocused,
      categoriesCollapsed: _categoriesCollapsed,
      categoryScopeFocused: _categorySidebarScope.hasFocus,
      categoryPanelAvailable: !isMobilePlatform,
    );
    switch (action) {
      case GridScreenBackAction.closeDetail:
        _closeDetail();
        return true;
      case GridScreenBackAction.bounceToCategory:
        // Opens the panel first if it's collapsed, then lands focus on
        // a real category item (never the bare scope).
        _openCategorySidebar();
        return true;
      case GridScreenBackAction.handToShell:
        return false;
    }
  }

  void _openSearch(AppLocalizations l10n) async {
    final result = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, _, _) => SearchDialog(
          hintText: l10n.searchMovies,
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

  void _openDetail(Channel ch) async {
    // Push the detail's primary action as the active overlay focus
    // target. While present this takes precedence over the grid in
    // TvFocusRegistry, so any sidebar/back jump lands on the play
    // button instead of the grid behind the detail panel.
    final cb = _focusDetailPlayCallback;
    _detailOverlayCb = cb;
    _focusRegistry.pushOverlayPrimary(TvBranchIndex.movies, cb);
    _categorySidebarScope.canRequestFocus = false;
    // Show DB-cached data immediately if available (no loading spinner)
    final hasCachedInfo =
        ch.genre != null || ch.plot != null || ch.backdropPath != null;
    if (hasCachedInfo) {
      // Build a pseudo vodInfo from DB cache so detail view can render immediately
      final cachedInfo = <String, dynamic>{
        'info': <String, dynamic>{
          'name': ch.name,
          'plot': ch.plot ?? '',
          'genre': ch.genre ?? '',
          'director': ch.director ?? '',
          'cast': ch.cast ?? '',
          'rating': ch.rating?.toStringAsFixed(1) ?? '',
          'youtube_trailer': ch.youtubeTrailer ?? '',
          'movie_image': ch.backdropPath ?? '',
          if (ch.backdropPath != null) 'backdrop_path': [ch.backdropPath],
          if (ch.year != null) 'release_date': ch.year,
        },
      };
      setState(() {
        _detailChannel = ch;
        _vodInfo = cachedInfo;
        _loadingDetail = false;
      });
      _focusDetailBackButton();
      // Still fetch fresh data in background to update cache silently
      _refreshDetailInBackground(ch);
      return;
    }

    // No cache - show loading and fetch from API
    setState(() {
      _detailChannel = ch;
      _loadingDetail = true;
      _vodInfo = null;
    });
    _focusDetailBackButton();
    final account = ref.read(currentAccountProvider).value;
    if (account == null || account.type == 'm3u') {
      // M3U accounts don't have API — show basic info from channel data
      final basicInfo = <String, dynamic>{
        'info': <String, dynamic>{
          'name': ch.name,
          'plot': '',
          'genre': '',
          if (ch.year != null) 'release_date': ch.year,
          if (ch.streamIcon != null) 'movie_image': ch.streamIcon,
        },
      };
      if (mounted) {
        setState(() {
          _vodInfo = basicInfo;
          _loadingDetail = false;
        });
      }
      return;
    }
    try {
      final api = ref.read(xtreamApiServiceProvider);
      final info = await api.getVODInfo(
        account.url,
        account.username ?? '',
        account.password ?? '',
        ch.streamId,
      );
      if (mounted) {
        setState(() {
          _vodInfo = info;
          _loadingDetail = false;
        });
        _cacheMetadata(ch, info);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  /// Silently refresh detail from API and update cache (no loading indicator)
  void _refreshDetailInBackground(Channel ch) async {
    final account = ref.read(currentAccountProvider).value;
    if (account == null || account.type == 'm3u') return;
    final api = ref.read(xtreamApiServiceProvider);
    try {
      final info = await api.getVODInfo(
        account.url,
        account.username ?? '',
        account.password ?? '',
        ch.streamId,
      );
      if (mounted && _detailChannel?.streamId == ch.streamId && info != null) {
        setState(() => _vodInfo = info);
        _cacheMetadata(ch, info);
      }
    } catch (_) {}
  }

  void _cacheMetadata(Channel ch, Map<String, dynamic>? vodInfo) {
    if (vodInfo == null) return;
    final infoRaw = vodInfo['info'];
    final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
    if (info == null) return;
    String? backdrop;
    if (info['backdrop_path'] is List &&
        (info['backdrop_path'] as List).isNotEmpty) {
      backdrop = info['backdrop_path'][0]?.toString();
    } else if (info['movie_image'] != null &&
        info['movie_image'].toString().isNotEmpty) {
      backdrop = info['movie_image'].toString();
    }
    final trailer = _extractTrailerUrl(info, raw: vodInfo);
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
            'movie',
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

  bool _openingMovie = false;

  Future<void> _playMovie(Channel channel, {Duration? startPosition}) async {
    if (_openingMovie) return;
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    _openingMovie = true;
    final vodInfo = _detailChannel?.streamId == channel.streamId
        ? _vodInfo
        : null;
    try {
      final url = await ref
          .read(playbackUrlResolverProvider)
          .resolve(account, channel, vodInfo: vodInfo);
      if (!mounted ||
          ref.read(currentAccountProvider).value?.id != account.id) {
        return;
      }

      // Extract VOD metadata for pause info badge
      final infoRaw = vodInfo?['info'];
      final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
      final ratingStr =
          info?['rating']?.toString() ?? channel.rating?.toStringAsFixed(1);
      final ratingVal = ratingStr != null ? double.tryParse(ratingStr) : null;

      await context.push(
        '/player',
        extra: {
          'url': url,
          'httpHeaders': MediaRequest.decode(channel.playbackHeaders),
          'streamId': channel.streamId,
          'accountId': channel.accountId,
          'title': channel.name,
          'type': VideoType.movie,
          'logo': channel.streamIcon,
          'startPosition': startPosition,
          'plot': info?['plot'] ?? channel.plot,
          'genre': info?['genre'] ?? channel.genre,
          'year':
              info?['release_date']?.toString().split('-').firstOrNull ??
              channel.year,
          'director': info?['director'] ?? channel.director,
          'cast': info?['cast'] ?? channel.cast,
          'rating': ratingVal,
        },
      );
      if (mounted &&
          _detailChannel?.streamId == channel.streamId &&
          ref.read(currentAccountProvider).value?.id == account.id) {
        _focusDetailBackButton();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.streamLoadFailed)),
      );
    } finally {
      _openingMovie = false;
    }
  }

  /// Select a category, then (desktop/TV) collapse the sidebar like the
  /// main sidebar and hand focus to the grid — more room for content and
  /// a TiViMate-style flow. Focus MUST move to the grid before/with the
  /// collapse or the sidebar's FocusScope unmounts while holding focus
  /// (the freeze bug); the grid controller's deferred-focus handles the
  /// not-yet-loaded case safely.
  void _selectCategory(String? categoryId) {
    // Fresh page-1 cap for the new category so we never re-load the old
    // (possibly grown) row count against a different list.
    ref.read(_movieGridLimitProvider.notifier).reset();
    setState(() {
      _selectedCategoryId = categoryId;
      if (!isMobilePlatform) _categoriesCollapsed = true;
    });
    if (!isMobilePlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridController.focusCurrentOrFirst();
      });
    }
  }

  /// Toggle category sidebar open/closed
  void _toggleCategorySidebar() {
    if (isMobilePlatform) {
      _showCategoryBottomSheet();
      return;
    }
    setState(() => _categoriesCollapsed = !_categoriesCollapsed);
    if (_categoriesCollapsed) {
      // Sidebar collapsed → focus a poster (preferred: the one the user
      // was last on, otherwise the first). The controller handles
      // unmounted / scrolled-off-screen items with scroll-then-retry.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridController.focusCurrentOrFirst();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSidebarItem();
      });
    }
  }

  void _showCategoryBottomSheet() {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.read(_movieCategoriesProvider);
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
            // Handle bar
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
                  Icon(
                    Icons.movie_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.categories,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark
                          ? AppColors.text(context)
                          : AppColors.textLight,
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
                    l10n.allMovies,
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

  /// Move focus to the poster grid (D-pad right from category sidebar
  /// or right-arrow from the main sidebar via [TvFocusRegistry]).
  ///
  /// Prefers the previously focused poster (so detail dismiss / sidebar
  /// jumps don't lose the user's place); falls back to the first poster
  /// if the controller has nothing to restore.
  void _focusGrid() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gridController.focusCurrentOrFirst();
    });
  }

  /// Focus a concrete, focusable target inside the sidebar — the
  /// selected item if live, else the scope as a fallback. Focusing the
  /// bare scope with no focusable child orphans focus → "no key works".
  void _focusSidebarItem({int attemptsLeft = 4}) {
    if (!mounted) return;
    if (_selectedCatFocusNode.canRequestFocus) {
      _selectedCatFocusNode.requestFocus();
      return;
    }
    if (_favCatFocusNode.canRequestFocus) {
      // Selected category scrolled off-screen → land on the always-visible
      // Favorites row so D-pad works (not the bare scope, which orphans).
      _favCatFocusNode.requestFocus();
      return;
    }
    // Panel just re-expanded (it was SizedBox.shrink while collapsed), so
    // the category item FocusNodes aren't attached yet — retry over a few
    // frames instead of dropping onto the bare scope (which left focus
    // nowhere: "opens but no focus / needs the down arrow"). Bare scope is
    // only the last resort.
    if (attemptsLeft > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSidebarItem(attemptsLeft: attemptsLeft - 1);
      });
    } else {
      _categorySidebarScope.requestFocus();
    }
  }

  /// Open category sidebar (called from grid left edge D-pad)
  void _openCategorySidebar() {
    if (!_categoriesCollapsed) {
      // Already open — focus the selected category item.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusSidebarItem();
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

  /// Stable callback used for the registry overlay slot. Captured once
  /// in [_openDetail] so push/pop identity matches.
  void _focusDetailPlayCallback() {
    if (_detailPlayFocusNode.canRequestFocus) {
      _detailPlayFocusNode.requestFocus();
    }
  }

  /// Focus the main AppSidebar via [TvFocusRegistry] — no
  /// findAncestorStateOfType (the sidebar lives in a sibling subtree
  /// under StatefulShellRoute.indexedStack so the ancestor lookup
  /// never finds it anyway).
  void _focusMainSidebar() {
    final ok = _focusRegistry.requestMainSidebar();
    if (!ok) {
      // First-frame fallback before the sidebar finished registering.
      FocusManager.instance.primaryFocus?.focusInDirection(
        TraversalDirection.left,
      );
    }
  }

  void _closeDetail() {
    _similarCacheKey = null;
    _similarCache = const [];
    setState(() {
      _detailChannel = null;
      _vodInfo = null;
    });
    // Pop the overlay focus target so subsequent sidebar/back jumps go
    // back to the grid rather than a disposed detail button.
    final overlay = _detailOverlayCb;
    if (overlay != null) {
      _focusRegistry.popOverlayPrimary(TvBranchIndex.movies, overlay);
      _detailOverlayCb = null;
    }
    _categorySidebarScope.canRequestFocus = true;
    // Restore focus to the previously focused poster — only on
    // desktop/TV. On mobile: Offstage preserves scroll position;
    // imperatively requesting focus would scroll the grid.
    if (!isMobilePlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridController.focusCurrentOrFirst();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for pending detail from dashboard navigation
    final pendingChannel = ref.watch(pendingDetailChannelProvider);
    if (pendingChannel != null &&
        pendingChannel.type == 'movie' &&
        _detailChannel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detailChannel == null) {
          ref.read(pendingDetailChannelProvider.notifier).clear();
          _openDetail(pendingChannel);
        }
      });
    }

    final categoriesAsync = ref.watch(_movieCategoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final showDetail = _detailChannel != null;

    return Scaffold(
      body: Stack(
        children: [
          // Keep the list alive behind detail view so scroll position is preserved
          ExcludeFocus(
            excluding: showDetail,
            child: Offstage(
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
          color: isDark
              ? AppColors.background(context)
              : AppColors.backgroundLight,
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
                  Icon(
                    Icons.movie_outlined,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.movies,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark
                          ? AppColors.text(context)
                          : AppColors.textLight,
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
              fallbackNode: _favCatFocusNode,
            ),
            // 📺 History
            _buildCatItem(
              '📺 ${l10n.watchHistory}',
              _selectedCategoryId == _kHistoryId,
              () => _selectCategory(_kHistoryId),
              isDark,
            ),
            // All movies
            _buildCatItem(
              l10n.allMovies,
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
    bool isDark, {
    FocusNode? fallbackNode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: _FocusableCatItem(
        name: name,
        isSelected: isSelected,
        isDark: isDark,
        focusNode: isSelected ? _selectedCatFocusNode : fallbackNode,
        onTap: onTap,
        onRightPressed: _focusGrid,
        onLeftPressed: _focusMainSidebar,
      ),
    );
  }

  Widget _buildContentArea(bool isDark, AppLocalizations l10n) {
    // No parent Focus wrapper anymore — the poster grid items in
    // TvPosterGrid own their own FocusNodes and report up through the
    // controller. A parent Focus would intercept D-pad before the
    // items could handle row/column math.
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
                      : l10n.searchMovies,
                  isActive: _searchQuery.isNotEmpty,
                  onTap: () => _openSearch(l10n),
                  onClear: _searchQuery.isNotEmpty
                      ? () => setState(() => _searchQuery = '')
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              // Genre filter (only renders when there are genres in DB).
              // Uses the currently-loaded movie list to populate the picker
              // so the dropdown only ever shows genres that actually have
              // matching content.
              Consumer(
                builder: (context, ref, _) {
                  return GenreDropdown(
                    value: ref.watch(movieGenreFilterProvider),
                    genres: ref.watch(_movieGenresProvider),
                    onChanged: (g) =>
                        ref.read(movieGenreFilterProvider.notifier).set(g),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Sort picker (newest / rating / name)
              Consumer(
                builder: (context, ref, _) => SortDropdown(
                  value: ref.watch(movieSortModeProvider),
                  onChanged: (m) =>
                      ref.read(movieSortModeProvider.notifier).set(m),
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
        onPlay: _playMovie,
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
        onPlay: _playMovie,
        onHover: _onPosterHover,
        onTap: _openDetail,
        onLeftEdge: _openCategorySidebar,
        l10n: l10n,
      );
    }
    if (_selectedCategoryId != null) {
      return _MovieGridView(
        gridController: _gridController,
        categoryId: _selectedCategoryId!,
        searchQuery: _searchQuery,
        onPlay: _playMovie,
        onHover: _onPosterHover,
        onTap: _openDetail,
        onLeftEdge: _openCategorySidebar,
        l10n: l10n,
      );
    }
    return _AllMoviesGridView(
      gridController: _gridController,
      searchQuery: _searchQuery,
      onPlay: _playMovie,
      onHover: _onPosterHover,
      onTap: _openDetail,
      onLeftEdge: _openCategorySidebar,
      l10n: l10n,
    );
  }

  Widget _buildHeroBanner(Channel ch, bool isDark, AppLocalizations l10n) {
    final hasBackdrop = ch.backdropPath?.isNotEmpty ?? false;
    final imgUrl = hasBackdrop ? ch.backdropPath! : ch.streamIcon;
    final heroHeight = isMobilePlatform
        ? 200.0
        : PlatformHelper.isTV
        ? (MediaQuery.sizeOf(context).height * 0.36).clamp(280.0, 380.0)
        : 280.0;

    return GestureDetector(
      onTap: () => _openDetail(ch),
      child: Container(
        height: heroHeight,
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image (backdrop preferred)
            if (imgUrl != null && (hasBackdrop || !PlatformHelper.isTV))
              CachedNetworkImage(
                imageUrl: imgUrl,
                fit: BoxFit.cover,
                memCacheWidth: PlatformHelper.isTV ? 1280 : 960,
                fadeInDuration: PlatformHelper.isTV
                    ? Duration.zero
                    : const Duration(milliseconds: 500),
                alignment: const Alignment(0, -0.3),
                errorWidget: (_, _, _) =>
                    Container(color: AppColors.surface(context)),
              ),
            if (!hasBackdrop && PlatformHelper.isTV && imgUrl != null)
              Positioned(
                right: 32,
                top: 12,
                bottom: 12,
                width: heroHeight * 0.68,
                child: CachedNetworkImage(
                  imageUrl: imgUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 420,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),

            // Left gradient for text readability (lighter to show more poster)
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

            // Content overlay
            Positioned(
              left: PlatformHelper.isTV ? 32 : 24,
              bottom: PlatformHelper.isTV ? 28 : 20,
              width: PlatformHelper.isTV
                  ? min(MediaQuery.sizeOf(context).width * 0.48, 620)
                  : null,
              right: PlatformHelper.isTV ? null : 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badges: type + rating + year
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.movie,
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
                  // Title
                  Text(
                    ch.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: PlatformHelper.isTV ? 30 : 24,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Genre (from DB cache)
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
                  // Plot (from DB cache)
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
                  // Action buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _playMovie(ch),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(l10n.play),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _openDetail(ch),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: Text(l10n.details),
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
                      // Trailer button (if available in DB)
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

            // Mini poster (bottom right, like Tauri)
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
                    memCacheWidth: 300,
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
    final compactDetail =
        isMobilePlatform || MediaQuery.sizeOf(context).width < 1000;
    final ch = _detailChannel!;
    final infoRaw = _vodInfo?['info'];
    final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
    final title = info?['name'] ?? ch.name;
    final plot = info?['plot'] ?? '';
    final cast = info?['cast'] ?? '';
    final director = info?['director'] ?? '';
    final genre = info?['genre'] ?? '';
    final rating = info?['rating'] ?? ch.rating?.toStringAsFixed(1) ?? '';
    final releaseDate = info?['release_date']?.toString() ?? '';
    final year = releaseDate.length >= 4
        ? releaseDate.substring(0, 4)
        : (ch.year ?? '');
    final duration = info?['duration'] ?? '';
    // Server / DB cache first; if neither has a real URL fall back to a
    // YouTube search query so every movie has a working trailer button.
    final trailerUrl =
        _extractTrailerUrl(info, fallback: ch.youtubeTrailer, raw: _vodInfo) ??
        youtubeSearchTrailerUrl(
          ch.name,
          year: year.isNotEmpty ? year : ch.year,
        );
    final backdrop =
        (info?['backdrop_path'] is List &&
            (info!['backdrop_path'] as List).isNotEmpty)
        ? info['backdrop_path'][0]
        : info?['movie_image'] ?? ch.backdropPath ?? ch.streamIcon ?? '';

    // Get playback progress
    final progressAsync = ref.watch(
      _playbackProgressProvider((streamId: ch.streamId, type: 'movie')),
    );
    final progress = progressAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, _) => null,
    );
    final favIds = ref
        .watch(_favMovieIdsProvider)
        .when(
          data: (v) => v,
          loading: () => const <int>[],
          error: (_, _) => const <int>[],
        );
    final favoriteMovies = favIds.isEmpty
        ? const <Channel>[]
        : ref
              .watch(_favChannelsProvider(favIds))
              .when(
                data: (v) => v,
                loading: () => const <Channel>[],
                error: (_, _) => const <Channel>[],
              );
    final historyMovies = ref
        .watch(_continueWatchingMoviesProvider)
        .when(
          data: (v) => v,
          loading: () => const <Channel>[],
          error: (_, _) => const <Channel>[],
        );
    final allMoviesAsync = ref.watch(_allMoviesProvider);
    // Prefer semantic (embedding) similarity when available — it's
    // genuinely per-title. Falls back to the metadata heuristic until
    // the catalogue is embedded.
    final embSimilar =
        ref.watch(_embeddingSimilarMoviesProvider(ch.streamId)).value ??
        const <Channel>[];
    final similarMovies = embSimilar.isNotEmpty
        ? embSimilar
        : allMoviesAsync.when(
            data: (all) => _memoSimilarMovies(
              ch,
              all,
              genreText: genre.toString().isNotEmpty
                  ? genre.toString()
                  : ch.genre,
              baseDirector: director.toString().isNotEmpty
                  ? director.toString()
                  : ch.director,
              baseCast: cast.toString().isNotEmpty ? cast.toString() : ch.cast,
              basePlot: plot.toString().isNotEmpty ? plot.toString() : ch.plot,
              personalizationSeed: [...favoriteMovies, ...historyMovies],
            ),
            loading: () => _similarCacheKey == ch.streamId
                ? _similarCache
                : const <Channel>[],
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
                    memCacheWidth: PlatformHelper.isTV ? 720 : 1280,
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
                  type: 'movie',
                  name: ch.name,
                  thumbnail: ch.streamIcon,
                ),
                const SizedBox(width: 8),
                FavoriteButton(
                  streamId: ch.streamId,
                  type: 'movie',
                  name: ch.name,
                  thumbnail: ch.streamIcon,
                ),
              ],
            ),
          ),

          // Content
          Positioned(
            left: compactDetail ? 16 : 40,
            top: compactDetail ? 56 : 80,
            right: compactDetail ? 16 : 40,
            bottom: 0,
            child: SingleChildScrollView(
              child: compactDetail
                  ? _buildMobileDetailContent(
                      ch,
                      l10n,
                      progress,
                      trailerUrl,
                      similarMovies,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster (200×300, Tauri style)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: PlatformHelper.isTV
                                ? const <BoxShadow>[]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
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
                                    width: 180,
                                    height: 270,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 360,
                                    errorWidget: (_, _, _) => Container(
                                      width: 180,
                                      height: 270,
                                      color: AppColors.surface(context),
                                      child: Center(
                                        child: Icon(
                                          Icons.movie,
                                          color: AppColors.textTertiary(
                                            context,
                                          ),
                                          size: 48,
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 180,
                                    height: 270,
                                    color: AppColors.surface(context),
                                    child: Center(
                                      child: Icon(
                                        Icons.movie,
                                        color: AppColors.textTertiary(context),
                                        size: 48,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Info column
                        Expanded(
                          child: _loadingDetail
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 60),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 20),
                                    // Badges row
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade700,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.movie,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                l10n.movie,
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
                                              borderRadius:
                                                  BorderRadius.circular(20),
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
                                      year,
                                      genre.toString(),
                                      duration.toString(),
                                    ),
                                    const SizedBox(height: 20),
                                    // Actions row (D-pad focusable)
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        if (progress != null &&
                                            !progress.isFinished &&
                                            progress.position > 1000)
                                          _FocusableActionButton(
                                            icon: Icons.play_arrow,
                                            label: l10n.continueFrom(
                                              _formatDuration(
                                                Duration(
                                                  milliseconds:
                                                      progress.position,
                                                ),
                                              ),
                                            ),
                                            isPrimary: true,
                                            focusNode: _detailPlayFocusNode,
                                            onTap: () => _playMovie(
                                              ch,
                                              startPosition: Duration(
                                                milliseconds: progress.position,
                                              ),
                                            ),
                                          )
                                        else
                                          _FocusableActionButton(
                                            icon: Icons.play_arrow,
                                            label: l10n.play,
                                            isPrimary: true,
                                            focusNode: _detailPlayFocusNode,
                                            onTap: () => _playMovie(ch),
                                          ),
                                        _FocusableActionButton(
                                          icon: Icons.play_circle_outline,
                                          label: l10n.watchTrailer,
                                          isPrimary: false,
                                          backgroundColor: Colors.red.shade900
                                              .withValues(alpha: 0.3),
                                          onTap: () => _openTrailer(trailerUrl),
                                        ),
                                        _FocusableActionButton(
                                          icon: Icons.open_in_new,
                                          label: 'IMDB',
                                          isPrimary: false,
                                          onTap: () =>
                                              _openImdb(title.toString(), year),
                                        ),
                                      ],
                                    ),
                                    // Progress bar
                                    if (progress != null &&
                                        !progress.isFinished &&
                                        progress.position > 1000 &&
                                        progress.duration > 0) ...[
                                      const SizedBox(height: 14),
                                      SizedBox(
                                        width: 300,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          child: LinearProgressIndicator(
                                            value:
                                                (progress.position /
                                                        progress.duration)
                                                    .clamp(0.0, 1.0),
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.1),
                                            color: AppColors.primary,
                                            minHeight: 3,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    // Plot (max-width constrained for readability).
                                    // PlotEnrichedView falls back to plain Text
                                    // when the user has no Gemini key — so this
                                    // is visually identical for users without AI
                                    // and gains inline translate / summarise /
                                    // fill-in links for those who opt in.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 600,
                                      ),
                                      child: PlotEnrichedView(
                                        channel: ch,
                                        plotText: plot.toString(),
                                        textStyle: TextStyle(
                                          color: AppColors.textSecondary(
                                            context,
                                          ),
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
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textTertiary(
                                                              context,
                                                            ),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      director.toString(),
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textSecondary(
                                                              context,
                                                            ),
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
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textTertiary(
                                                              context,
                                                            ),
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
                                                        // Defer-pop the bottom sheet,
                                                        // then switch the detail page
                                                        // to the new channel.
                                                        setState(
                                                          () =>
                                                              _hoveredChannel =
                                                                  c,
                                                        );
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
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textTertiary(
                                                              context,
                                                            ),
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      genre.toString(),
                                                      style: TextStyle(
                                                        color:
                                                            AppColors.textSecondary(
                                                              context,
                                                            ),
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
                                    // Smart Similar — falls back to the
                                    // token-overlap rail when no Gemini key or
                                    // when the AI call doesn't yield usable
                                    // results.
                                    const SizedBox(height: 44),
                                    AiSimilarSection(
                                      current: ch,
                                      onTap: (target) => _openDetail(target),
                                      fallbackBuilder: (_) =>
                                          similarMovies.isNotEmpty
                                          ? _buildSimilarSection(similarMovies)
                                          : const SizedBox.shrink(),
                                    ),
                                    const SizedBox(height: 40),
                                  ],
                                ),
                        ),
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
          // and stamps right under the header, covering content. The
          // "Fragman İzle" button in `_buildMobileDetailContent` opens
          // the same `showExpandedTrailer` dialog directly, which is
          // the right entry point for a touch UI without burning
          // cellular data / battery on silent autoplay.
          //
          // Also gated on the user's `showTrailer` setting — turning
          // it off keeps the detail panel static and stops the
          // background YouTube extraction from running.
          if (!compactDetail &&
              !PlatformHelper.isTV &&
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
                            searchYear: year.isNotEmpty ? year : ch.year,
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
                              searchYear: year.isNotEmpty ? year : ch.year,
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

  Widget _buildMobileDetailContent(
    Channel ch,
    AppLocalizations l10n,
    dynamic progress,
    String? trailerUrl,
    List<Channel> similarMovies,
  ) {
    final infoRaw = _vodInfo?['info'];
    final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
    final title = info?['name'] ?? ch.name;
    final plot = info?['plot'] ?? '';
    final cast = info?['cast'] ?? '';
    final director = info?['director'] ?? '';
    final genre = info?['genre'] ?? '';
    final rating = info?['rating'] ?? ch.rating?.toStringAsFixed(1) ?? '';
    final releaseDate = info?['release_date']?.toString() ?? '';
    final year = releaseDate.length >= 4
        ? releaseDate.substring(0, 4)
        : (ch.year ?? '');
    final duration = info?['duration'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Poster (centered, smaller on mobile)
        if (ch.streamIcon != null)
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: ch.streamIcon!,
                  width: 120,
                  height: 180,
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  errorWidget: (_, _, _) => Container(
                    width: 120,
                    height: 180,
                    color: AppColors.surface(context),
                    child: Center(
                      child: Icon(
                        Icons.movie,
                        color: AppColors.textTertiary(context),
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Badges
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie, color: Colors.white, size: 10),
                  const SizedBox(width: 4),
                  Text(
                    l10n.movie,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (rating.toString().isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: AppColors.gold, size: 10),
                    const SizedBox(width: 3),
                    Text(
                      rating.toString(),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // Title
        Text(
          title.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.3,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        // Meta
        _buildMetaRow(year, genre.toString(), duration.toString()),
        const SizedBox(height: 16),
        // Action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (progress != null &&
                !progress.isFinished &&
                progress.position > 1000)
              ElevatedButton.icon(
                onPressed: () => _playMovie(
                  ch,
                  startPosition: Duration(milliseconds: progress.position),
                ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(l10n.continueWatching),
              ),
            ElevatedButton.icon(
              onPressed: () => _playMovie(ch),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(l10n.play),
            ),
            if (trailerUrl != null)
              OutlinedButton.icon(
                // Mobile entry point for the trailer. Desktop has a
                // floating PiP that opens the same dialog on tap, but
                // mobile skips the PiP (see the Positioned in
                // `_buildDetailView`) — so this button is the only path.
                // Open the in-app `showExpandedTrailer` instead of
                // bouncing the user out to the external YouTube app.
                onPressed: () => showExpandedTrailer(
                  context,
                  directTrailerRef: ch.youtubeTrailer,
                  searchTitle: ch.name,
                  searchYear: year.isNotEmpty ? year : ch.year,
                  channelType: ch.type,
                ),
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: Text(l10n.trailer),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Plot — same AI-aware wrapper as the desktop branch.
        PlotEnrichedView(
          channel: ch,
          plotText: plot.toString(),
          textStyle: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        // Credits
        if (director.toString().isNotEmpty)
          _buildCreditRow(l10n.director, director.toString()),
        if (cast.toString().isNotEmpty)
          _buildCastCreditRow(l10n.cast, cast.toString(), ch),
        if (genre.toString().isNotEmpty)
          _buildCreditRow(l10n.genre, genre.toString()),
        const SizedBox(height: 30),
        AiSimilarSection(
          current: ch,
          onTap: (target) => _openDetail(target),
          fallbackBuilder: (_) => similarMovies.isNotEmpty
              ? _buildSimilarSection(similarMovies)
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  /// Like [_buildCreditRow] but renders the value through a
  /// CastChipRow so each name is tappable and opens the cast
  /// deep-dive sheet. Used for the cast field on the mobile/narrow
  /// detail layout; the wide layout above already swapped in the
  /// chip row inline.
  Widget _buildCastCreditRow(String label, String rawCast, Channel current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: CastChipRow(
              raw: rawCast,
              currentTitle: current.name,
              onChannelTap: (c) {
                setState(() => _hoveredChannel = c);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildMetaRow(String year, String genre, String duration) {
    final items = <String>[
      if (year.isNotEmpty) year,
      if (genre.isNotEmpty) genre,
      if (duration.isNotEmpty) duration,
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
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

  /// Memoised wrapper around [_selectSimilarContent]: computes once per
  /// opened title and over a bounded candidate set, so the detail view's
  /// repeated rebuilds don't re-run an O(N) main-isolate scoring pass on a
  /// list that grows into the thousands (the ANR/jank on weak TVs).
  List<Channel> _memoSimilarMovies(
    Channel current,
    List<Channel> all, {
    String? genreText,
    String? baseDirector,
    String? baseCast,
    String? basePlot,
    List<Channel> personalizationSeed = const [],
  }) {
    if (_similarCacheKey == current.streamId && _similarCache.isNotEmpty) {
      return _similarCache;
    }
    // Bound the candidate set — far cheaper to score, and the rail only
    // needs ~12 picks. Tighter cap on TV where the CPU is weakest.
    final cap = PlatformHelper.isTV ? 400 : 1200;
    final candidates = all.length > cap ? all.sublist(0, cap) : all;
    final result = _selectSimilarContent(
      current: current,
      all: candidates,
      genreText: genreText,
      baseDirector: baseDirector,
      baseCast: baseCast,
      basePlot: basePlot,
      personalizationSeed: personalizationSeed,
    );
    _similarCacheKey = current.streamId;
    _similarCache = result;
    return result;
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
    // Plot tokens — meaningful content words from the current item's
    // plot. Drives a thematic-overlap score so e.g. an action film
    // about "kidnapping a daughter" surfaces other films whose
    // plots include "kidnapping". Stopword-filtered + length-gated
    // to drop "the", "and", "için", etc.
    final basePlotTokens = _plotTokens(basePlot ?? current.plot ?? '');
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
      // Category is the single strongest signal on Turkish IPTV
      // catalogues — `channels.genre` is empty most of the time
      // but the category name encodes the genre ("KORKU & PSiKOLOJiK",
      // "AKSiYON & MACERA"). Without bumping this weight the
      // algorithm gives every item the same score and the rail
      // shows the same top-rated films for EVERY VOD detail.
      if (channel.categoryId == current.categoryId) score += 25;
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
      // genre/cast/director. Counts shared meaningful words in
      // the plot column and weights moderately (each shared word
      // is worth 1 point, capped at 5).
      if (basePlotTokens.isNotEmpty) {
        final itemPlotTokens = _plotTokens(channel.plot ?? '');
        if (itemPlotTokens.isNotEmpty) {
          final plotOverlap = itemPlotTokens
              .where(basePlotTokens.contains)
              .length;
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

    // Sort: score desc, then per-current deterministic shuffle.
    // Without the shuffle every tied score bucket falls back to
    // rating, which on Türkish IPTV catalogues means the same
    // ~15 high-rated films win every tie → "every VOD shows the
    // same recommendations". The shuffle uses the current item's
    // streamId as a seed, so:
    //   * Same current → same order across opens (stable cache).
    //   * Different current → different order (different seed).
    final tieRng = Random(current.streamId);
    final tieOrder = <int, int>{
      for (final e in scored) e.key.streamId: tieRng.nextInt(1 << 30),
    };
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      // Equal score → seeded random tiebreaker (NOT rating). Rating
      // is already absorbed into the score; using it as the
      // tiebreaker on top of that just biases toward the same
      // few items again.
      return (tieOrder[a.key.streamId] ?? 0).compareTo(
        tieOrder[b.key.streamId] ?? 0,
      );
    });

    // Diversity guard — without it the top-N tends to be a clone
    // strip of the same series / franchise (e.g. "Korku Seansı 1,
    // 2, 3, 4…"). Cap items with the same primary genre at half
    // the result set; if we hit the cap, skip subsequent
    // same-genre candidates and pick from lower-scored buckets so
    // the user still sees variety.
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
    // If diversity capping starved us, top up from the original
    // ranking — better to over-cluster than to return too few.
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
  /// 3 chars, alphabetic, and minus a Turkish + English stopword
  /// list so common connectives don't pollute the signal.
  Set<String> _plotTokens(String raw) {
    if (raw.trim().isEmpty) return const {};
    final words = raw
        .toLowerCase()
        .split(RegExp(r'[^a-zçğıöşü0-9]+'))
        .where((w) => w.length > 3 && !_plotStopwords.contains(w));
    return words.toSet();
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
    'must', 'film', 'movie', 'story', 'tale', 'series',
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
    final title = AppLocalizations.of(context)!.similarContent;

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
    return _FocusableSimilarCard(
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
                        memCacheWidth: 360,
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

// ─── Focusable "Similar" rail card ──────────────────────────────────────────
// The similar rail was a bare GestureDetector — not focusable, so on TV the
// detail had NO focus target below the action buttons: D-pad down did nothing
// and the page couldn't scroll ("detay alta inmiyor"), and similar items
// weren't selectable. This wrapper makes each card a real focus stop (select/
// enter opens it) with a focus ring, so D-pad reaches the rail (scrolling the
// detail on the way) and can open items.
class _FocusableSimilarCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _FocusableSimilarCard({required this.child, required this.onTap});

  @override
  State<_FocusableSimilarCard> createState() => _FocusableSimilarCardState();
}

class _FocusableSimilarCardState extends State<_FocusableSimilarCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: widget.child,
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
  final FocusNode? focusNode;
  const _FocusableCatItem({
    required this.name,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.onRightPressed,
    this.onLeftPressed,
    this.focusNode,
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
      focusNode: widget.focusNode,
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

// ─── Focusable Action Button (D-pad + Mouse + Touch) ────────────────────────

class _FocusableActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final FocusNode? focusNode;

  const _FocusableActionButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    this.onTap,
    this.backgroundColor,
    this.focusNode,
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
            constraints: BoxConstraints(maxWidth: double.infinity),
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

// ─── Movie Grid Views ───────────────────────────────────────────────────────

class _MovieGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String categoryId;
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _MovieGridView({
    required this.gridController,
    required this.categoryId,
    required this.searchQuery,
    required this.onPlay,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_movieChannelsProvider(categoryId));
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
              l10n.noMoviesFound,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        final genreFiltered = filterByGenre(
          filtered,
          ref.watch(movieGenreFilterProvider),
        );
        final sorted = sortChannels(
          genreFiltered,
          ref.watch(movieSortModeProvider),
        );
        return _PosterGrid(
          controller: gridController,
          channels: sorted,
          onPlay: (ch) => onPlay(ch),
          onHover: onHover,
          onTap: onTap,
          onLeftEdge: onLeftEdge,
          // Grow the page when the grid nears its end. Idempotent: bumps to
          // raw-count + one page only while the DB returned a full page
          // (more may exist); stops once a short page proves exhaustion.
          onNeedMore: () =>
              ref.read(_movieGridLimitProvider.notifier).grow(channels.length),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _AllMoviesGridView extends ConsumerWidget {
  final TvPosterGridController gridController;
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _AllMoviesGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onPlay,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_allMoviesProvider);
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
              l10n.noMoviesFound,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          );
        }
        final genreFiltered = filterByGenre(
          filtered,
          ref.watch(movieGenreFilterProvider),
        );
        final sorted = sortChannels(
          genreFiltered,
          ref.watch(movieSortModeProvider),
        );
        return _PosterGrid(
          controller: gridController,
          channels: sorted,
          onPlay: (ch) => onPlay(ch),
          onHover: onHover,
          onTap: onTap,
          onLeftEdge: onLeftEdge,
          onNeedMore: () =>
              ref.read(_movieGridLimitProvider.notifier).grow(channels.length),
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
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _FavoritesGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onPlay,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIdsAsync = ref.watch(_favMovieIdsProvider);
    return favIdsAsync.when(
      data: (ids) {
        if (ids.isEmpty) {
          return EmptyState.favorites(
            title: l10n.noFavorites,
            subtitle:
                'Bir filmin yanındaki ♥︎ ikonuna dokunarak favorilere ekleyin.',
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
                    '"$searchQuery" aramasıyla eşleşen favori bulunamadı.',
              );
            }
            final genreFiltered = filterByGenre(
              filtered,
              ref.watch(movieGenreFilterProvider),
            );
            final sorted = sortChannels(
              genreFiltered,
              ref.watch(movieSortModeProvider),
            );
            return _PosterGrid(
              controller: gridController,
              channels: sorted,
              onPlay: (ch) => onPlay(ch),
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
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _HistoryGridView({
    required this.gridController,
    required this.searchQuery,
    required this.onPlay,
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
              ref.read(playerRepositoryProvider).clearAllProgress('movie');
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
        .deleteProgress(channel.streamId, 'movie');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.removedFromHistory),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_continueWatchingMoviesProvider);
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
                channels: filtered,
                onPlay: (ch) => onPlay(ch),
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

/// Thin wrapper around [TvPosterGrid] that hooks the auto-hover-first
/// behavior (so the hero banner shows something before the user has
/// focused a tile) and the unmuted poster visual ([_PosterCardVisual]).
/// The actual focus/D-pad work lives in [TvPosterGrid] and the
/// controller passed in.
class _PosterGrid extends StatefulWidget {
  final TvPosterGridController controller;
  final List<Channel> channels;
  final Function(Channel) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final Function(Channel)? onLongPress;
  final VoidCallback? onNeedMore;
  const _PosterGrid({
    required this.controller,
    required this.channels,
    required this.onPlay,
    required this.onHover,
    required this.onTap,
    this.onLeftEdge,
    this.onLongPress,
    this.onNeedMore,
  });

  @override
  State<_PosterGrid> createState() => _PosterGridState();
}

class _PosterGridState extends State<_PosterGrid> {
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

  /// Auto-select the first channel for hero display on initial load so
  /// the banner isn't blank before the user has moved focus. Separate
  /// from focus: the hero updates on hover too, and focus is delivered
  /// later when the registry fires (or never on mobile).
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
    return TvPosterGrid<Channel>(
      controller: widget.controller,
      items: widget.channels,
      streamIdOf: (ch) => ch.streamId,
      columns: context.gridColumns,
      childAspectRatio: 0.65,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      padding: EdgeInsets.fromLTRB(
        context.horizontalPadding,
        4,
        context.horizontalPadding,
        60,
      ),
      onActivate: (ch) => widget.onTap(ch),
      onLeftEdge: widget.onLeftEdge,
      onNeedMore: widget.onNeedMore,
      // Mirror hover state on focus changes — drives the hero banner
      // when D-pad moves between tiles.
      onFocusGained: (ch) => widget.onHover(ch),
      itemBuilder: (ctx, ch, isFocused) => _PosterCardVisual(
        channel: ch,
        isFocused: isFocused,
        onTap: () => widget.onTap(ch),
        onHover: () => widget.onHover(ch),
        onLongPress: widget.onLongPress == null
            ? null
            : () => widget.onLongPress!(ch),
      ),
    );
  }
}

/// Pure visual for a poster tile. Owns mouse-hover state for desktop
/// (the focus state arrives from [TvPosterGrid] via [isFocused]); the
/// active "lit up" look is `isFocused || isHovered`.
class _PosterCardVisual extends StatefulWidget {
  final Channel channel;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback? onLongPress;

  const _PosterCardVisual({
    required this.channel,
    required this.isFocused,
    required this.onTap,
    required this.onHover,
    this.onLongPress,
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
      // Snap the focus scale instantly on Android TV (no per-D-pad-move
      // re-composite tween); animated on desktop where the GPU can spare it.
      duration: PlatformHelper.isTV
          ? Duration.zero
          : const Duration(milliseconds: 180),
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

  void _syncAnim() {
    if (widget.isFocused || _isHovered) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isFocused || _isHovered;
    return MouseRegion(
      // No mouse on TV — drop hover interactions so they don't race
      // the focus state. The poster's active look is driven by
      // isFocused alone in that case.
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
        onTap: widget.onTap,
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
              // No blurred glow on TV — the focus border alone marks the
              // tile; a 24px Gaussian glow per D-pad move is wasted GPU work.
              boxShadow: (active && !PlatformHelper.isTV)
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: PlatformHelper.focusRingGlowAlpha,
                        ),
                        blurRadius: PlatformHelper.focusRingGlowBlur,
                      ),
                    ]
                  : const <BoxShadow>[],
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
                          // Decode posters to ~tile width, not full source
                          // resolution — a grid of full-res decodes is the
                          // main OOM/jank source on weak Android TV GPUs.
                          memCacheWidth: 320,
                          errorWidget: (_, _, _) =>
                              _placeholder(context, widget.channel),
                        )
                      : _placeholder(context, widget.channel),
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
                  if (widget.channel.rating != null &&
                      widget.channel.rating! > 0)
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
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
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

  static Widget _placeholder(BuildContext context, Channel channel) {
    final i = channel.name.isNotEmpty
        ? channel.name
              .substring(0, channel.name.length.clamp(0, 2))
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

final _movieCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(contentRepositoryProvider).watchCategories('movie');
});

/// Progressive-loading page size: how many poster rows to pull initially
/// and grow by each time the grid nears its end. Bounds memory + the
/// per-build sort cost so a huge category never loads all at once.
const int _kGridPageSize = 240;

/// Row cap for a poster grid, grown as the user nears the end. Riverpod 3
/// dropped `StateProvider`, so this is a tiny Notifier. [grow] is
/// idempotent: it only advances while the DB returned a full page (more
/// may exist) and no-ops once a short page proves the list is exhausted.
class _GridLimitNotifier extends Notifier<int> {
  @override
  int build() => _kGridPageSize;

  void grow(int rawCount) {
    if (rawCount >= state) state = rawCount + _kGridPageSize;
  }

  void reset() {
    if (state != _kGridPageSize) state = _kGridPageSize;
  }
}

/// Row cap for the currently shown movie grid (category or "All"). Only
/// one grid is visible at a time, so a single shared provider suffices;
/// it's reset on every category switch so each category starts at page 1.
final _movieGridLimitProvider = NotifierProvider<_GridLimitNotifier, int>(
  _GridLimitNotifier.new,
);

final _movieChannelsProvider = StreamProvider.family<List<Channel>, String>((
  ref,
  categoryId,
) {
  final limit = ref.watch(_movieGridLimitProvider);
  return ref
      .watch(contentRepositoryProvider)
      .watchChannels(categoryId, type: 'movie', limit: limit);
});

final _allMoviesProvider = StreamProvider<List<Channel>>((ref) {
  final limit = ref.watch(_movieGridLimitProvider);
  return ref
      .watch(contentRepositoryProvider)
      .watchAllChannelsByType('movie', limit: limit);
});

/// Genre chips derived from the loaded movie list. Memoized as a Provider so
/// it recomputes only when the list actually changes (a page grow / DB emit),
/// not on every unrelated widget rebuild (focus, hero, typing) — which used
/// to re-scan the whole loaded set each frame and jank D-pad scrolling.
final _movieGenresProvider = Provider<List<String>>((ref) {
  final all = ref.watch(_allMoviesProvider).value ?? const <Channel>[];
  return extractGenres(all);
});

/// Embedding-based "similar movies" for a given stream id. Empty until
/// the title (and its neighbours) have been embedded — the detail page
/// falls back to its heuristic in that case. Vector ranking is what
/// makes the rail genuinely per-title instead of "same top items".
final _embeddingSimilarMoviesProvider =
    FutureProvider.family<List<Channel>, int>((ref, streamId) async {
      // Never run the semantic (embedding) similar scan on Android TV — if a
      // paired phone LAN-synced embeddings, this would loadAll + sort every
      // vector on the DB isolate on each detail open. The metadata fallback
      // (_memoSimilarMovies) covers TV cheaply.
      if (PlatformHelper.isTV) return const [];
      final hits = await ref
          .watch(semanticSearchServiceProvider)
          .similarTo(streamId, 'movie', k: 30, restrictType: 'movie');
      if (hits.isEmpty) return const [];
      final db = ref.watch(appDatabaseProvider);
      final ids = hits.map((h) => h.streamId).toList();
      final rows = await (db.select(
        db.channels,
      )..where((t) => t.streamId.isIn(ids))).get();
      final byId = {
        for (final r in rows)
          if (r.type == 'movie') r.streamId: r,
      };
      return [
        for (final h in hits)
          if (byId[h.streamId] != null) byId[h.streamId]!,
      ];
    });

final _favMovieIdsProvider = StreamProvider<List<int>>((ref) {
  return ref.watch(favoritesRepositoryProvider).watchFavoriteStreamIds('movie');
});

final _favChannelsProvider = StreamProvider.family<List<Channel>, List<int>>((
  ref,
  ids,
) {
  return ref
      .watch(contentRepositoryProvider)
      .watchFavoriteChannels('movie', ids);
});

final _continueWatchingMoviesProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchContinueWatching('movie');
});

final _playbackProgressProvider =
    StreamProvider.family<PlaybackProgressData?, ({int streamId, String type})>(
      (ref, params) {
        return ref
            .watch(contentRepositoryProvider)
            .watchPlaybackProgress(params.streamId, params.type);
      },
    );

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

// ─── Search Button (replaces inline TextField for TV friendliness) ──────────

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
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClear,
                  // Padding gives the ✕ a finger-sized tap target so a
                  // mobile tap clears the search instead of slipping
                  // onto the surrounding button and reopening it.
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close,
                      color: AppColors.textTertiary(context),
                      size: 18,
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
