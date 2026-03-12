import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/widgets/content/content_list.dart';
import 'package:lifeostv/presentation/widgets/content/hero_banner.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lifeostv/utils/responsive.dart';
import 'package:lifeostv/utils/platform_utils.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerSync();
    });
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
    final continueWatchingAsync = ref.watch(dashboardContinueWatchingProvider);
    final account = ref.watch(currentAccountProvider);

    // Hero items: combine movies + series, prioritize those with backdrop
    final heroItems = [
      ...?recentMoviesAsync.value?.take(5),
      ...?recentSeriesAsync.value?.take(5),
    ]..sort((a, b) {
      final aHas = a.backdropPath != null ? 0 : 1;
      final bHas = b.backdropPath != null ? 0 : 1;
      return aHas.compareTo(bHas);
    });

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _triggerSync,
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mobile logo bar — only on mobile, right above hero
                  if (isMobilePlatform)
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      color: AppColors.backgroundDark,
                      child: Row(
                        children: [
                          const Text(
                            'Life',
                            style: TextStyle(
                              color: AppColors.textDark,
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

                  // Hero Banner with VOD info
                  HeroBanner(
                    channels: heroItems,
                    vodInfo: _heroVodInfo,
                    onItemChanged: _onHeroItemChanged,
                    onPlay: _playChannel,
                    onDetails: _openDetail,
                    onTrailer: _openTrailer,
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
                            style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
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
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // Continue Watching (movies + series with unfinished progress)
                  continueWatchingAsync.when(
                    data: (channels) => channels.isNotEmpty
                        ? ContentList(
                            title: l10n.continueWatching,
                            icon: Icons.play_circle_outline,
                            channels: channels,
                            onChannelTap: (ch) => _openDetail(ch),
                            onChannelFocus: (_) {},
                            trailing: IconButton(
                              onPressed: _clearContinueWatching,
                              icon: const Icon(Icons.delete_sweep, size: 18),
                              color: AppColors.textTertiaryDark,
                              tooltip: l10n.clearHistory,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  // Recently Added Movies → tap opens detail page
                  recentMoviesAsync.when(
                    data: (channels) => ContentList(
                      title: l10n.recentlyAddedMovies,
                      icon: Icons.movie_outlined,
                      channels: channels,
                      onChannelTap: _openDetail,
                      onChannelFocus: (_) {},
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, __) => const SizedBox.shrink(),
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
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, __) => const SizedBox.shrink(),
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
                    ),
                    loading: () => _buildLoadingRow(),
                    error: (_, __) => const SizedBox.shrink(),
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
        backgroundColor: AppColors.surfaceElevatedDark,
        title: Text(l10n.clearHistory, style: const TextStyle(color: AppColors.textDark)),
        content: Text(l10n.clearHistoryConfirm, style: const TextStyle(color: AppColors.textSecondaryDark)),
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

  /// Open YouTube trailer
  void _openTrailer(Channel channel) {
    final trailer = _heroVodInfo?.youtubeTrailer ?? channel.youtubeTrailer;
    if (trailer == null || trailer.isEmpty) return;

    final url = trailer.startsWith('http')
        ? trailer
        : 'https://www.youtube.com/watch?v=$trailer';

    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildNoAccountBanner(BuildContext c, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, color: AppColors.accent, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.noAccountFound, style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(l10n.noAccountWarning, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
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
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => Container(
          width: 140,
          height: 210,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
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
final dashboardContinueWatchingProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchAllContinueWatching();
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
