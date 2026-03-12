import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'content_repository.g.dart';

class ContentRepository {
  final AppDatabase _db;
  final SyncService _syncService;

  /// Minimum interval between full EPG syncs (server-friendly)
  static const _epgSyncInterval = Duration(hours: 2);
  static const _epgSyncKey = 'last_epg_sync_timestamp';

  ContentRepository(this._db, this._syncService);

  Stream<List<Category>> watchCategories(String type) {
    return (_db.select(_db.categories)
      ..where((tbl) => tbl.type.equals(type))
      ..where((tbl) => tbl.isHidden.equals(false))
    ).watch();
  }

  /// All categories including hidden ones (for editing)
  Stream<List<Category>> watchAllCategories(String type) {
    return (_db.select(_db.categories)..where((tbl) => tbl.type.equals(type))).watch();
  }

  /// Toggle category visibility
  Future<void> toggleCategoryHidden(String categoryId, String type, bool hidden) async {
    await (_db.update(_db.categories)
      ..where((tbl) => tbl.id.equals(categoryId) & tbl.type.equals(type))
    ).write(CategoriesCompanion(isHidden: Value(hidden)));
  }

  Stream<List<Channel>> watchChannels(String categoryId, {String? type}) {
    final query = _db.select(_db.channels)
      ..where((tbl) => tbl.categoryId.equals(categoryId));
    if (type != null) {
      query.where((tbl) => tbl.type.equals(type));
    }
    return query.watch();
  }

  /// All channels of a given type (no limit — for "Tüm" grid + search)
  /// Filters out channels from hidden categories.
  Stream<List<Channel>> watchAllChannelsByType(String type) {
    final query = _db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
      ..orderBy([OrderingTerm(expression: _db.channels.added, mode: OrderingMode.desc)]);
    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Recent channels filtered by hidden categories.
  Stream<List<Channel>> watchRecentChannels(String type, {int limit = 20}) {
    final query = _db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
      ..orderBy([OrderingTerm(expression: _db.channels.added, mode: OrderingMode.desc)])
      ..limit(limit);
    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Search channels by name across all types.
  /// Uses Dart-side filtering for proper Turkish/Unicode case-insensitive search
  /// (SQLite LIKE is only case-insensitive for ASCII characters).
  /// Filters out channels from hidden categories.
  Future<List<Channel>> searchChannels(String query, {int limit = 50}) async {
    final lowerQuery = query.toLowerCase();
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])..where(_db.categories.isHidden.equals(false))).get();
    return rows
        .map((row) => row.readTable(_db.channels))
        .where((ch) => ch.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
  }

  /// Search channels by name filtered by type (movie/series/live).
  /// Filters out channels from hidden categories.
  Future<List<Channel>> searchChannelsByType(String query, String type, {int limit = 100}) async {
    final lowerQuery = query.toLowerCase();
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
    ).get();
    return rows
        .map((row) => row.readTable(_db.channels))
        .where((ch) => ch.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
  }

  /// Full sync: categories + all streams
  Future<void> refreshContent(int accountId) async {
    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncAll(account);
    }
  }

  Stream<List<Program>> watchPrograms(int channelId) {
    final now = DateTime.now();
    return (_db.select(_db.programs)
      ..where((tbl) => tbl.channelId.equals(channelId))
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.start)])
    ).watch();
  }

  /// Check if enough time has passed since last EPG sync
  Future<bool> _shouldSyncEpg() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_epgSyncKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastSync;
      return elapsed > _epgSyncInterval.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  /// Mark that an EPG sync just completed
  Future<void> _markEpgSynced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_epgSyncKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Check if DB has any EPG programs for live channels
  Future<bool> hasEpgData() async {
    final now = DateTime.now();
    final count = await (_db.select(_db.programs)
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..limit(1)
    ).get();
    return count.isNotEmpty;
  }

  /// Sync single channel EPG - only if no data exists in DB.
  /// Uses Xtream API first, then XMLTV fallback.
  Future<void> syncChannelEpg(int accountId, String streamId) async {
    // Check if we already have future programs for this channel
    final channelId = int.tryParse(streamId) ?? 0;
    final now = DateTime.now();
    final existing = await (_db.select(_db.programs)
      ..where((tbl) => tbl.channelId.equals(channelId))
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..limit(1)
    ).get();
    if (existing.isNotEmpty) return; // Already have data, skip API call

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account == null) return;

    if (account.type == 'xtream') {
      await _syncService.syncEpg(account, streamId);

      // Check if Xtream EPG returned data
      final afterXtream = await (_db.select(_db.programs)
        ..where((tbl) => tbl.channelId.equals(channelId))
        ..where((tbl) => tbl.stop.isBiggerThanValue(now))
        ..limit(1)
      ).get();
      if (afterXtream.isNotEmpty) return; // Xtream worked
    }

    // XMLTV fallback
    await _syncService.syncChannelEpgFromXmltv(accountId, channelId);
  }

  /// Sync EPG for all live channels - throttled (max once per 2 hours)
  /// If DB already has data, shows that immediately and syncs silently in background.
  Future<void> syncAllLiveEpg(int accountId) async {
    // Check if we should sync at all
    final shouldSync = await _shouldSyncEpg();
    if (!shouldSync) return; // Recently synced, use DB cache

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncAllLiveEpg(account);
      await _markEpgSynced();
    }
  }

  /// Sync EPG for specific channel IDs (batch) - throttled
  Future<void> syncEpgBatch(int accountId, List<int> streamIds) async {
    final shouldSync = await _shouldSyncEpg();
    if (!shouldSync) return;

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncEpgBatch(account, streamIds);
      await _markEpgSynced();
    }
  }

  /// Delete expired program data (cleanup)
  Future<void> cleanupOldPrograms() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    await (_db.delete(_db.programs)
      ..where((tbl) => tbl.stop.isSmallerThanValue(cutoff))
    ).go();
  }

  /// Update channel metadata (backdrop, trailer, genre, plot, etc.) from detail API
  Future<void> updateChannelMetadata(
    int streamId,
    String type, {
    String? backdropPath,
    String? youtubeTrailer,
    String? genre,
    String? plot,
    String? director,
    String? castInfo,
  }) async {
    if (backdropPath == null && youtubeTrailer == null &&
        genre == null && plot == null && director == null && castInfo == null) return;
    await (_db.update(_db.channels)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).write(ChannelsCompanion(
      backdropPath: backdropPath != null ? Value(backdropPath) : const Value.absent(),
      youtubeTrailer: youtubeTrailer != null ? Value(youtubeTrailer) : const Value.absent(),
      genre: genre != null ? Value(genre) : const Value.absent(),
      plot: plot != null ? Value(plot) : const Value.absent(),
      director: director != null ? Value(director) : const Value.absent(),
      cast: castInfo != null ? Value(castInfo) : const Value.absent(),
    ));
  }

  /// Watch channels that have playback progress (continue watching)
  Stream<List<Channel>> watchContinueWatching(String type) {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
      ..orderBy([OrderingTerm(expression: _db.playbackProgress.updatedAt, mode: OrderingMode.desc)])
      ..limit(50);

    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Watch all continue watching items (movies + series combined, sorted by updatedAt)
  Stream<List<Channel>> watchAllContinueWatching() {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.isIn(['movie', 'series']))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
      ..orderBy([OrderingTerm(expression: _db.playbackProgress.updatedAt, mode: OrderingMode.desc)])
      ..limit(20);

    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Watch playback progress for a specific channel
  Stream<PlaybackProgressData?> watchPlaybackProgress(int streamId, String type) {
    return (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).watchSingleOrNull();
  }

  /// Get playback progress for a specific channel (one-shot)
  Future<PlaybackProgressData?> getPlaybackProgress(int streamId, String type) {
    return (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).getSingleOrNull();
  }

  /// Watch channels with their playback progress (for history display)
  Stream<List<Channel>> watchFavoriteChannels(String type, List<int> streamIds) {
    if (streamIds.isEmpty) return Stream.value([]);
    return (_db.select(_db.channels)
      ..where((tbl) => tbl.streamId.isIn(streamIds) & tbl.type.equals(type))
    ).watch();
  }

  /// Check if a series has new episodes
  Stream<SeriesTrackingData?> watchSeriesTracking(int seriesId) {
    return (_db.select(_db.seriesTracking)
      ..where((tbl) => tbl.seriesId.equals(seriesId))
    ).watchSingleOrNull();
  }

  /// Get all series with new episodes (for badges/notifications)
  Stream<List<SeriesTrackingData>> watchSeriesWithNewEpisodes() {
    return (_db.select(_db.seriesTracking)
      ..where((tbl) => tbl.hasNewEpisodes.equals(true))
    ).watch();
  }

  /// Mark new episodes as seen (user opened the series)
  Future<void> markNewEpisodesSeen(int seriesId) async {
    await (_db.update(_db.seriesTracking)
      ..where((tbl) => tbl.seriesId.equals(seriesId))
    ).write(const SeriesTrackingCompanion(
      hasNewEpisodes: Value(false),
      newEpisodeCount: Value(0),
    ));
  }
}

@riverpod
ContentRepository contentRepository(Ref ref) {
  return ContentRepository(ref.watch(appDatabaseProvider), ref.watch(syncServiceProvider));
}
