import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/presentation/widgets/layout/sidebar.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'dart:async';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _liveCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchCategories('live');
});

final _liveChannelsProvider = StreamProvider.family<List<Channel>, String>((
  ref,
  categoryId,
) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchChannels(categoryId, type: 'live');
});

final _allLiveChannelsProvider = StreamProvider<List<Channel>>((ref) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchRecentChannels('live', limit: 500);
});

final _favLiveIdsProvider = StreamProvider<List<int>>((ref) {
  return ref.watch(favoritesRepositoryProvider).watchFavoriteStreamIds('live');
});

final _favLiveChannelsProvider =
    StreamProvider.family<List<Channel>, List<int>>((ref, ids) {
      return ref
          .watch(contentRepositoryProvider)
          .watchFavoriteChannels('live', ids);
    });

final _isLiveFavoriteProvider = StreamProvider.family<bool, int>((
  ref,
  streamId,
) {
  return ref
      .watch(favoritesRepositoryProvider)
      .watchIsFavorite(streamId, 'live');
});

const String _kFavoritesId = '__favorites__';
const String _kHistoryId = '__history__';

final _continueWatchingLiveProvider = StreamProvider<List<Channel>>((ref) {
  return ref.watch(contentRepositoryProvider).watchContinueWatching('live');
});

final _channelProgramsProvider = StreamProvider.family<List<Program>, int>((
  ref,
  channelId,
) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchPrograms(channelId);
});

/// EPG sync state - tracks if a batch sync is running
final _epgSyncingNotifier = ValueNotifier<bool>(false);

/// Per-channel EPG sync tracker (to avoid re-fetching same channel repeatedly)
final _epgSyncedChannels = <int>{};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kCategoryPanelWidth = 200.0;
const double _kChannelListWidth = 220.0;
const double _kChannelRowHeight = 56.0;
const double _kTimelineHeaderHeight = 36.0;
const double _kHourWidth = 360.0; // pixels per hour
const double _kCurrentTimeLineWidth = 2.0;

// ---------------------------------------------------------------------------
// LiveTvScreen
// ---------------------------------------------------------------------------

class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  String? _selectedCategoryId;
  bool _categoriesCollapsed = isMobilePlatform;
  Timer? _currentTimeTimer;
  DateTime _currentTime = DateTime.now();

  // Scroll controllers for synced scrolling
  final ScrollController _channelListScrollController = ScrollController();
  final ScrollController _epgVerticalScrollController = ScrollController();
  final ScrollController _epgHorizontalScrollController = ScrollController();

  // Focus node for channel list (to receive focus after sidebar collapse)
  final FocusNode _channelListFocusNode = FocusNode();
  // Focus scope for category sidebar (to receive focus when sidebar opens)
  final FocusScopeNode _categorySidebarScope = FocusScopeNode();

  // The base time for the EPG timeline (start of the current 2-hour window)
  late DateTime _timelineStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start timeline 1 hour before current time
    _timelineStart = DateTime(now.year, now.month, now.day, now.hour - 1);

    // Auto-select "Favorites" on mobile so the screen isn't blank
    if (isMobilePlatform) {
      _selectedCategoryId = _kFavoritesId;
    }

    // Sync vertical scrolling between channel list and EPG grid
    _channelListScrollController.addListener(_onChannelListScroll);
    _epgVerticalScrollController.addListener(_onEpgVerticalScroll);

    // Update current time every 30 seconds
    _currentTimeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });

    // Auto-scroll to current time after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime(animate: false);
      // Start EPG sync in background
      _triggerEpgSync();
    });
  }

  /// Trigger batch EPG sync for all live channels (throttled - max once per 2h)
  /// DB-first: existing programs are shown immediately from cache,
  /// this only fetches from server if last sync was >2 hours ago.
  Future<void> _triggerEpgSync() async {
    if (_epgSyncingNotifier.value) return;
    _epgSyncingNotifier.value = true;
    try {
      final account =
          ref.read(currentAccountProvider).value ??
          await ref.read(currentAccountProvider.future);
      if (account == null) return;
      final repo = ref.read(contentRepositoryProvider);
      // Cleanup old programs, then silently sync if needed (throttled in repo)
      await repo.cleanupOldPrograms();
      await repo.syncAllLiveEpg(account.id);
    } finally {
      _epgSyncingNotifier.value = false;
    }
  }

  @override
  void dispose() {
    _currentTimeTimer?.cancel();
    _channelListScrollController.removeListener(_onChannelListScroll);
    _epgVerticalScrollController.removeListener(_onEpgVerticalScroll);
    _channelListScrollController.dispose();
    _epgVerticalScrollController.dispose();
    _epgHorizontalScrollController.dispose();
    _channelListFocusNode.dispose();
    _categorySidebarScope.dispose();
    super.dispose();
  }

  bool _isSyncingScroll = false;

  void _onChannelListScroll() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    if (_epgVerticalScrollController.hasClients) {
      _epgVerticalScrollController.jumpTo(_channelListScrollController.offset);
    }
    _isSyncingScroll = false;
  }

  void _onEpgVerticalScroll() {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    if (_channelListScrollController.hasClients) {
      _channelListScrollController.jumpTo(_epgVerticalScrollController.offset);
    }
    _isSyncingScroll = false;
  }

  void _scrollToCurrentTime({bool animate = true}) {
    final now = DateTime.now();
    final offset =
        now.difference(_timelineStart).inMinutes * (_kHourWidth / 60.0);
    // Center on screen
    final screenWidth =
        MediaQuery.of(context).size.width -
        (_categoriesCollapsed ? 56 : _kCategoryPanelWidth) -
        _kChannelListWidth;
    final target = (offset - screenWidth / 2).clamp(0.0, double.infinity);

    if (_epgHorizontalScrollController.hasClients) {
      if (animate) {
        _epgHorizontalScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else {
        _epgHorizontalScrollController.jumpTo(target);
      }
    }
  }

  /// Select category (sidebar stays open, user closes via toggle button)
  void _selectCategory(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
  }

  /// Toggle category sidebar open/closed
  void _toggleCategorySidebar() {
    if (isMobilePlatform) {
      _showMobileCategorySheet();
      return;
    }
    setState(() => _categoriesCollapsed = !_categoriesCollapsed);
    if (_categoriesCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _channelListFocusNode.requestFocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FocusManager.instance.primaryFocus?.focusInDirection(
              TraversalDirection.down,
            );
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _categorySidebarScope.requestFocus();
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MOBILE LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout(
    AppLocalizations l10n,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    return Column(
      children: [
        _buildMobileTopBar(l10n),
        Expanded(
          child: _selectedCategoryId != null
              ? _buildMobileChannelList(l10n)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildMobileTopBar(AppLocalizations l10n) {
    String categoryLabel;
    IconData categoryIcon;
    if (_selectedCategoryId == _kFavoritesId) {
      categoryLabel = l10n.favoriteChannels;
      categoryIcon = Icons.favorite;
    } else if (_selectedCategoryId == _kHistoryId) {
      categoryLabel = l10n.watchHistory;
      categoryIcon = Icons.history;
    } else if (_selectedCategoryId == '__all__') {
      categoryLabel = l10n.allChannels;
      categoryIcon = Icons.grid_view_rounded;
    } else {
      categoryLabel = l10n.categories;
      categoryIcon = Icons.category;
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.backgroundDark,
        border: Border(
          bottom: BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _showMobileCategorySheet,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevatedDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(categoryIcon, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    categoryLabel,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: AppColors.textSecondaryDark,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileCategorySheet() {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.read(_liveCategoriesProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevatedDark,
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
                color: AppColors.textTertiaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.live_tv, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    l10n.categories,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textDark,
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
                  _buildMobileLiveCatTile(
                    l10n.favoriteChannels,
                    Icons.favorite,
                    _selectedCategoryId == _kFavoritesId,
                    () {
                      Navigator.pop(ctx);
                      _selectCategory(_kFavoritesId);
                    },
                  ),
                  _buildMobileLiveCatTile(
                    l10n.watchHistory,
                    Icons.history,
                    _selectedCategoryId == _kHistoryId,
                    () {
                      Navigator.pop(ctx);
                      _selectCategory(_kHistoryId);
                    },
                  ),
                  _buildMobileLiveCatTile(
                    l10n.allChannels,
                    Icons.grid_view_rounded,
                    _selectedCategoryId == '__all__',
                    () {
                      Navigator.pop(ctx);
                      _selectCategory('__all__');
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ...categoriesAsync.when(
                    data: (cats) => cats.map(
                      (cat) => _buildMobileLiveCatTile(
                        cat.name,
                        null,
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

  Widget _buildMobileLiveCatTile(
    String name,
    IconData? icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedColor: AppColors.primary,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
      leading: icon != null
          ? Icon(
              icon,
              size: 18,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.textTertiaryDark,
            )
          : (isSelected
                ? const Icon(Icons.check_circle, size: 18)
                : const Icon(
                    Icons.circle_outlined,
                    size: 18,
                    color: AppColors.textTertiaryDark,
                  )),
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

  Widget _buildMobileChannelList(AppLocalizations l10n) {
    final channelsAsync =
        _selectedCategoryId == _kFavoritesId ||
            _selectedCategoryId == _kHistoryId
        ? null // handled separately
        : _selectedCategoryId == '__all__'
        ? ref.watch(_allLiveChannelsProvider)
        : ref.watch(_liveChannelsProvider(_selectedCategoryId!));

    // Handle favorites
    if (_selectedCategoryId == _kFavoritesId) {
      final favIdsAsync = ref.watch(_favLiveIdsProvider);
      return favIdsAsync.when(
        data: (ids) {
          if (ids.isEmpty)
            return Center(
              child: Text(
                l10n.noChannels,
                style: const TextStyle(color: AppColors.textTertiaryDark),
              ),
            );
          final chAsync = ref.watch(_favLiveChannelsProvider(ids));
          return chAsync.when(
            data: (channels) => _buildMobileChannelListView(channels, l10n),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      );
    }

    // Handle history
    if (_selectedCategoryId == _kHistoryId) {
      final historyAsync = ref.watch(_continueWatchingLiveProvider);
      return historyAsync.when(
        data: (channels) {
          if (channels.isEmpty)
            return Center(
              child: Text(
                l10n.noHistory,
                style: const TextStyle(color: AppColors.textTertiaryDark),
              ),
            );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _clearLiveHistory(l10n),
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
              Expanded(child: _buildMobileChannelListView(channels, l10n)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      );
    }

    return channelsAsync!.when(
      data: (channels) {
        if (channels.isEmpty) {
          return Center(
            child: Text(
              l10n.noChannels,
              style: const TextStyle(color: AppColors.textTertiaryDark),
            ),
          );
        }
        return _buildMobileChannelListView(channels, l10n);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }

  Widget _buildMobileChannelListView(
    List<Channel> channels,
    AppLocalizations l10n,
  ) {
    return ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 68, color: AppColors.borderDark),
      itemBuilder: (context, index) {
        final ch = channels[index];
        return _MobileChannelTile(
          channel: ch,
          onTap: () => _playChannel(ch, channelList: channels),
        );
      },
    );
  }

  void _clearLiveHistory(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        title: Text(
          l10n.clearHistory,
          style: const TextStyle(color: AppColors.textDark),
        ),
        content: Text(
          l10n.clearHistoryConfirm,
          style: const TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(playerRepositoryProvider).clearAllProgress('live');
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

  void _playChannel(Channel channel, {List<Channel>? channelList}) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;

    final quality = ref.read(settingsProvider).streamQuality;
    final user = account.username ?? '';
    final pass = account.password ?? '';
    final isM3u = account.type == 'm3u';

    final url =
        (isM3u && channel.streamUrl != null && channel.streamUrl!.isNotEmpty)
        ? channel.streamUrl!
        : StreamUrlBuilder.live(
            account.url,
            user,
            pass,
            channel.streamId,
            quality: quality,
          );

    // Build channel list for live TV channel switching (D-pad up/down)
    final channels = channelList ?? _getCurrentChannelList();
    List<PlayerChannel>? playerChannels;
    int? currentIndex;

    if (channels != null && channels.isNotEmpty) {
      playerChannels = channels
          .map(
            (ch) => PlayerChannel(
              streamId: ch.streamId,
              name: ch.name,
              url: (isM3u && ch.streamUrl != null && ch.streamUrl!.isNotEmpty)
                  ? ch.streamUrl!
                  : StreamUrlBuilder.live(
                      account.url,
                      user,
                      pass,
                      ch.streamId,
                      quality: quality,
                    ),
              logo: ch.streamIcon,
              categoryId: ch.categoryId,
            ),
          )
          .toList();
      currentIndex = channels.indexWhere(
        (ch) => ch.streamId == channel.streamId,
      );
      if (currentIndex < 0) currentIndex = 0;
    }

    // Build category name map from loaded categories
    final categories = ref.read(_liveCategoriesProvider).value;
    final categoryMap = <String, String>{};
    if (categories != null) {
      for (final cat in categories) {
        categoryMap[cat.id] = cat.name;
      }
    }

    context.push(
      '/player',
      extra: {
        'url': url,
        'title': channel.name,
        'type': VideoType.live,
        'logo': channel.streamIcon,
        'channels': playerChannels,
        'currentChannelIndex': currentIndex,
        'categoryNames': categoryMap,
      },
    );
  }

  /// Get the currently displayed channel list (for channel switching in player)
  List<Channel>? _getCurrentChannelList() {
    if (_selectedCategoryId == _kFavoritesId) {
      final favIds = ref.read(_favLiveIdsProvider).value;
      if (favIds == null || favIds.isEmpty) return null;
      return ref.read(_favLiveChannelsProvider(favIds)).value;
    }
    if (_selectedCategoryId == _kHistoryId) {
      return ref.read(_continueWatchingLiveProvider).value;
    }
    if (_selectedCategoryId == '__all__') {
      return ref.read(_allLiveChannelsProvider).value;
    }
    if (_selectedCategoryId != null) {
      return ref.read(_liveChannelsProvider(_selectedCategoryId!)).value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.watch(_liveCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: isMobilePlatform
          ? _buildMobileLayout(l10n, categoriesAsync)
          : Row(
              children: [
                // -- Category sidebar
                _buildCategorySidebar(l10n, categoriesAsync),

                // -- Main content (channel list + EPG timeline)
                Expanded(
                  child: Column(
                    children: [
                      // Top bar
                      _buildTopBar(l10n),
                      // Channel list + EPG grid
                      Expanded(
                        child: _selectedCategoryId != null
                            ? _buildEpgLayout(l10n)
                            : Center(
                                child: Text(
                                  l10n.selectCategory,
                                  style: const TextStyle(
                                    color: AppColors.textTertiaryDark,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TOP BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTopBar(AppLocalizations l10n) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.backgroundDark,
        border: Border(
          bottom: BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
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
          Icon(Icons.live_tv, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            l10n.liveTV,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.programGuide,
            style: const TextStyle(
              color: AppColors.textTertiaryDark,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          // Current time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // EPG sync indicator
          ValueListenableBuilder<bool>(
            valueListenable: _epgSyncingNotifier,
            builder: (context, isSyncing, _) {
              if (!isSyncing) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'EPG',
                      style: TextStyle(
                        color: AppColors.textTertiaryDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Refresh EPG button
          _FocusableIconButton(
            icon: Icons.refresh,
            tooltip: 'EPG',
            onTap: () => _triggerEpgSync(),
          ),
          const SizedBox(width: 4),
          // Scroll to now button
          _FocusableIconButton(
            icon: Icons.my_location,
            tooltip: l10n.nowPlaying,
            onTap: () => _scrollToCurrentTime(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CATEGORY SIDEBAR
  // ═══════════════════════════════════════════════════════════════════════════

  /// Move focus to channel list (D-pad right from category sidebar)
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _channelListFocusNode.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          FocusManager.instance.primaryFocus?.focusInDirection(
            TraversalDirection.down,
          );
        });
      }
    });
  }

  /// Open category sidebar (called from channel list left D-pad)
  void _openCategorySidebar() {
    if (!_categoriesCollapsed) return;
    _toggleCategorySidebar();
  }

  /// Focus the main AppSidebar (called from category item left press)
  void _focusMainSidebar() {
    final sidebarState = context.findAncestorStateOfType<AppSidebarState>();
    sidebarState?.requestFocus();
  }

  Widget _buildCategorySidebar(
    AppLocalizations l10n,
    AsyncValue<List<Category>> categoriesAsync,
  ) {
    // Fully hidden when collapsed — content takes full width
    if (_categoriesCollapsed) {
      return const SizedBox.shrink();
    }

    return FocusScope(
      node: _categorySidebarScope,
      child: SizedBox(
        width: _kCategoryPanelWidth,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.sidebarBgDark,
            border: Border(
              right: BorderSide(color: AppColors.sidebarBorderDark),
            ),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.categories,
                        style: const TextStyle(
                          color: AppColors.textTertiaryDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    _FocusableIconButton(
                      icon: Icons.chevron_left,
                      onTap: _toggleCategorySidebar,
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ),
              // Favorite channels
              _CategoryItem(
                name: l10n.favoriteChannels,
                icon: Icons.favorite,
                isSelected: _selectedCategoryId == _kFavoritesId,
                collapsed: false,
                onTap: () => _selectCategory(_kFavoritesId),
                onRightPressed: _focusContent,
                onLeftPressed: _focusMainSidebar,
              ),
              // History
              _CategoryItem(
                name: l10n.watchHistory,
                icon: Icons.history,
                isSelected: _selectedCategoryId == _kHistoryId,
                collapsed: false,
                onTap: () => _selectCategory(_kHistoryId),
                onRightPressed: _focusContent,
                onLeftPressed: _focusMainSidebar,
              ),
              // All Channels
              _CategoryItem(
                name: l10n.allChannels,
                icon: Icons.grid_view_rounded,
                isSelected: _selectedCategoryId == '__all__',
                collapsed: false,
                onTap: () => _selectCategory('__all__'),
                onRightPressed: _focusContent,
                onLeftPressed: _focusMainSidebar,
              ),
              const SizedBox(height: 4),
              Divider(
                color: AppColors.sidebarBorderDark,
                height: 1,
                indent: 14,
                endIndent: 14,
              ),
              const SizedBox(height: 4),
              // Category list
              Expanded(
                child: categoriesAsync.when(
                  data: (categories) {
                    if (_selectedCategoryId == null && categories.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _selectedCategoryId == null) {
                          setState(
                            () => _selectedCategoryId = categories.first.id,
                          );
                        }
                      });
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isSelected = cat.id == _selectedCategoryId;

                        return _CategoryItem(
                          name: cat.name,
                          isSelected: isSelected,
                          collapsed: false,
                          onTap: () => _selectCategory(cat.id),
                          onRightPressed: _focusContent,
                          onLeftPressed: _focusMainSidebar,
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Text(
                      'Error',
                      style: TextStyle(
                        color: AppColors.textTertiaryDark,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  EPG LAYOUT (Channel List + Timeline Grid)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEpgLayout(AppLocalizations l10n) {
    // Handle favorites category
    if (_selectedCategoryId == _kFavoritesId) {
      return _buildFavoritesEpgLayout(l10n);
    }

    // Handle history category
    if (_selectedCategoryId == _kHistoryId) {
      return _buildHistoryEpgLayout(l10n);
    }

    final channelsAsync = _selectedCategoryId == '__all__'
        ? ref.watch(_allLiveChannelsProvider)
        : ref.watch(_liveChannelsProvider(_selectedCategoryId!));

    return channelsAsync.when(
      data: (channels) {
        if (channels.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tv_off_outlined,
                  size: 48,
                  color: AppColors.textDisabledDark,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noChannels,
                  style: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          children: [
            // -- Channel list (left side, fixed width)
            Focus(
              focusNode: _channelListFocusNode,
              child: SizedBox(
                width: _kChannelListWidth,
                child: Column(
                  children: [
                    // Header spacer (aligned with timeline header)
                    Container(
                      height: _kTimelineHeaderHeight,
                      decoration: const BoxDecoration(
                        color: AppColors.backgroundDark,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.borderDark,
                            width: 1,
                          ),
                          right: BorderSide(
                            color: AppColors.borderDark,
                            width: 1,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.allChannels,
                        style: const TextStyle(
                          color: AppColors.textTertiaryDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    // Channel rows
                    Expanded(
                      child: ListView.builder(
                        controller: _channelListScrollController,
                        itemCount: channels.length,
                        itemExtent: _kChannelRowHeight,
                        itemBuilder: (context, index) {
                          return _ChannelListItem(
                            channel: channels[index],
                            onTap: () => _playChannel(channels[index]),
                            onLeftPressed: _openCategorySidebar,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -- EPG Timeline grid (right side, horizontally scrollable)
            Expanded(
              child: _EpgTimelineGrid(
                channels: channels,
                timelineStart: _timelineStart,
                currentTime: _currentTime,
                verticalScrollController: _epgVerticalScrollController,
                horizontalScrollController: _epgHorizontalScrollController,
                onChannelTap: _playChannel,
                l10n: l10n,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.textTertiaryDark),
        ),
      ),
    );
  }

  Widget _buildFavoritesEpgLayout(AppLocalizations l10n) {
    final favIdsAsync = ref.watch(_favLiveIdsProvider);
    return favIdsAsync.when(
      data: (ids) {
        if (ids.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 48,
                  color: AppColors.textDisabledDark,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noFavorites,
                  style: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }
        final channelsAsync = ref.watch(_favLiveChannelsProvider(ids));
        return channelsAsync.when(
          data: (channels) {
            if (channels.isEmpty) {
              return Center(
                child: Text(
                  l10n.noFavorites,
                  style: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    fontSize: 14,
                  ),
                ),
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: _kChannelListWidth,
                  child: Column(
                    children: [
                      Container(
                        height: _kTimelineHeaderHeight,
                        decoration: const BoxDecoration(
                          color: AppColors.backgroundDark,
                          border: Border(
                            bottom: BorderSide(
                              color: AppColors.borderDark,
                              width: 1,
                            ),
                            right: BorderSide(
                              color: AppColors.borderDark,
                              width: 1,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.favoriteChannels,
                          style: const TextStyle(
                            color: AppColors.textTertiaryDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _channelListScrollController,
                          itemCount: channels.length,
                          itemExtent: _kChannelRowHeight,
                          itemBuilder: (context, index) => _ChannelListItem(
                            channel: channels[index],
                            onTap: () => _playChannel(channels[index]),
                            onLeftPressed: _openCategorySidebar,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _EpgTimelineGrid(
                    channels: channels,
                    timelineStart: _timelineStart,
                    currentTime: _currentTime,
                    verticalScrollController: _epgVerticalScrollController,
                    horizontalScrollController: _epgHorizontalScrollController,
                    onChannelTap: _playChannel,
                    l10n: l10n,
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => Center(
            child: Text(
              'Error: $err',
              style: const TextStyle(color: AppColors.textTertiaryDark),
            ),
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.textTertiaryDark),
        ),
      ),
    );
  }

  Widget _buildHistoryEpgLayout(AppLocalizations l10n) {
    final historyAsync = ref.watch(_continueWatchingLiveProvider);
    return historyAsync.when(
      data: (channels) {
        if (channels.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 48,
                  color: AppColors.textDisabledDark,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noHistory,
                  style: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }
        return Row(
          children: [
            SizedBox(
              width: _kChannelListWidth,
              child: Column(
                children: [
                  Container(
                    height: _kTimelineHeaderHeight,
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundDark,
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.borderDark,
                          width: 1,
                        ),
                        right: BorderSide(
                          color: AppColors.borderDark,
                          width: 1,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.watchHistory,
                            style: const TextStyle(
                              color: AppColors.textTertiaryDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _clearLiveHistory(l10n),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_sweep,
                                  size: 12,
                                  color: Colors.red.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.clearHistory,
                                  style: TextStyle(
                                    color: Colors.red.withValues(alpha: 0.7),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _channelListScrollController,
                      itemCount: channels.length,
                      itemExtent: _kChannelRowHeight,
                      itemBuilder: (context, index) => _ChannelListItem(
                        channel: channels[index],
                        onTap: () => _playChannel(channels[index]),
                        onLeftPressed: _openCategorySidebar,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _EpgTimelineGrid(
                channels: channels,
                timelineStart: _timelineStart,
                currentTime: _currentTime,
                verticalScrollController: _epgVerticalScrollController,
                horizontalScrollController: _epgHorizontalScrollController,
                onChannelTap: _playChannel,
                l10n: l10n,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: const TextStyle(color: AppColors.textTertiaryDark),
        ),
      ),
    );
  }
}

// ===========================================================================
//  FOCUSABLE ICON BUTTON (for category sidebar toggle)
// ===========================================================================

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final EdgeInsets padding;
  const _FocusableIconButton({
    required this.icon,
    this.tooltip,
    required this.onTap,
    this.padding = const EdgeInsets.all(8),
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
    final btn = Focus(
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
            padding: widget.padding,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(10),
              border: _isFocused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: isActive ? AppColors.primary : AppColors.textSecondaryDark,
              size: 22,
            ),
          ),
        ),
      ),
    );
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: btn)
        : btn;
  }
}

// ===========================================================================
//  CATEGORY ITEM
// ===========================================================================

class _CategoryItem extends StatefulWidget {
  final String name;
  final IconData? icon;
  final bool isSelected;
  final bool collapsed;
  final VoidCallback onTap;
  final VoidCallback? onRightPressed;
  final VoidCallback? onLeftPressed;

  const _CategoryItem({
    required this.name,
    this.icon,
    required this.isSelected,
    required this.collapsed,
    required this.onTap,
    this.onRightPressed,
    this.onLeftPressed,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isFocused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Focus(
        onFocusChange: (f) => setState(() => _isFocused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            // D-pad Right → collapse sidebar and go to channel list
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
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              vertical: 8,
              horizontal: widget.collapsed ? 6 : 10,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : (_isFocused
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isFocused ? AppColors.primary : Colors.transparent,
                width: _isFocused ? 1.5 : 0,
              ),
            ),
            child: widget.collapsed
                ? Center(
                    child: Text(
                      widget.name.isNotEmpty
                          ? widget.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.textSecondaryDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      if (widget.icon != null) ...[
                        Icon(
                          widget.icon,
                          size: 16,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textTertiaryDark,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.isSelected)
                        Container(
                          width: 3,
                          height: 16,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          widget.name,
                          style: TextStyle(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textSecondaryDark,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

// ===========================================================================
//  CHANNEL LIST ITEM (left side of EPG)
// ===========================================================================

class _ChannelListItem extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  final VoidCallback? onLeftPressed;

  const _ChannelListItem({
    required this.channel,
    required this.onTap,
    this.onLeftPressed,
  });

  @override
  ConsumerState<_ChannelListItem> createState() => _ChannelListItemState();
}

class _ChannelListItemState extends ConsumerState<_ChannelListItem> {
  bool _isFocused = false;

  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context)!;
    final added = await ref
        .read(favoritesRepositoryProvider)
        .toggleFavorite(
          widget.channel.streamId,
          'live',
          widget.channel.name,
          widget.channel.streamIcon,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? l10n.addedToFavorites : l10n.removedFromFavorites,
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final programsAsync = ref.watch(
      _channelProgramsProvider(widget.channel.streamId),
    );
    final isFavoriteAsync = ref.watch(
      _isLiveFavoriteProvider(widget.channel.streamId),
    );
    final now = DateTime.now();
    final isFavorite = isFavoriteAsync.when(
      data: (v) => v,
      loading: () => false,
      error: (_, __) => false,
    );

    String? currentProgramTitle;
    programsAsync.whenData((programs) {
      for (final p in programs) {
        if (p.start.isBefore(now) && p.stop.isAfter(now)) {
          currentProgramTitle = p.title;
          break;
        }
      }
    });

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.onLeftPressed != null) {
            widget.onLeftPressed!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _kChannelRowHeight,
          transform: Matrix4.identity()..scale(_isFocused ? 1.02 : 1.0),
          transformAlignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _isFocused
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.backgroundDark,
            border: Border(
              bottom: const BorderSide(color: AppColors.borderDark, width: 0.5),
              right: const BorderSide(color: AppColors.borderDark, width: 1),
              left: BorderSide(
                color: _isFocused ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // Channel logo
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: widget.channel.streamIcon != null
                      ? Image.network(
                          widget.channel.streamIcon!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _channelPlaceholder(),
                        )
                      : _channelPlaceholder(),
                ),
              ),
              const SizedBox(width: 8),
              // Channel name + current program
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.name,
                      style: TextStyle(
                        color: _isFocused
                            ? AppColors.textDark
                            : AppColors.textDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (currentProgramTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        currentProgramTitle!,
                        style: const TextStyle(
                          color: AppColors.textTertiaryDark,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                onTap: _toggleFavorite,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? AppColors.primary
                        : AppColors.textTertiaryDark,
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

  Widget _channelPlaceholder() {
    return Container(
      color: AppColors.surfaceElevatedDark,
      child: const Center(
        child: Icon(Icons.tv, color: AppColors.textDisabledDark, size: 18),
      ),
    );
  }
}

// ===========================================================================
//  EPG TIMELINE GRID
// ===========================================================================

class _EpgTimelineGrid extends StatelessWidget {
  final List<Channel> channels;
  final DateTime timelineStart;
  final DateTime currentTime;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final Function(Channel) onChannelTap;
  final AppLocalizations l10n;

  // Total timeline hours to render
  static const int _totalHours = 6;

  const _EpgTimelineGrid({
    required this.channels,
    required this.timelineStart,
    required this.currentTime,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.onChannelTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final totalWidth = _kHourWidth * _totalHours;

    return Column(
      children: [
        // Timeline header with hour marks
        _buildTimelineHeader(totalWidth),
        // EPG grid rows
        Expanded(
          child: SingleChildScrollView(
            controller: horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Stack(
                children: [
                  // Program rows
                  ListView.builder(
                    controller: verticalScrollController,
                    itemCount: channels.length,
                    itemExtent: _kChannelRowHeight,
                    itemBuilder: (context, index) {
                      return _EpgChannelRow(
                        channel: channels[index],
                        timelineStart: timelineStart,
                        currentTime: currentTime,
                        totalWidth: totalWidth,
                        totalHours: _totalHours,
                        onTap: () => onChannelTap(channels[index]),
                        l10n: l10n,
                      );
                    },
                  ),
                  // Current time indicator (red vertical line)
                  _buildCurrentTimeLine(totalWidth),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineHeader(double totalWidth) {
    return Container(
      height: _kTimelineHeaderHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(
          bottom: BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        controller:
            null, // Shares scroll with the grid below via NotificationListener
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: totalWidth,
          child: CustomPaint(
            painter: _TimelineHeaderPainter(
              timelineStart: timelineStart,
              totalHours: _totalHours,
              hourWidth: _kHourWidth,
              currentTime: currentTime,
            ),
            size: Size(totalWidth, _kTimelineHeaderHeight),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTimeLine(double totalWidth) {
    final minutesSinceStart = currentTime
        .difference(timelineStart)
        .inMinutes
        .toDouble();
    final xPos = minutesSinceStart * (_kHourWidth / 60.0);

    if (xPos < 0 || xPos > totalWidth) return const SizedBox.shrink();

    return Positioned(
      left: xPos - _kCurrentTimeLineWidth / 2,
      top: 0,
      bottom: 0,
      child: Container(
        width: _kCurrentTimeLineWidth,
        decoration: BoxDecoration(
          color: AppColors.primary,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  TIMELINE HEADER PAINTER
// ===========================================================================

class _TimelineHeaderPainter extends CustomPainter {
  final DateTime timelineStart;
  final int totalHours;
  final double hourWidth;
  final DateTime currentTime;

  _TimelineHeaderPainter({
    required this.timelineStart,
    required this.totalHours,
    required this.hourWidth,
    required this.currentTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.borderDark
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: AppColors.textSecondaryDark,
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    final halfHourTextStyle = TextStyle(
      color: AppColors.textDisabledDark,
      fontSize: 9,
    );

    for (int i = 0; i <= totalHours; i++) {
      final x = i * hourWidth;
      final time = timelineStart.add(Duration(hours: i));
      final label = '${time.hour.toString().padLeft(2, '0')}:00';

      // Draw hour line
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x, size.height),
        linePaint,
      );

      // Draw hour text
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(x + 6, (size.height - textPainter.height) / 2),
      );

      // Draw 30-minute mark
      if (i < totalHours) {
        final halfX = x + hourWidth / 2;
        canvas.drawLine(
          Offset(halfX, size.height - 5),
          Offset(halfX, size.height),
          linePaint..color = AppColors.borderDark.withValues(alpha: 0.5),
        );

        final halfLabel = '${time.hour.toString().padLeft(2, '0')}:30';
        final halfPainter = TextPainter(
          text: TextSpan(text: halfLabel, style: halfHourTextStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        halfPainter.paint(
          canvas,
          Offset(halfX + 4, (size.height - halfPainter.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineHeaderPainter oldDelegate) {
    return oldDelegate.currentTime != currentTime;
  }
}

// ===========================================================================
//  EPG CHANNEL ROW (one row of program blocks)
// ===========================================================================

class _EpgChannelRow extends ConsumerStatefulWidget {
  final Channel channel;
  final DateTime timelineStart;
  final DateTime currentTime;
  final double totalWidth;
  final int totalHours;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _EpgChannelRow({
    required this.channel,
    required this.timelineStart,
    required this.currentTime,
    required this.totalWidth,
    required this.totalHours,
    required this.onTap,
    required this.l10n,
  });

  @override
  ConsumerState<_EpgChannelRow> createState() => _EpgChannelRowState();
}

class _EpgChannelRowState extends ConsumerState<_EpgChannelRow> {
  bool _epgFetchAttempted = false;

  /// Lazy-fetch EPG for this channel if not yet synced
  void _lazyFetchEpg(List<Program> programs) async {
    if (_epgFetchAttempted) return;
    if (programs.isNotEmpty) return; // Already have data
    if (_epgSyncedChannels.contains(widget.channel.streamId)) {
      _epgFetchAttempted = true;
      return;
    }

    final account =
        ref.read(currentAccountProvider).value ??
        await ref.read(currentAccountProvider.future);
    if (!mounted) return;
    if (account == null) return;

    // Check if this channel was already synced in this session
    if (_epgSyncedChannels.contains(widget.channel.streamId)) return;

    _epgFetchAttempted = true;

    // Mark as synced
    _epgSyncedChannels.add(widget.channel.streamId);

    // Fetch EPG in background
    unawaited(
      ref
          .read(contentRepositoryProvider)
          .syncChannelEpg(account.id, widget.channel.streamId.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final programsAsync = ref.watch(
      _channelProgramsProvider(widget.channel.streamId),
    );
    final timelineEnd = widget.timelineStart.add(
      Duration(hours: widget.totalHours),
    );

    return Container(
      height: _kChannelRowHeight,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderDark, width: 0.5),
        ),
      ),
      child: programsAsync.when(
        data: (programs) {
          // Lazy-fetch EPG if empty
          _lazyFetchEpg(programs);

          // Filter programs that overlap with our timeline window
          final visible = programs.where((p) {
            return p.start.isBefore(timelineEnd) &&
                p.stop.isAfter(widget.timelineStart);
          }).toList();

          if (visible.isEmpty) {
            // No program data - show a placeholder bar
            return GestureDetector(
              onTap: widget.onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.l10n.noProgramGuide,
                  style: const TextStyle(
                    color: AppColors.textDisabledDark,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: visible.map((program) {
              return _ProgramBlock(
                program: program,
                timelineStart: widget.timelineStart,
                currentTime: widget.currentTime,
                totalWidth: widget.totalWidth,
                totalHours: widget.totalHours,
                onTap: widget.onTap,
              );
            }).toList(),
          );
        },
        loading: () => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
          child: const Center(
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                color: AppColors.textDisabledDark,
                strokeWidth: 1.5,
              ),
            ),
          ),
        ),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}

// ===========================================================================
//  PROGRAM BLOCK (individual program in the timeline)
// ===========================================================================

class _ProgramBlock extends StatefulWidget {
  final Program program;
  final DateTime timelineStart;
  final DateTime currentTime;
  final double totalWidth;
  final int totalHours;
  final VoidCallback onTap;

  const _ProgramBlock({
    required this.program,
    required this.timelineStart,
    required this.currentTime,
    required this.totalWidth,
    required this.totalHours,
    required this.onTap,
  });

  @override
  State<_ProgramBlock> createState() => _ProgramBlockState();
}

class _ProgramBlockState extends State<_ProgramBlock> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final pixelsPerMinute = _kHourWidth / 60.0;
    final timelineEnd = widget.timelineStart.add(
      Duration(hours: widget.totalHours),
    );

    // Clamp program start/stop to timeline bounds
    final clampedStart = widget.program.start.isBefore(widget.timelineStart)
        ? widget.timelineStart
        : widget.program.start;
    final clampedStop = widget.program.stop.isAfter(timelineEnd)
        ? timelineEnd
        : widget.program.stop;

    final left =
        clampedStart.difference(widget.timelineStart).inMinutes *
        pixelsPerMinute;
    final width =
        clampedStop.difference(clampedStart).inMinutes * pixelsPerMinute;

    if (width < 2) return const SizedBox.shrink();

    final isCurrent =
        widget.program.start.isBefore(widget.currentTime) &&
        widget.program.stop.isAfter(widget.currentTime);
    final isPast = widget.program.stop.isBefore(widget.currentTime);

    // Calculate progress for current program
    double progress = 0.0;
    if (isCurrent) {
      final total = widget.program.stop
          .difference(widget.program.start)
          .inMinutes;
      final elapsed = widget.currentTime
          .difference(widget.program.start)
          .inMinutes;
      if (total > 0) progress = (elapsed / total).clamp(0.0, 1.0);
    }

    Color bgColor;
    Color textColor;
    Color timeColor;
    List<BoxShadow>? shadows;

    if (isCurrent) {
      bgColor = AppColors.primary.withValues(alpha: 0.18);
      textColor = AppColors.textDark;
      timeColor = AppColors.primary;
      shadows = [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.15),
          blurRadius: 8,
          spreadRadius: 0,
        ),
      ];
    } else if (isPast) {
      bgColor = AppColors.surfaceDark.withValues(alpha: 0.3);
      textColor = AppColors.textDisabledDark;
      timeColor = AppColors.textDisabledDark;
    } else {
      bgColor = AppColors.surfaceDark;
      textColor = AppColors.textSecondaryDark;
      timeColor = AppColors.textTertiaryDark;
    }

    if (_isFocused) {
      bgColor = AppColors.primary.withValues(alpha: 0.25);
      textColor = AppColors.textDark;
    }

    final startLabel =
        '${widget.program.start.hour.toString().padLeft(2, '0')}:${widget.program.start.minute.toString().padLeft(2, '0')}';
    final stopLabel =
        '${widget.program.stop.hour.toString().padLeft(2, '0')}:${widget.program.stop.minute.toString().padLeft(2, '0')}';

    return Positioned(
      left: left,
      top: 2,
      bottom: 2,
      width: width - 2, // 2px gap between blocks
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
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isFocused
                    ? AppColors.primary
                    : (isCurrent
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : Colors.transparent),
                width: _isFocused ? 1.5 : (isCurrent ? 1 : 0),
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ]
                  : shadows,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // Progress fill for current program
                if (isCurrent)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (width - 2) * progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.program.title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 10,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Time range
                      if (width > 60)
                        Text(
                          '$startLabel - $stopLabel',
                          style: TextStyle(
                            color: timeColor,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
                // LIVE badge for current program
                if (isCurrent && width > 80)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
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

// =============================================================================
//  Mobile Channel Tile — full-width row with logo, name, EPG info
// =============================================================================

class _MobileChannelTile extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _MobileChannelTile({required this.channel, required this.onTap});

  @override
  ConsumerState<_MobileChannelTile> createState() => _MobileChannelTileState();
}

class _MobileChannelTileState extends ConsumerState<_MobileChannelTile> {
  bool _epgFetchAttempted = false;

  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context)!;
    final added = await ref
        .read(favoritesRepositoryProvider)
        .toggleFavorite(
          widget.channel.streamId,
          'live',
          widget.channel.name,
          widget.channel.streamIcon,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? l10n.addedToFavorites : l10n.removedFromFavorites,
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Lazy-fetch EPG for this channel if not yet synced (same logic as _EpgChannelRow)
  void _lazyFetchEpg(List<Program> programs) async {
    if (_epgFetchAttempted) return;
    if (programs.isNotEmpty) return; // Already have data
    if (_epgSyncedChannels.contains(widget.channel.streamId)) {
      _epgFetchAttempted = true;
      return;
    }

    final account =
        ref.read(currentAccountProvider).value ??
        await ref.read(currentAccountProvider.future);
    if (!mounted) return;
    if (account == null) return;

    // Check if this channel was already synced in this session
    if (_epgSyncedChannels.contains(widget.channel.streamId)) return;

    _epgFetchAttempted = true;

    // Mark as synced
    _epgSyncedChannels.add(widget.channel.streamId);

    // Fetch EPG in background
    unawaited(
      ref
          .read(contentRepositoryProvider)
          .syncChannelEpg(account.id, widget.channel.streamId.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final programsAsync = ref.watch(
      _channelProgramsProvider(widget.channel.streamId),
    );
    final isFavoriteAsync = ref.watch(
      _isLiveFavoriteProvider(widget.channel.streamId),
    );
    final isFavorite = isFavoriteAsync.when(
      data: (v) => v,
      loading: () => false,
      error: (_, __) => false,
    );
    final now = DateTime.now();

    // Find current program
    String? currentProgram;
    programsAsync.whenData((programs) {
      // Trigger lazy EPG fetch if no programs cached
      _lazyFetchEpg(programs);

      for (final p in programs) {
        if (p.start.isBefore(now) && p.stop.isAfter(now)) {
          currentProgram = p.title;
          break;
        }
      }
    });

    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Channel logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: widget.channel.streamIcon != null
                    ? Image.network(
                        widget.channel.streamIcon!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surfaceElevatedDark,
                          child: const Icon(
                            Icons.tv,
                            color: AppColors.textTertiaryDark,
                            size: 22,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.surfaceElevatedDark,
                        child: const Icon(
                          Icons.tv,
                          color: AppColors.textTertiaryDark,
                          size: 22,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Channel info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.channel.name,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (currentProgram != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      currentProgram!,
                      style: const TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? AppColors.primary
                        : AppColors.textTertiaryDark,
                    size: 22,
                  ),
                ),
                const Icon(
                  Icons.play_circle_outline,
                  color: AppColors.primary,
                  size: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
