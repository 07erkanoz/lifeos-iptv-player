import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/widgets/content/favorite_button.dart';
import 'package:lifeostv/presentation/widgets/content/search_dialog.dart';
import 'package:lifeostv/presentation/widgets/layout/sidebar.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/utils/responsive.dart';

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
  bool _categoriesCollapsed = isMobilePlatform; // collapsed by default on mobile

  // Hero: hovered poster shows big hero (NO API call on hover)
  Channel? _hoveredChannel;

  // Detail modal
  Channel? _detailChannel;
  Map<String, dynamic>? _vodInfo;
  bool _loadingDetail = false;

  // Focus node for content area (to receive focus after sidebar collapse)
  final FocusNode _contentFocusNode = FocusNode();
  // Focus scope for category sidebar (to receive focus when sidebar opens)
  final FocusScopeNode _categorySidebarScope = FocusScopeNode();
  // Focus node for detail view back button
  final FocusNode _detailBackFocusNode = FocusNode();
  // Focus node for detail view play button (primary action)
  final FocusNode _detailPlayFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerBackHandler();
    });
  }

  @override
  void dispose() {
    _contentFocusNode.dispose();
    _categorySidebarScope.dispose();
    _detailBackFocusNode.dispose();
    _detailPlayFocusNode.dispose();
    super.dispose();
  }

  /// Register a back handler that handles all focus levels:
  /// Detail open → close detail
  /// Category sidebar focused → move to content
  /// Content focused → move to main sidebar
  void _registerBackHandler() {
    ref.read(backHandlerProvider.notifier).set(() {
      // Level 2: Detail is open → close it
      if (_detailChannel != null) {
        _closeDetail();
        return true;
      }
      // Level 1b: Category sidebar is focused → move to content
      if (!_categoriesCollapsed && _categorySidebarScope.hasFocus) {
        _focusContent();
        return true;
      }
      // Level 1a: Content area is focused → move to main sidebar
      if (_contentFocusNode.hasFocus) {
        _focusMainSidebar();
        return true;
      }
      return false; // Let AppShell handle it
    });
  }

  void _openSearch(AppLocalizations l10n) async {
    final result = await Navigator.of(context).push<String>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => SearchDialog(
          hintText: l10n.searchMovies,
          initialQuery: _searchQuery,
        ),
        transitionsBuilder: (_, anim, __, child) =>
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
    // Disable content area focus so grid can't steal focus from detail
    _contentFocusNode.canRequestFocus = false;
    _categorySidebarScope.canRequestFocus = false;
    // Show DB-cached data immediately if available (no loading spinner)
    final hasCachedInfo = ch.genre != null || ch.plot != null || ch.backdropPath != null;
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
      setState(() { _detailChannel = ch; _vodInfo = cachedInfo; _loadingDetail = false; });
      _focusDetailBackButton();
      // Still fetch fresh data in background to update cache silently
      _refreshDetailInBackground(ch);
      return;
    }

    // No cache - show loading and fetch from API
    setState(() { _detailChannel = ch; _loadingDetail = true; _vodInfo = null; });
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
      if (mounted) setState(() { _vodInfo = basicInfo; _loadingDetail = false; });
      return;
    }
    try {
      final api = ref.read(xtreamApiServiceProvider);
      final info = await api.getVODInfo(account.url, account.username ?? '', account.password ?? '', ch.streamId);
      if (mounted) {
        setState(() { _vodInfo = info; _loadingDetail = false; });
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
      final info = await api.getVODInfo(account.url, account.username ?? '', account.password ?? '', ch.streamId);
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
    if (info['backdrop_path'] is List && (info['backdrop_path'] as List).isNotEmpty) {
      backdrop = info['backdrop_path'][0]?.toString();
    } else if (info['movie_image'] != null && info['movie_image'].toString().isNotEmpty) {
      backdrop = info['movie_image'].toString();
    }
    final trailer = _extractTrailerUrl(info, raw: vodInfo);
    final genre = info['genre']?.toString();
    final plot = info['plot']?.toString() ?? info['description']?.toString();
    final director = info['director']?.toString();
    final castInfo = info['cast']?.toString();
    // Cache all metadata to DB (serve from cache next time, no API call needed)
    if (backdrop != null || (trailer != null && trailer.isNotEmpty) ||
        (genre != null && genre.isNotEmpty) || (plot != null && plot.isNotEmpty) ||
        (director != null && director.isNotEmpty) || (castInfo != null && castInfo.isNotEmpty)) {
      ref.read(contentRepositoryProvider).updateChannelMetadata(
        ch.streamId, 'movie',
        backdropPath: backdrop,
        youtubeTrailer: (trailer != null && trailer.isNotEmpty) ? trailer : null,
        genre: (genre != null && genre.isNotEmpty) ? genre : null,
        plot: (plot != null && plot.isNotEmpty) ? plot : null,
        director: (director != null && director.isNotEmpty) ? director : null,
        castInfo: (castInfo != null && castInfo.isNotEmpty) ? castInfo : null,
      );
    }
  }

  void _playMovie(Channel channel, {Duration? startPosition}) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    // M3U accounts: use direct stream URL from DB
    final url = (account.type == 'm3u' && channel.streamUrl != null && channel.streamUrl!.isNotEmpty)
        ? channel.streamUrl!
        : '${account.url}/movie/${account.username}/${account.password}/${channel.streamId}.mkv';

    // Extract VOD metadata for pause info badge
    final infoRaw = _vodInfo?['info'];
    final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
    final ratingStr = info?['rating']?.toString() ?? channel.rating?.toStringAsFixed(1);
    final ratingVal = ratingStr != null ? double.tryParse(ratingStr) : null;

    context.push('/player', extra: {
      'url': url,
      'title': channel.name,
      'type': VideoType.movie,
      'logo': channel.streamIcon,
      'startPosition': startPosition,
      'plot': info?['plot'] ?? channel.plot,
      'genre': info?['genre'] ?? channel.genre,
      'year': info?['release_date']?.toString().split('-').firstOrNull ?? channel.year,
      'director': info?['director'] ?? channel.director,
      'cast': info?['cast'] ?? channel.cast,
      'rating': ratingVal,
    });
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
        if (mounted) {
          _contentFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.down);
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _categorySidebarScope.requestFocus();
      });
    }
  }

  void _showCategoryBottomSheet() {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.read(_movieCategoriesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textTertiaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.movie_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(l10n.categories, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: isDark ? AppColors.textDark : AppColors.textLight)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildMobileCatTile('⭐ ${l10n.myFavorites}', _selectedCategoryId == _kFavoritesId, () {
                    Navigator.pop(ctx);
                    _selectCategory(_kFavoritesId);
                  }),
                  _buildMobileCatTile('📺 ${l10n.watchHistory}', _selectedCategoryId == _kHistoryId, () {
                    Navigator.pop(ctx);
                    _selectCategory(_kHistoryId);
                  }),
                  _buildMobileCatTile(l10n.allMovies, _selectedCategoryId == null, () {
                    Navigator.pop(ctx);
                    _selectCategory(null);
                  }),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ...categoriesAsync.when(
                    data: (cats) => cats.map((cat) => _buildMobileCatTile(cat.name, cat.id == _selectedCategoryId, () {
                      Navigator.pop(ctx);
                      _selectCategory(cat.id);
                    })),
                    loading: () => [const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))],
                    error: (e, _) => [Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('$e')))],
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
      leading: isSelected ? const Icon(Icons.check_circle, size: 18) : const Icon(Icons.circle_outlined, size: 18, color: AppColors.textTertiaryDark),
      title: Text(name, style: TextStyle(
        fontSize: 14,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      )),
      onTap: onTap,
    );
  }

  /// Move focus to content area (D-pad right from category sidebar)
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentFocusNode.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.down);
        });
      }
    });
  }

  /// Open category sidebar (called from grid left edge D-pad)
  void _openCategorySidebar() {
    if (!_categoriesCollapsed) return;
    _toggleCategorySidebar();
  }

  /// Focus the detail view play button (primary action for better TV UX)
  void _focusDetailBackButton() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detailPlayFocusNode.requestFocus();
    });
  }

  /// Focus the main AppSidebar (called from category item left press)
  void _focusMainSidebar() {
    final sidebarState = context.findAncestorStateOfType<AppSidebarState>();
    if (sidebarState != null) {
      sidebarState.requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.left);
    }
  }

  void _closeDetail() {
    setState(() { _detailChannel = null; _vodInfo = null; });
    // Re-enable content area focus
    _contentFocusNode.canRequestFocus = true;
    _categorySidebarScope.canRequestFocus = true;
    // Restore focus to content area — only on desktop/TV
    // On mobile: Offstage preserves scroll position, focus manipulation
    // would scroll the grid to a random item
    if (!isMobilePlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _contentFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.down);
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for pending detail from dashboard navigation
    final pendingChannel = ref.watch(pendingDetailChannelProvider);
    if (pendingChannel != null && pendingChannel.type == 'movie' && _detailChannel == null) {
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

  Widget _buildCategoriesPanel(AsyncValue<List<Category>> categoriesAsync, bool isDark, AppLocalizations l10n) {
    // Fully hidden when collapsed — content takes full width
    if (_categoriesCollapsed) {
      return const SizedBox.shrink();
    }

    return FocusScope(
      node: _categorySidebarScope,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          border: Border(right: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Row(children: [
              Icon(Icons.movie_outlined, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(l10n.movies, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: isDark ? AppColors.textDark : AppColors.textLight)),
            ]),
          ),
          // ⭐ Favorites
          _buildCatItem('⭐ ${l10n.myFavorites}', _selectedCategoryId == _kFavoritesId, () => _selectCategory(_kFavoritesId), isDark),
          // 📺 History
          _buildCatItem('📺 ${l10n.watchHistory}', _selectedCategoryId == _kHistoryId, () => _selectCategory(_kHistoryId), isDark),
          // All movies
          _buildCatItem(l10n.allMovies, _selectedCategoryId == null, () => _selectCategory(null), isDark),
          Divider(color: isDark ? AppColors.borderDark : AppColors.borderLight, height: 1, indent: 12, endIndent: 12),
          Expanded(
            child: categoriesAsync.when(
              data: (cats) => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: cats.length,
                itemBuilder: (_, i) => _buildCatItem(cats[i].name, cats[i].id == _selectedCategoryId, () => _selectCategory(cats[i].id), isDark),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12))),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCatItem(String name, bool isSelected, VoidCallback onTap, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: _FocusableCatItem(name: name, isSelected: isSelected, isDark: isDark, onTap: onTap, onRightPressed: _focusContent, onLeftPressed: _focusMainSidebar),
    );
  }

  Widget _buildContentArea(bool isDark, AppLocalizations l10n) {
    return Focus(
      focusNode: _contentFocusNode,
      child: Column(
      children: [
        // Hero banner (Tauri style: backdrop + info)
        if (_hoveredChannel != null && (_hoveredChannel!.backdropPath ?? _hoveredChannel!.streamIcon) != null)
          _buildHeroBanner(_hoveredChannel!, isDark, l10n)
        else
          const SizedBox(height: 8),
        // Search bar + back-to-categories button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
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
                hintText: _searchQuery.isNotEmpty ? _searchQuery : l10n.searchMovies,
                isActive: _searchQuery.isNotEmpty,
                onTap: () => _openSearch(l10n),
                onClear: _searchQuery.isNotEmpty
                    ? () => setState(() => _searchQuery = '')
                    : null,
              ),
            ),
          ]),
        ),
        // Grid
        Expanded(child: _buildGrid(l10n)),
      ],
    ),
    );
  }

  Widget _buildGrid(AppLocalizations l10n) {
    if (_selectedCategoryId == _kFavoritesId) {
      return _FavoritesGridView(searchQuery: _searchQuery, onPlay: _playMovie, onHover: _onPosterHover, onTap: _openDetail, onLeftEdge: _openCategorySidebar, l10n: l10n);
    }
    if (_selectedCategoryId == _kHistoryId) {
      return _HistoryGridView(searchQuery: _searchQuery, onPlay: _playMovie, onHover: _onPosterHover, onTap: _openDetail, onLeftEdge: _openCategorySidebar, l10n: l10n);
    }
    if (_selectedCategoryId != null) {
      return _MovieGridView(categoryId: _selectedCategoryId!, searchQuery: _searchQuery, onPlay: _playMovie, onHover: _onPosterHover, onTap: _openDetail, onLeftEdge: _openCategorySidebar, l10n: l10n);
    }
    return _AllMoviesGridView(searchQuery: _searchQuery, onPlay: _playMovie, onHover: _onPosterHover, onTap: _openDetail, onLeftEdge: _openCategorySidebar, l10n: l10n);
  }

  Widget _buildHeroBanner(Channel ch, bool isDark, AppLocalizations l10n) {
    final hasBackdrop = ch.backdropPath != null;
    final imgUrl = hasBackdrop ? ch.backdropPath! : ch.streamIcon;

    return GestureDetector(
      onTap: () => _openDetail(ch),
      child: Container(
        height: isMobilePlatform ? 200 : 280,
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image (backdrop preferred)
            if (imgUrl != null)
              Image.network(imgUrl, fit: BoxFit.cover,
                alignment: const Alignment(0, -0.3),
                errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceDark)),

            // Left gradient for text readability (lighter to show more poster)
            Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft, end: Alignment.centerRight,
                colors: [
                  AppColors.backgroundDark.withValues(alpha: 0.85),
                  AppColors.backgroundDark.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.7],
              ),
            )),
            // Bottom gradient
            Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [
                  AppColors.backgroundDark,
                  AppColors.backgroundDark.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.5],
              ),
            )),

            // Content overlay
            Positioned(
              left: 24, bottom: 20, right: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badges: type + rating + year
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                      child: Text(l10n.movie, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
                    ),
                    if (ch.rating != null && ch.rating! > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star, color: AppColors.gold, size: 12),
                          const SizedBox(width: 3),
                          Text(ch.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                    if (ch.year != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(ch.year!, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  // Title
                  Text(ch.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24, height: 1.2),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  // Genre (from DB cache)
                  if (ch.genre != null && ch.genre!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: ch.genre!.split(',').take(4).map((g) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Text(g.trim(), style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 10)),
                      )).toList(),
                    ),
                  ],
                  // Plot (from DB cache)
                  if (ch.plot != null && ch.plot!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ch.plot!.length > 150 ? '${ch.plot!.substring(0, 150)}...' : ch.plot!,
                      style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Action buttons
                  Row(children: [
                    ElevatedButton.icon(
                      onPressed: () => _playMovie(ch),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(l10n.play),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openDetail(ch),
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: Text(l10n.details),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    // Trailer button (if available in DB)
                    if (ch.youtubeTrailer != null && ch.youtubeTrailer!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          final tid = ch.youtubeTrailer!;
                          final url = tid.startsWith('http') ? tid : 'https://www.youtube.com/watch?v=$tid';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: Text(l10n.trailer),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),

            // Mini poster (bottom right, like Tauri)
            if (ch.streamIcon != null && hasBackdrop)
              Positioned(
                right: 24, bottom: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(ch.streamIcon!, width: 100, height: 150, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
    final infoRaw = _vodInfo?['info'];
    final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
    final title = info?['name'] ?? ch.name;
    final plot = info?['plot'] ?? '';
    final cast = info?['cast'] ?? '';
    final director = info?['director'] ?? '';
    final genre = info?['genre'] ?? '';
    final rating = info?['rating'] ?? ch.rating?.toStringAsFixed(1) ?? '';
    final releaseDate = info?['release_date']?.toString() ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : (ch.year ?? '');
    final duration = info?['duration'] ?? '';
    final trailerUrl = _extractTrailerUrl(info, fallback: ch.youtubeTrailer, raw: _vodInfo);
    final backdrop = (info?['backdrop_path'] is List && (info!['backdrop_path'] as List).isNotEmpty)
        ? info['backdrop_path'][0] : info?['movie_image'] ?? ch.backdropPath ?? ch.streamIcon ?? '';

    // Get playback progress
    final progressAsync = ref.watch(_playbackProgressProvider((streamId: ch.streamId, type: 'movie')));
    final progress = progressAsync.when(data: (p) => p, loading: () => null, error: (_, __) => null);
    final favIds = ref.watch(_favMovieIdsProvider).when(
      data: (v) => v,
      loading: () => const <int>[],
      error: (_, __) => const <int>[],
    );
    final favoriteMovies = favIds.isEmpty
        ? const <Channel>[]
        : ref.watch(_favChannelsProvider(favIds)).when(
              data: (v) => v,
              loading: () => const <Channel>[],
              error: (_, __) => const <Channel>[],
            );
    final historyMovies = ref.watch(_continueWatchingMoviesProvider).when(
      data: (v) => v,
      loading: () => const <Channel>[],
      error: (_, __) => const <Channel>[],
    );
    final allMoviesAsync = ref.watch(_allMoviesProvider);
    final similarMovies = allMoviesAsync.when(
      data: (all) => _selectSimilarContent(
        current: ch,
        all: all,
        genreText: genre.toString().isNotEmpty ? genre.toString() : ch.genre,
        baseDirector: director.toString().isNotEmpty ? director.toString() : ch.director,
        baseCast: cast.toString().isNotEmpty ? cast.toString() : ch.cast,
        personalizationSeed: [...favoriteMovies, ...historyMovies],
      ),
      loading: () => const <Channel>[],
      error: (_, __) => const <Channel>[],
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // Backdrop
          if (backdrop.toString().isNotEmpty)
            Positioned.fill(
              child: Image.network(backdrop.toString(), fit: BoxFit.cover, alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceDark)),
            ),
          // Gradients
          Positioned.fill(child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.backgroundDark.withValues(alpha: 0.6), AppColors.backgroundDark], stops: const [0.0, 0.35, 0.65])),
          )),
          Positioned.fill(child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
              colors: [AppColors.backgroundDark.withValues(alpha: 0.85), Colors.transparent], stops: const [0.0, 0.5])),
          )),

          // Back button + Favorite button
          Positioned(top: 16, left: 16, child: _FocusableActionButton(
            icon: Icons.arrow_back,
            label: '',
            isPrimary: false,
            backgroundColor: Colors.black45,
            onTap: _closeDetail,
            focusNode: _detailBackFocusNode,
          )),
          Positioned(top: 16, right: 16, child: FavoriteButton(
            streamId: ch.streamId, type: 'movie', name: ch.name, thumbnail: ch.streamIcon,
          )),

          // Content
          Positioned(
            left: isMobilePlatform ? 16 : 40,
            top: isMobilePlatform ? 56 : 80,
            right: isMobilePlatform ? 16 : 40,
            bottom: 0,
            child: SingleChildScrollView(
            child: isMobilePlatform
                ? _buildMobileDetailContent(ch, l10n, progress, trailerUrl, similarMovies)
                : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster (200×300, Tauri style)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 12))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ch.streamIcon != null
                        ? Image.network(ch.streamIcon!, width: 180, height: 270, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 180, height: 270, color: AppColors.surfaceDark,
                              child: Center(child: Icon(Icons.movie, color: AppColors.textTertiaryDark, size: 48))))
                        : Container(width: 180, height: 270, color: AppColors.surfaceDark,
                            child: Center(child: Icon(Icons.movie, color: AppColors.textTertiaryDark, size: 48))),
                  ),
                ),
                const SizedBox(width: 32),
                // Info column
                Expanded(child: _loadingDetail
                    ? const Center(child: Padding(padding: EdgeInsets.only(top: 60), child: CircularProgressIndicator()))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          // Badges row
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.movie, color: Colors.white, size: 12),
                                const SizedBox(width: 5),
                                Text(l10n.movie, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.3)),
                              ]),
                            ),
                            if (rating.toString().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.star, color: AppColors.gold, size: 12),
                                  const SizedBox(width: 4),
                                  Text(rating.toString(), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600, fontSize: 11)),
                                ]),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 14),
                          // Title
                          Text(title.toString(), style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 30,
                            letterSpacing: -0.5, height: 1.15,
                            shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                          )),
                          const SizedBox(height: 10),
                          // Meta row with dot separators
                          _buildMetaRow(year, genre.toString(), duration.toString()),
                          const SizedBox(height: 20),
                          // Actions row (D-pad focusable)
                          Wrap(spacing: 10, runSpacing: 8, children: [
                            if (progress != null && !progress.isFinished && progress.position > 1000)
                              _FocusableActionButton(
                                icon: Icons.play_arrow,
                                label: l10n.continueFrom(_formatDuration(Duration(milliseconds: progress.position))),
                                isPrimary: true,
                                focusNode: _detailPlayFocusNode,
                                onTap: () => _playMovie(ch, startPosition: Duration(milliseconds: progress.position)),
                              )
                            else
                              _FocusableActionButton(
                                icon: Icons.play_arrow,
                                label: l10n.play,
                                isPrimary: true,
                                focusNode: _detailPlayFocusNode,
                                onTap: () => _playMovie(ch),
                              ),
                            if (trailerUrl != null)
                              _FocusableActionButton(
                                icon: Icons.play_circle_outline,
                                label: l10n.watchTrailer,
                                isPrimary: false,
                                backgroundColor: Colors.red.shade900.withValues(alpha: 0.3),
                                onTap: () => _openTrailer(trailerUrl),
                              ),
                            _FocusableActionButton(
                              icon: Icons.open_in_new,
                              label: 'IMDB',
                              isPrimary: false,
                              onTap: () => _openImdb(title.toString(), year),
                            ),
                          ]),
                          // Progress bar
                          if (progress != null && !progress.isFinished && progress.position > 1000 && progress.duration > 0) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: 300,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: (progress.position / progress.duration).clamp(0.0, 1.0),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  color: AppColors.primary,
                                  minHeight: 3,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          // Plot (max-width constrained for readability)
                          if (plot.toString().isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 600),
                              child: Text(plot.toString(), style: const TextStyle(
                                color: AppColors.textSecondaryDark, fontSize: 14, height: 1.6,
                              )),
                            ),
                          const SizedBox(height: 20),
                          // Credits (label-value pairs)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (director.toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 80,
                                          child: Text(l10n.director, style: const TextStyle(color: AppColors.textTertiaryDark, fontSize: 13, fontWeight: FontWeight.w700)),
                                        ),
                                        Expanded(child: Text(director.toString(), style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, height: 1.4))),
                                      ],
                                    ),
                                  ),
                                if (cast.toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 80,
                                          child: Text(l10n.cast, style: const TextStyle(color: AppColors.textTertiaryDark, fontSize: 13, fontWeight: FontWeight.w700)),
                                        ),
                                        Expanded(child: Text(
                                          cast.toString().length > 100 ? '${cast.toString().substring(0, 100)}...' : cast.toString(),
                                          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, height: 1.4),
                                        )),
                                      ],
                                    ),
                                  ),
                                if (genre.toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 80,
                                          child: Text(l10n.genre, style: const TextStyle(color: AppColors.textTertiaryDark, fontSize: 13, fontWeight: FontWeight.w700)),
                                        ),
                                        Expanded(child: Text(genre.toString(), style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, height: 1.4))),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (similarMovies.isNotEmpty) ...[
                            const SizedBox(height: 44),
                            _buildSimilarSection(similarMovies),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                ),
              ],
            ),
          )),
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
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : (ch.year ?? '');
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(ch.streamIcon!, width: 120, height: 180, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 120, height: 180, color: AppColors.surfaceDark,
                    child: const Center(child: Icon(Icons.movie, color: AppColors.textTertiaryDark, size: 36)))),
              ),
            ),
          ),
        // Badges
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.movie, color: Colors.white, size: 10),
              const SizedBox(width: 4),
              Text(l10n.movie, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
            ]),
          ),
          if (rating.toString().isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star, color: AppColors.gold, size: 10),
                const SizedBox(width: 3),
                Text(rating.toString(), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600, fontSize: 10)),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        // Title
        Text(title.toString(), style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22,
          letterSpacing: -0.3, height: 1.15,
        )),
        const SizedBox(height: 6),
        // Meta
        _buildMetaRow(year, genre.toString(), duration.toString()),
        const SizedBox(height: 16),
        // Action buttons
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (progress != null && !progress.isFinished && progress.position > 1000)
            ElevatedButton.icon(
              onPressed: () => _playMovie(ch, startPosition: Duration(milliseconds: progress.position)),
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
              onPressed: () => _openTrailer(trailerUrl),
              icon: const Icon(Icons.play_circle_outline, size: 16),
              label: Text(l10n.trailer),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        // Plot
        if (plot.toString().isNotEmpty)
          Text(plot.toString(), style: const TextStyle(
            color: AppColors.textSecondaryDark, fontSize: 13, height: 1.6,
          )),
        const SizedBox(height: 12),
        // Credits
        if (director.toString().isNotEmpty)
          _buildCreditRow(l10n.director, director.toString()),
        if (cast.toString().isNotEmpty)
          _buildCreditRow(l10n.cast, cast.toString().length > 100 ? '${cast.toString().substring(0, 100)}...' : cast.toString()),
        if (genre.toString().isNotEmpty)
          _buildCreditRow(l10n.genre, genre.toString()),
        if (similarMovies.isNotEmpty) ...[
          const SizedBox(height: 30),
          _buildSimilarSection(similarMovies),
        ],
        const SizedBox(height: 40),
      ],
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
            child: Text(label, style: const TextStyle(color: AppColors.textTertiaryDark, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
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
          if (i > 0) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('·', style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: Text(items[i], style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
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

        if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
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
    List<Channel> personalizationSeed = const [],
    int limit = 12,
  }) {
    final baseGenres = _genreTokens(genreText ?? current.genre ?? '');
    final baseDirectors = _textTokens(baseDirector ?? current.director ?? '');
    final baseCastTokens = _textTokens(baseCast ?? current.cast ?? '', minLength: 4);
    final seedItems = personalizationSeed.where((c) => c.streamId != current.streamId).toList();
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
      if (baseDirectors.isNotEmpty && itemDirectors.any(baseDirectors.contains)) {
        score += 5;
      }

      final itemCast = _textTokens(channel.cast ?? '', minLength: 4);
      if (baseCastTokens.isNotEmpty && itemCast.isNotEmpty) {
        final castOverlap = itemCast.where(baseCastTokens.contains).length;
        score += (castOverlap * 2).clamp(0, 6).toInt();
      }

      if (prefGenres.isNotEmpty && itemGenres.isNotEmpty) {
        final prefGenreOverlap = itemGenres.where(prefGenres.contains).length;
        score += prefGenreOverlap * 2;
      }

      if (prefDirectors.isNotEmpty && itemDirectors.any(prefDirectors.contains)) {
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
      return all.where((c) => c.streamId != current.streamId).take(limit).toList();
    }

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return (b.key.rating ?? 0).compareTo(a.key.rating ?? 0);
    });

    return scored.take(limit).map((e) => e.key).toList();
  }

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
    final locale = Localizations.localeOf(context).languageCode;
    final title = locale == 'tr' ? 'Benzer İçerikler' : 'More Like This';

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
            separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                    ? Image.network(
                        channel.streamIcon!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceDark),
                      )
                    : Container(color: AppColors.surfaceDark),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              channel.name,
              style: const TextStyle(
                color: AppColors.textSecondaryDark,
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

// ─── Focusable Category Item ────────────────────────────────────────────────

class _FocusableCatItem extends StatefulWidget {
  final String name;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onRightPressed;
  final VoidCallback? onLeftPressed;
  const _FocusableCatItem({required this.name, required this.isSelected, required this.isDark, required this.onTap, this.onRightPressed, this.onLeftPressed});
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
        color: isActive ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? AppColors.primary : (widget.isSelected ? AppColors.primary : Colors.transparent),
                width: _isFocused ? 2 : (widget.isSelected ? 1.5 : 0),
              ),
            ),
            child: Text(widget.name, style: TextStyle(
              color: isActive ? AppColors.primary : (widget.isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, fontSize: 13,
            ), maxLines: 1, overflow: TextOverflow.ellipsis),
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
          padding: EdgeInsets.symmetric(horizontal: widget.label.isEmpty ? 10 : 18, vertical: 10),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? (widget.isPrimary
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth ?? double.infinity),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 18),
                if (widget.label.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
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
  final String categoryId;
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _MovieGridView({required this.categoryId, required this.searchQuery, required this.onPlay, required this.onHover, required this.onTap, this.onLeftEdge, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_movieChannelsProvider(categoryId));
    return channelsAsync.when(
      data: (channels) {
        final filtered = searchQuery.isEmpty ? channels : channels.where((c) => c.name.toLowerCase().contains(searchQuery)).toList();
        if (filtered.isEmpty) return Center(child: Text(l10n.noMoviesFound, style: TextStyle(color: AppColors.textTertiaryDark)));
        return _PosterGrid(channels: filtered, onPlay: (ch) => onPlay(ch), onHover: onHover, onTap: onTap, onLeftEdge: onLeftEdge);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _AllMoviesGridView extends ConsumerWidget {
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _AllMoviesGridView({required this.searchQuery, required this.onPlay, required this.onHover, required this.onTap, this.onLeftEdge, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_allMoviesProvider);
    return channelsAsync.when(
      data: (channels) {
        final filtered = searchQuery.isEmpty ? channels : channels.where((c) => c.name.toLowerCase().contains(searchQuery)).toList();
        if (filtered.isEmpty) return Center(child: Text(l10n.noMoviesFound, style: TextStyle(color: AppColors.textTertiaryDark)));
        return _PosterGrid(channels: filtered, onPlay: (ch) => onPlay(ch), onHover: onHover, onTap: onTap, onLeftEdge: onLeftEdge);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _FavoritesGridView extends ConsumerWidget {
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _FavoritesGridView({required this.searchQuery, required this.onPlay, required this.onHover, required this.onTap, this.onLeftEdge, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIdsAsync = ref.watch(_favMovieIdsProvider);
    return favIdsAsync.when(
      data: (ids) {
        if (ids.isEmpty) return Center(child: Text(l10n.noFavorites, style: TextStyle(color: AppColors.textTertiaryDark)));
        final channelsAsync = ref.watch(_favChannelsProvider(ids));
        return channelsAsync.when(
          data: (channels) {
            final filtered = searchQuery.isEmpty ? channels : channels.where((c) => c.name.toLowerCase().contains(searchQuery)).toList();
            if (filtered.isEmpty) return Center(child: Text(l10n.noFavorites, style: TextStyle(color: AppColors.textTertiaryDark)));
            return _PosterGrid(channels: filtered, onPlay: (ch) => onPlay(ch), onHover: onHover, onTap: onTap, onLeftEdge: onLeftEdge);
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
  final String searchQuery;
  final Function(Channel, {Duration? startPosition}) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final AppLocalizations l10n;
  const _HistoryGridView({required this.searchQuery, required this.onPlay, required this.onHover, required this.onTap, this.onLeftEdge, required this.l10n});

  void _clearAllHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        title: Text(l10n.clearHistory, style: const TextStyle(color: AppColors.textDark)),
        content: Text(l10n.clearHistoryConfirm, style: const TextStyle(color: AppColors.textSecondaryDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              ref.read(playerRepositoryProvider).clearAllProgress('movie');
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.historyCleared), duration: const Duration(seconds: 2)));
            },
            child: Text(l10n.clearHistory, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _removeFromHistory(BuildContext context, WidgetRef ref, Channel channel) {
    ref.read(playerRepositoryProvider).deleteProgress(channel.streamId, 'movie');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.removedFromHistory), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(_continueWatchingMoviesProvider);
    return channelsAsync.when(
      data: (channels) {
        if (channels.isEmpty) return Center(child: Text(l10n.noHistory, style: TextStyle(color: AppColors.textTertiaryDark)));
        final filtered = searchQuery.isEmpty ? channels : channels.where((c) => c.name.toLowerCase().contains(searchQuery)).toList();
        if (filtered.isEmpty) return Center(child: Text(l10n.noHistory, style: TextStyle(color: AppColors.textTertiaryDark)));
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
                    icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.red),
                    label: Text(l10n.clearHistory, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _PosterGrid(
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

class _PosterGrid extends StatefulWidget {
  final List<Channel> channels;
  final Function(Channel) onPlay;
  final Function(Channel) onHover;
  final Function(Channel) onTap;
  final VoidCallback? onLeftEdge;
  final Function(Channel)? onLongPress;
  const _PosterGrid({required this.channels, required this.onPlay, required this.onHover, required this.onTap, this.onLeftEdge, this.onLongPress});

  @override
  State<_PosterGrid> createState() => _PosterGridState();
}

class _PosterGridState extends State<_PosterGrid> {
  bool _autoHovered = false;

  @override
  void initState() {
    super.initState();
    // Auto-select first channel for hero display on initial load
    if (widget.channels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_autoHovered) {
          _autoHovered = true;
          widget.onHover(widget.channels.first);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _PosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If channels changed from empty to non-empty, auto-hover first
    if (!_autoHovered && widget.channels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoHovered) {
          _autoHovered = true;
          widget.onHover(widget.channels.first);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cols = context.gridColumns;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(context.horizontalPadding, 4, context.horizontalPadding, 60),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: widget.channels.length,
      itemBuilder: (_, i) => _PosterCard(
        channel: widget.channels[i],
        onPlay: () => widget.onPlay(widget.channels[i]),
        onHover: () => widget.onHover(widget.channels[i]),
        onTap: () => widget.onTap(widget.channels[i]),
        isLeftEdge: i % cols == 0,
        onLeftEdge: widget.onLeftEdge,
        onLongPress: widget.onLongPress != null ? () => widget.onLongPress!(widget.channels[i]) : null,
      ),
    );
  }
}

class _PosterCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onPlay;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final bool isLeftEdge;
  final VoidCallback? onLeftEdge;
  final VoidCallback? onLongPress;
  const _PosterCard({required this.channel, required this.onPlay, required this.onHover, required this.onTap, this.isLeftEdge = false, this.onLeftEdge, this.onLongPress});
  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  bool _isHovered = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _scale = Tween(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _update() { (_isFocused || _isHovered) ? _ctrl.forward() : _ctrl.reverse(); }

  @override
  Widget build(BuildContext context) {
    final active = _isFocused || _isHovered;
    return Focus(
      onFocusChange: (f) { setState(() => _isFocused = f); _update(); if (f) widget.onHover(); },
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.select || e.logicalKey == LogicalKeyboardKey.enter) { widget.onTap(); return KeyEventResult.handled; }
          // D-pad Left on leftmost column → open category sidebar
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft && widget.isLeftEdge && widget.onLeftEdge != null) {
            widget.onLeftEdge!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) { setState(() => _isHovered = true); _update(); widget.onHover(); },
        onExit: (_) { setState(() => _isHovered = false); _update(); },
        child: GestureDetector(
          onTap: () { widget.onHover(); widget.onTap(); },
          onLongPress: widget.onLongPress,
          child: AnimatedBuilder(animation: _scale, builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: active ? AppColors.primary : Colors.transparent, width: active ? 2 : 0),
                boxShadow: active ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 14)] : [],
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(7), child: Stack(fit: StackFit.expand, children: [
                widget.channel.streamIcon != null
                    ? Image.network(widget.channel.streamIcon!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
                    : _ph(),
                Positioned.fill(child: Container(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)], stops: const [0.55, 1.0])))),
                // Play overlay on hover
                if (active)
                  Center(child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.85), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                  )),
                if (widget.channel.rating != null && widget.channel.rating! > 0)
                  Positioned(top: 5, right: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star, color: AppColors.gold, size: 10), const SizedBox(width: 2),
                      Text(widget.channel.rating!.toStringAsFixed(1), style: const TextStyle(color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w700)),
                    ]),
                  )),
                if (widget.channel.year != null)
                  Positioned(top: 5, left: 5, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                    child: Text(widget.channel.year!, style: const TextStyle(color: Colors.white70, fontSize: 9)),
                  )),
                Positioned(bottom: 6, left: 6, right: 6, child: Text(widget.channel.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ])),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ph() {
    final i = widget.channel.name.isNotEmpty ? widget.channel.name.substring(0, widget.channel.name.length.clamp(0, 2)).toUpperCase() : '?';
    return Container(color: AppColors.surfaceElevatedDark, child: Center(child: Text(i, style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 22, fontWeight: FontWeight.w800))));
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final _movieCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(contentRepositoryProvider).watchCategories('movie');
});

final _movieChannelsProvider = StreamProvider.family<List<Channel>, String>((ref, categoryId) {
  return ref.watch(contentRepositoryProvider).watchChannels(categoryId, type: 'movie');
});

final _allMoviesProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchAllChannelsByType('movie');
});

final _favMovieIdsProvider = StreamProvider<List<int>>((ref) {
  return ref.watch(favoritesRepositoryProvider).watchFavoriteStreamIds('movie');
});

final _favChannelsProvider = StreamProvider.family<List<Channel>, List<int>>((ref, ids) {
  return ref.watch(contentRepositoryProvider).watchFavoriteChannels('movie', ids);
});

final _continueWatchingMoviesProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchContinueWatching('movie');
});

final _playbackProgressProvider = StreamProvider.family<PlaybackProgressData?, ({int streamId, String type})>((ref, params) {
  return ref.watch(contentRepositoryProvider).watchPlaybackProgress(params.streamId, params.type);
});

// ─── Focusable Icon Button (for category sidebar toggle etc.) ──────────────

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _FocusableIconButton({required this.icon, required this.tooltip, required this.onTap});
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
                color: isActive ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
              ),
              child: Icon(widget.icon, color: isActive ? AppColors.primary : AppColors.textSecondaryDark, size: 22),
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
  const _SearchButton({required this.hintText, this.isActive = false, required this.onTap, this.onClear});
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
            color: _isFocused ? AppColors.surfaceElevatedDark : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: widget.isActive ? AppColors.primary : AppColors.textTertiaryDark, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.hintText,
                  style: TextStyle(
                    color: widget.isActive ? AppColors.textDark : AppColors.textTertiaryDark,
                    fontSize: 14,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClear != null)
                GestureDetector(
                  onTap: widget.onClear,
                  child: const Icon(Icons.close, color: AppColors.textTertiaryDark, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
