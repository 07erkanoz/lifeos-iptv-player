import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_branches.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_provider.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_registry.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/taste_profile_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/hero_billboard_provider.dart';
import 'package:lifeostv/presentation/widgets/ai/dashboard_greeting.dart';
import 'package:lifeostv/presentation/widgets/ai/mood_selector.dart';
import 'package:lifeostv/presentation/widgets/ai/personalized_picks_rail.dart';
import 'package:lifeostv/presentation/widgets/ai/taste_wizard_sheet.dart';
import 'package:lifeostv/presentation/widgets/ai/weekly_digest_banner.dart';
import 'package:lifeostv/presentation/widgets/ai/tonight_chat_sheet.dart';
import 'package:lifeostv/presentation/widgets/content/content_list.dart';
import 'package:lifeostv/presentation/widgets/content/hero_banner.dart';
import 'package:lifeostv/presentation/widgets/content/live_now_on_air_rail.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/repositories/watchlist_repository.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/utils/youtube_trailer.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lifeostv/utils/responsive.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/core/platform_helper.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSyncing = false;

  // Hero VOD info (fetched when hero item changes)
  HeroVodInfo? _heroVodInfo;
  int? _heroInfoStreamId; // Track which channel the info belongs to

  /// FocusNode for the hero banner so the registry can target it as
  /// the dashboard's branch primary (sidebar → right enters here).
  final FocusNode _heroFocusNode = FocusNode(debugLabel: 'DashboardHero');

  /// Scroll controller for the dashboard list. Used to snap back to the
  /// very top when D-pad focus re-enters the hero — otherwise the hero
  /// stays clipped (the rails' focus-scroll never scrolls *up* past
  /// the hero's top edge).
  final ScrollController _dashScroll = ScrollController();

  void _scrollDashboardToTop() {
    if (!_dashScroll.hasClients) return;
    _dashScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Stable callback registered with [TvFocusRegistry]. Captured once
  /// so register/unregister identity matches across the widget life.
  late final VoidFocusCallback _branchPrimaryCb;

  @override
  void initState() {
    super.initState();
    _branchPrimaryCb = _focusHero;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _triggerSync();
      ref.read(tvFocusRegistryProvider).registerBranchPrimary(
            TvBranchIndex.dashboard,
            _branchPrimaryCb,
          );
      _maybeShowTasteWizard();
    });
  }

  /// Show the AI taste-onboarding wizard exactly once per user.
  ///
  /// Fires only when:
  ///   * the user has a Gemini key configured,
  ///   * the wizard hasn't been completed before, and
  ///   * the AI providers truly have no signal to ground on
  ///     (< 3 favourites AND < 5 history rows).
  ///
  /// Waits 1.2 seconds after first paint so the dashboard finishes
  /// settling before the modal slides up — appearing during the
  /// hero shimmer feels janky.
  Future<void> _maybeShowTasteWizard() async {
    final settings = ref.read(settingsProvider);
    if (!settings.hasAiKey) return;
    if (settings.tasteWizardCompleted) return;

    final db = ref.read(appDatabaseProvider);
    final favCount = await (db.select(db.favorites)..limit(3)).get();
    if (favCount.length >= 3) {
      // Already has favourites — they have a taste profile.
      // Flip the flag so we don't re-check this on every open.
      ref.read(settingsProvider.notifier).updateSettings(
          settings.copyWith(tasteWizardCompleted: true));
      return;
    }
    final histCount =
        await (db.select(db.playbackProgress)..limit(5)).get();
    if (histCount.length >= 5) {
      ref.read(settingsProvider.notifier).updateSettings(
          settings.copyWith(tasteWizardCompleted: true));
      return;
    }

    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await TasteWizardSheet.show(context);
  }

  @override
  void dispose() {
    ref.read(tvFocusRegistryProvider).unregisterBranchPrimary(
          TvBranchIndex.dashboard,
          _branchPrimaryCb,
        );
    _heroFocusNode.dispose();
    _dashScroll.dispose();
    super.dispose();
  }

  /// Branch-primary target: focus the hero banner so the user lands
  /// on the most prominent action (play / open detail) when they
  /// arrow right out of the sidebar.
  void _focusHero() {
    if (!mounted) return;
    if (_heroFocusNode.canRequestFocus) {
      _heroFocusNode.requestFocus();
    }
  }

  /// Left-edge target wired into every carousel's first item via
  /// [ContentList.onCarouselLeftEdge]. Hands focus back to the main
  /// sidebar through the registry — no findAncestor hack needed.
  void _focusMainSidebar() {
    final ok = ref.read(tvFocusRegistryProvider).requestMainSidebar();
    if (!ok) {
      // First-frame fallback before AppSidebar finished registering.
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.left);
    }
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      // initialSyncProvider is throttled - only syncs if 6+ hours passed
      await ref.read(initialSyncProvider.future);
    } catch (_) {}
    if (mounted) setState(() => _isSyncing = false);
  }

  /// Fetch VOD info when hero item changes
  /// Uses DB cache first - only hits API if no cached data exists
  void _onHeroItemChanged(Channel channel) async {
    // Don't fetch for live channels
    if (channel.type == 'live') {
      setState(() { _heroVodInfo = null; _heroInfoStreamId = channel.streamId; });
      return;
    }

    // If already fetched for this channel, skip
    if (_heroInfoStreamId == channel.streamId && _heroVodInfo != null) return;

    setState(() { _heroInfoStreamId = channel.streamId; });

    // Check if DB already has cached metadata (genre, plot, backdrop)
    // If yes, use it directly - NO API call needed (server-friendly)
    if (channel.genre != null || channel.plot != null || channel.backdropPath != null) {
      setState(() {
        _heroVodInfo = HeroVodInfo(
          plot: channel.plot,
          genre: channel.genre,
          director: channel.director,
          cast: channel.cast,
          rating: channel.rating,
          youtubeTrailer: channel.youtubeTrailer,
          backdropUrl: channel.backdropPath,
        );
      });
      return; // Already have cached data, skip API
    }

    // No cached data - clear and fetch from API
    setState(() { _heroVodInfo = null; });

    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;

    final api = ref.read(xtreamApiServiceProvider);

    try {
      Map<String, dynamic>? result;
      if (channel.type == 'movie') {
        result = await api.getVODInfo(account.url, account.username ?? '', account.password ?? '', channel.streamId);
      } else if (channel.type == 'series') {
        result = await api.getSeriesInfo(account.url, account.username ?? '', account.password ?? '', channel.streamId);
      }

      if (!mounted || _heroInfoStreamId != channel.streamId) return;

      if (result != null) {
        final infoRaw = result['info'];
        final info = infoRaw is Map<String, dynamic> ? infoRaw : null;
        if (info != null) {
          // Extract backdrop
          String? backdrop;
          if (info['backdrop_path'] is List && (info['backdrop_path'] as List).isNotEmpty) {
            backdrop = info['backdrop_path'][0]?.toString();
          } else if (info['movie_image'] != null && info['movie_image'].toString().isNotEmpty) {
            backdrop = info['movie_image'].toString();
          } else if (info['cover'] != null && info['cover'].toString().isNotEmpty) {
            backdrop = info['cover'].toString();
          }

          final trailer = info['youtube_trailer']?.toString();
          final ratingStr = info['rating']?.toString() ?? info['rating_5based']?.toString();
          double? rating = double.tryParse(ratingStr ?? '');
          // Some APIs return rating on 5-based scale
          if (rating != null && rating <= 5 && info['rating_5based'] != null) {
            rating = rating * 2;
          }

          // Duration
          String? duration;
          final dur = info['duration']?.toString() ?? info['episode_run_time']?.toString();
          if (dur != null && dur.isNotEmpty) {
            duration = dur.contains(':') ? dur : '$dur min';
          }

          setState(() {
            _heroVodInfo = HeroVodInfo(
              plot: info['plot']?.toString() ?? info['description']?.toString(),
              genre: info['genre']?.toString(),
              director: info['director']?.toString(),
              cast: info['cast']?.toString(),
              rating: rating,
              duration: duration,
              youtubeTrailer: (trailer != null && trailer.isNotEmpty) ? trailer : null,
              backdropUrl: backdrop,
            );
          });

          // Cache ALL metadata to DB for future hero banner use (no repeated API calls)
          final genreStr = info['genre']?.toString();
          final plotStr = info['plot']?.toString() ?? info['description']?.toString();
          final directorStr = info['director']?.toString();
          final castStr = info['cast']?.toString();
          if (backdrop != null || (trailer != null && trailer.isNotEmpty) ||
              (genreStr != null && genreStr.isNotEmpty) || (plotStr != null && plotStr.isNotEmpty)) {
            ref.read(contentRepositoryProvider).updateChannelMetadata(
              channel.streamId, channel.type,
              backdropPath: backdrop,
              youtubeTrailer: (trailer != null && trailer.isNotEmpty) ? trailer : null,
              genre: (genreStr != null && genreStr.isNotEmpty) ? genreStr : null,
              plot: (plotStr != null && plotStr.isNotEmpty) ? plotStr : null,
              director: (directorStr != null && directorStr.isNotEmpty) ? directorStr : null,
              castInfo: (castStr != null && castStr.isNotEmpty) ? castStr : null,
            );
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recentMoviesAsync = ref.watch(recentChannelsProvider('movie'));
    final recentSeriesAsync = ref.watch(recentChannelsProvider('series'));
    final recentLiveAsync = ref.watch(recentChannelsProvider('live'));
    final favoritesAsync = ref.watch(dashboardFavoritesProvider);
    final watchlistAsync = ref.watch(dashboardWatchlistProvider);
    final continueWatchingAsync = ref.watch(dashboardContinueWatchingProvider);
    final account = ref.watch(currentAccountProvider);

    // Hero items: combine movies + series, prioritize those with backdrop
    final fallbackHeroItems = [
      ...?recentMoviesAsync.value?.take(5),
      ...?recentSeriesAsync.value?.take(5),
    ]..sort((a, b) {
      final aHas = a.backdropPath != null ? 0 : 1;
      final bHas = b.backdropPath != null ? 0 : 1;
      return aHas.compareTo(bHas);
    });

    // AI hero billboard — present only when the user has a Gemini
    // key and the provider successfully resolved. Replaces the
    // recent-movies/series hero items with a tighter AI-curated
    // selection that includes per-item hook taglines. Falls back
    // to [fallbackHeroItems] otherwise so the dashboard for non-AI
    // users (or while the provider is loading / failed) looks
    // identical to before this commit.
    final aiBillboard = ref.watch(heroBillboardProvider).value;
    final heroItems = (aiBillboard != null && !aiBillboard.isEmpty)
        ? aiBillboard.channels
        : fallbackHeroItems;
    final aiTaglines = aiBillboard?.taglines;

    // AI assistant entry — only renders when the user has a Gemini
    // key configured. We hide the FAB entirely rather than showing
    // it disabled because the chat has nothing meaningful to do
    // without a key, and a disabled button is a worse signal than no
    // button at all.
    // TV-lite: no AI assistant on Android TV.
    final hasAiKey = ref.watch(settingsProvider).hasAiKey &&
        !PlatformHelper.isTV;

    return Scaffold(
      floatingActionButton: hasAiKey
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.aiChatTitle),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const TonightChatSheet(),
              ),
            )
          : null,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _triggerSync,
            color: AppColors.primary,
            child: SingleChildScrollView(
              controller: _dashScroll,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mobile logo bar — only on mobile, right above hero
                  if (isMobilePlatform)
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      color: AppColors.background(context),
                      child: Row(
                        children: [
                          Text(
                            'Life',
                            style: TextStyle(
                              color: AppColors.text(context),
                              fontWeight: FontWeight.w300,
                              fontSize: 18,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 1),
                          const Text(
                            'OS',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5484D),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'TV',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // AI greeting banner — renders nothing without a
                  // Gemini key (no fallback hardcoded text either,
                  // the dashboard for non-AI users looks unchanged).
                  const DashboardGreeting(),

                  // Hero Banner with VOD info. Wrapped in a focus
                  // watcher: when D-pad focus enters ANY hero control
                  // (Play / Trailer / +List), snap the list back to the
                  // top so the whole hero is shown instead of staying
                  // clipped under the rail the user came from.
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (hasFocus) {
                      if (hasFocus) _scrollDashboardToTop();
                    },
                    child: HeroBanner(
                      channels: heroItems,
                      vodInfo: _heroVodInfo,
                      onItemChanged: _onHeroItemChanged,
                      onPlay: _playChannel,
                      onDetails: _openDetail,
                      onTrailer: _openTrailer,
                      playFocusNode: _heroFocusNode,
                      onLeftEdge: _focusMainSidebar,
                      aiTaglines: aiTaglines,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Syncing indicator
                  if (_isSyncing)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding > 12 ? 24 : 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.syncContent,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // No account warning
                  if (account.value == null && !account.isLoading)
                    _buildNoAccountBanner(context, l10n),

                  const SizedBox(height: 8),

                  // Favorites carousel
                  favoritesAsync.when(
                    data: (channels) => channels.isNotEmpty
                        ? ContentList(
                            title: l10n.myFavorites,
                            icon: Icons.favorite,
                            channels: channels,
                            onChannelTap: (ch) => ch.type == 'live' ? _playChannel(ch) : _openDetail(ch),
                            onChannelFocus: (_) {},
                            onCarouselLeftEdge: _focusMainSidebar,
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  // Weekly digest — once-a-week AI banner of new
                  // additions matching the user's taste. Hides
                  // itself when there's no key, no recent content,
                  // or the user dismissed within the last 7 days.
                  WeeklyDigestBanner(onTap: _openDetail),

                  // "Sana Özel" — AI-curated personalised rail.
                  // Hides itself entirely when the user has no
                  // Gemini key, so the dashboard for non-AI users
                  // looks identical to before this commit.
                  PersonalizedPicksRail(onTap: _openDetail),

                  // Mood chip selector — taps spawn an ephemeral
                  // mood-based rail right below the chips. Also
                  // hides itself when no Gemini key is configured.
                  MoodSelector(onTap: _openDetail),

                  // "Şu an canlıda" — EPG-driven rail of live
                  // channels currently broadcasting. Hides itself
                  // when no EPG data is available (rail's own
                  // provider returns []).
                  LiveNowOnAirRail(onTap: (ch) => _openDetail(ch)),

                  // Continue Watching (movies + series with unfinished progress)
                  continueWatchingAsync.when(
                    data: (channels) => channels.isNotEmpty
                        ? ContentList(
                            title: l10n.continueWatching,
                            icon: Icons.play_circle_outline,
                            channels: channels,
                            onChannelTap: (ch) => _openDetail(ch),
                            onChannelFocus: (_) {},
                            onCarouselLeftEdge: _focusMainSidebar,
                            trailing: IconButton(
                              onPressed: _clearContinueWatching,
                              icon: const Icon(Icons.delete_sweep, size: 18),
                              color: AppColors.textTertiary(context),
                              tooltip: l10n.clearHistory,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  // Watchlist ("My List") — items the user saved for later.
                  watchlistAsync.when(
                    data: (channels) => channels.isNotEmpty
                        ? ContentList(
                            title: l10n.watchlist,
                            icon: Icons.bookmark_outlined,
                            channels: channels,
                            onChannelTap: (ch) => _openDetail(ch),
                            onChannelFocus: (_) {},
                            onCarouselLeftEdge: _focusMainSidebar,
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  // Recently Added Movies → tap opens detail page
                  recentMoviesAsync.when(
                    data: (channels) => ContentList(
                      title: l10n.recentlyAddedMovies,
                      icon: Icons.movie_outlined,
                      channels: channels,
                      onChannelTap: _openDetail,
                      onChannelFocus: (_) {},
                      onCarouselLeftEdge: _focusMainSidebar,
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 14),

                  // Recently Added Series → tap opens detail page
                  recentSeriesAsync.when(
                    data: (channels) => ContentList(
                      title: l10n.recentlyAddedSeries,
                      icon: Icons.tv_outlined,
                      channels: channels,
                      onChannelTap: _openDetail,
                      onChannelFocus: (_) {},
                      onCarouselLeftEdge: _focusMainSidebar,
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 14),

                  // Live TV Channels → tap plays directly
                  recentLiveAsync.when(
                    data: (channels) => ContentList(
                      title: l10n.liveTV,
                      icon: Icons.live_tv_outlined,
                      channels: channels,
                      onChannelTap: _playChannel,
                      onChannelFocus: (_) {},
                      onCarouselLeftEdge: _focusMainSidebar,
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to detail page (movies/series screen with detail panel open)
  void _openDetail(Channel channel) {
    if (channel.type == 'live') {
      // Live channels play directly
      _playChannel(channel);
      return;
    }

    // Set the pending detail channel so the target screen opens it
    ref.read(pendingDetailChannelProvider.notifier).set(channel);

    // Navigate to the corresponding section (movies or series)
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      if (channel.type == 'movie') {
        shell.goBranch(2); // Movies tab
      } else if (channel.type == 'series') {
        shell.goBranch(3); // Series tab
      }
    }
  }

  /// Play channel directly
  void _playChannel(Channel channel) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noActiveAccount)),
      );
      return;
    }

    final settings = ref.read(settingsProvider);
    String url;
    VideoType type;

    // M3U accounts: use direct stream URL
    if (account.type == 'm3u' && channel.streamUrl != null && channel.streamUrl!.isNotEmpty) {
      url = channel.streamUrl!;
      type = channel.type == 'movie' ? VideoType.movie
          : channel.type == 'series' ? VideoType.series
          : VideoType.live;
    } else {
      switch (channel.type) {
        case 'live':
          url = StreamUrlBuilder.live(account.url, account.username ?? '', account.password ?? '', channel.streamId, quality: settings.streamQuality);
          type = VideoType.live;
          break;
        case 'movie':
          url = StreamUrlBuilder.movie(account.url, account.username ?? '', account.password ?? '', channel.streamId);
          type = VideoType.movie;
          break;
        default:
          url = StreamUrlBuilder.series(account.url, account.username ?? '', account.password ?? '', channel.streamId);
          type = VideoType.series;
      }
    }

    context.push('/player', extra: {
      'url': url,
      'title': channel.name,
      'type': type,
      'logo': channel.streamIcon,
      'plot': channel.plot,
      'genre': channel.genre,
      'year': channel.year,
      'director': channel.director,
      'cast': channel.cast,
      'rating': channel.rating,
    });
  }

  void _clearContinueWatching() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated(ctx),
        title: Text(l10n.clearHistory, style: TextStyle(color: AppColors.text(ctx))),
        content: Text(
          l10n.clearHistoryConfirm,
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () async {
              final repo = ref.read(playerRepositoryProvider);
              await repo.clearAllProgress('movie');
              await repo.clearAllProgress('series');
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.historyCleared), duration: const Duration(seconds: 2)),
                );
              }
            },
            child: Text(l10n.clearHistory, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Open YouTube trailer.
  /// Falls back to a YouTube search query for "<name> <year> trailer" when
  /// the server (or our DB cache) didn't supply a canonical trailer URL —
  /// guarantees every VOD has a working trailer affordance.
  void _openTrailer(Channel channel) {
    final apiTrailer = _heroVodInfo?.youtubeTrailer;
    if (apiTrailer != null && apiTrailer.trim().isNotEmpty) {
      final url = apiTrailer.startsWith('http')
          ? apiTrailer
          : 'https://www.youtube.com/watch?v=$apiTrailer';
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    openTrailerForChannel(channel);
  }

  Widget _buildNoAccountBanner(BuildContext c, AppLocalizations l10n) {
    final isDark = Theme.of(c).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final title = isDark ? AppColors.textDark : AppColors.textLight;
    final body = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, color: AppColors.accent, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.noAccountFound, style: TextStyle(color: title, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(l10n.noAccountWarning, style: TextStyle(color: body, fontSize: 13)),
          ]),
        ),
        TextButton(onPressed: () => c.go('/settings'), child: Text(l10n.goToSettings)),
      ]),
    );
  }

  Widget _buildLoadingRow() {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding > 12 ? 24 : 12),
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => Container(
          width: 140,
          height: 210,
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

final recentChannelsProvider = StreamProvider.family<List<Channel>, String>((ref, type) {
  return ref.watch(contentRepositoryProvider).watchRecentChannels(type);
});

/// Combined continue watching provider: movies + series with unfinished progress, sorted by updatedAt
final dashboardContinueWatchingProvider = StreamProvider<List<Channel>>((ref) async* {
  // Respect the user's "Continue watching" toggle — when off, the rail
  // shows nothing (the .when below renders empty → no rail).
  if (!ref.watch(settingsProvider).continueWatchingEnabled) {
    yield const <Channel>[];
    return;
  }
  // Base stream — last-watched-first, the deterministic answer.
  final baseStream =
      ref.watch(contentRepositoryProvider).watchAllContinueWatching();

  await for (final base in baseStream) {
    // Skip the AI step when there's nothing to rerank (cold list,
    // single item, or AI disabled). Yield the base list unchanged so
    // the user still sees their history immediately.
    //
    // Two gates here so we never accidentally call Gemini when the
    // user has opted out of AI: `hasAiKey` from settings AND
    // `geminiServiceProvider` returning a non-null instance. The
    // provider already checks the key, but reading hasAiKey first
    // lets us skip even the service lookup on the cold path.
    final hasAiKey = ref.read(settingsProvider).hasAiKey;
    final gemini = ref.read(geminiServiceProvider);
    if (!hasAiKey || gemini == null || base.length < 3) {
      yield base;
      continue;
    }

    // Optimistic emit — show the raw list while the rerank is
    // pending. Without this the rail flashes blank for the 1-2 s
    // it takes Gemini to reorder.
    yield base;

    try {
      final taste = await ref.read(tasteProfileProvider.future);
      if (taste.isCold) continue; // not enough signal to rerank

      // Build the compact item list the prompt expects. progressRatio
      // gives the AI a "how close to finishing" signal; days since
      // last watch lets it deprioritise stale items.
      final now = DateTime.now();
      final db = ref.read(appDatabaseProvider);
      final progressRows = await (db.select(db.playbackProgress)
            ..where((t) =>
                t.streamId.isIn(base.map((c) => c.streamId).toList())))
          .get();
      final progressByKey = {
        for (final p in progressRows) '${p.streamId}|${p.type}': p,
      };
      final items = base.map((c) {
        final p = progressByKey['${c.streamId}|${c.type}'];
        final ratio = (p == null || p.duration <= 0)
            ? 0.0
            : (p.position / p.duration).clamp(0.0, 1.0);
        final days = p == null
            ? 0
            : now.difference(p.updatedAt).inDays;
        return {
          'streamId': c.streamId,
          'title': c.name,
          'type': c.type,
          if (c.genre != null && c.genre!.isNotEmpty) 'genre': c.genre,
          'progressRatio': double.parse(ratio.toStringAsFixed(2)),
          'daysSinceLastWatch': days,
        };
      }).toList();

      final lang = ref.read(settingsProvider).language.name == 'system'
          ? 'tr'
          : ref.read(settingsProvider).language.name;

      final order = await gemini.rerankContinueWatching(
        items: items,
        tasteProfile: taste.toPromptJson(),
        timeOfDay: _bucketOfDay(now),
        targetLanguage: lang,
      );

      if (order == null || order.isEmpty) continue;

      // Reorder by the AI's ranking. We've already validated the id
      // set inside the Gemini method so this is just a sort.
      final byId = {for (final c in base) c.streamId: c};
      final ranked = order
          .map((id) => byId[id])
          .whereType<Channel>()
          .toList();
      if (ranked.length == base.length) {
        yield ranked;
      }
    } catch (e) {
      debugPrint('[continueWatching] rerank skipped: $e');
      // Already yielded the base list above — nothing else to do.
    }
  }
});

String _bucketOfDay(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'sabah';
  if (h >= 11 && h < 17) return 'öğle';
  if (h >= 17 && h < 22) return 'akşam';
  return 'gece';
}

/// Combined watchlist provider: movies + series the user saved for later,
/// joined with the channel rows so PosterCard can render them. Mirrors the
/// favorites pattern (asyncMap over the watchlist stream → channel lookup).
final dashboardWatchlistProvider = StreamProvider<List<Channel>>((ref) {
  final wlRepo = ref.watch(watchlistRepositoryProvider);
  final contentRepo = ref.watch(contentRepositoryProvider);

  return wlRepo.watchAll().asyncMap((items) async {
    if (items.isEmpty) return <Channel>[];

    final movieIds =
        items.where((w) => w.streamType == 'movie').map((w) => w.streamId).toList();
    final seriesIds =
        items.where((w) => w.streamType == 'series').map((w) => w.streamId).toList();

    final chunks = await Future.wait([
      if (movieIds.isNotEmpty)
        contentRepo.watchFavoriteChannels('movie', movieIds).first
      else
        Future.value(<Channel>[]),
      if (seriesIds.isNotEmpty)
        contentRepo.watchFavoriteChannels('series', seriesIds).first
      else
        Future.value(<Channel>[]),
    ]);

    final channels = <Channel>[...chunks[0], ...chunks[1]];

    // Preserve watchlist order (newest-first).
    final order = <String, int>{
      for (var i = 0; i < items.length; i++) '${items[i].streamType}:${items[i].streamId}': i,
    };
    channels.sort((a, b) {
      final ai = order['${a.type}:${a.streamId}'] ?? 1 << 20;
      final bi = order['${b.type}:${b.streamId}'] ?? 1 << 20;
      return ai.compareTo(bi);
    });

    return channels;
  });
});

/// Combined favorites provider: watches all favorites, then joins with channels for full data
final dashboardFavoritesProvider = StreamProvider<List<Channel>>((ref) {
  final favRepo = ref.watch(favoritesRepositoryProvider);
  final contentRepo = ref.watch(contentRepositoryProvider);

  return favRepo.watchAllFavorites().asyncMap((favs) async {
    if (favs.isEmpty) return <Channel>[];

    final movieIds =
        favs.where((f) => f.streamType == 'movie').map((f) => f.streamId).toList();
    final seriesIds =
        favs.where((f) => f.streamType == 'series').map((f) => f.streamId).toList();
    final liveIds =
        favs.where((f) => f.streamType == 'live').map((f) => f.streamId).toList();

    final chunks = await Future.wait([
      if (movieIds.isNotEmpty)
        contentRepo.watchFavoriteChannels('movie', movieIds).first
      else
        Future.value(<Channel>[]),
      if (seriesIds.isNotEmpty)
        contentRepo.watchFavoriteChannels('series', seriesIds).first
      else
        Future.value(<Channel>[]),
      if (liveIds.isNotEmpty)
        contentRepo.watchFavoriteChannels('live', liveIds).first
      else
        Future.value(<Channel>[]),
    ]);

    final channels = <Channel>[
      ...chunks[0],
      ...chunks[1],
      ...chunks[2],
    ];

    // Keep dashboard order aligned with favorites table (latest first).
    final order = <String, int>{
      for (var i = 0; i < favs.length; i++) '${favs[i].streamType}:${favs[i].streamId}': i,
    };
    channels.sort((a, b) {
      final ai = order['${a.type}:${a.streamId}'] ?? 1 << 20;
      final bi = order['${b.type}:${b.streamId}'] ?? 1 << 20;
      return ai.compareTo(bi);
    });

    return channels;
  });
});
