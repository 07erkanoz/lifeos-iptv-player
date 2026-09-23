import 'dart:async';
import 'sync_budget.dart';
import 'm3u_identity.dart';
import 'sync_coordinator.dart';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/xmltv_parser.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'sync_service.g.dart';

/// Progress data for sync operations
class SyncProgress {
  final String step; // Current step description
  final int liveCount; // Number of live channels synced
  final int movieCount; // Number of movies synced
  final int seriesCount; // Number of series synced
  final int categoryCount; // Number of categories synced
  final bool isDone;

  const SyncProgress({
    this.step = '',
    this.liveCount = 0,
    this.movieCount = 0,
    this.seriesCount = 0,
    this.categoryCount = 0,
    this.isDone = false,
  });
}

class SyncService {
  final AppDatabase _db;
  final XtreamApiService _api;
  final Future<M3URawResult> Function(String) _loadM3u;

  static final _coordinators = Expando<SyncCoordinator<SyncProgress>>();
  final SyncCoordinator<SyncProgress>? _providedCoordinator;
  SyncService(
    this._db,
    this._api, {
    SyncCoordinator<SyncProgress>? coordinator,
    Future<M3URawResult> Function(String)? loadM3u,
  }) : _providedCoordinator = coordinator,
       _loadM3u = loadM3u ?? parseM3UFromUrlRaw;
  SyncCoordinator<SyncProgress> get _coordinator =>
      _providedCoordinator ??
      (_coordinators[_db.root] ??= SyncCoordinator<SyncProgress>());
  SyncService _bound(int id) => SyncService(
    _db.forAccount(id),
    _api,
    coordinator: _coordinator,
    loadM3u: _loadM3u,
  );
  void cancelSync(int accountId) {
    _coordinator.cancel(accountId);
    for (final entry in _epgBudgets.entries.toList()) {
      if (identical(entry.key.$1.root, _db.root) && entry.key.$2 == accountId) {
        entry.value.cancel();
      }
    }
  }

  Future<void> _run(
    Account account,
    SyncKind kind,
    Future<void> Function(void Function(SyncProgress)) action, {
    void Function(SyncProgress)? onProgress,
  }) async {
    try {
      await _coordinator.run(
        accountId: account.id,
        scope: _db,
        kind: kind,
        onProgress: onProgress,
        action: (report) async {
          _db.checkAccountWrite();
          var latest = const SyncProgress();
          await action((progress) {
            latest = progress;
            if (!progress.isDone) report(progress);
          });
          _db.checkAccountWrite();
          report(
            SyncProgress(
              step: 'Done',
              isDone: true,
              liveCount: latest.liveCount,
              movieCount: latest.movieCount,
              seriesCount: latest.seriesCount,
              categoryCount: latest.categoryCount,
            ),
          );
        },
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const SyncFailure(
        'Senkronizasyon tamamlanamadı. Bağlantıyı kontrol edip yeniden deneyin.',
      );
    }
  }

  Future<void> syncAll(Account account) => syncAllWithProgress(account, (_) {});

  Future<void> syncAllWithProgress(
    Account account,
    void Function(SyncProgress) onProgress,
  ) {
    if (_db.accountScope != account.id) {
      return _bound(account.id).syncAllWithProgress(account, onProgress);
    }
    return _run(account, SyncKind.full, (report) async {
      if (account.type == 'xtream' && account.username != null) {
        ApiCache.instance.invalidateForAccount(
          '${account.username}@${account.url.replaceAll(RegExp(r'/+$'), '')}',
        );
      }
      await _syncAllWithProgress(account, report);
      final meta = SyncMetadata(
        await SharedPreferences.getInstance(),
        accountId: account.id,
      );
      _db.checkAccountWrite();
      await meta.markTierSynced(3);
      if (account.type == 'xtream') {
        _db.checkAccountWrite();
        await meta.markTierSynced(1);
        _db.checkAccountWrite();
        await meta.markTierSynced(2);
        await meta.incrementApiCalls(6);
      }
    }, onProgress: onProgress);
  }

  /// Sync all data with progress callback
  Future<void> _syncAllWithProgress(
    Account account,
    void Function(SyncProgress) onProgress,
  ) async {
    if (account.type == 'm3u') {
      await _syncM3UWithProgress(account, onProgress);
      return;
    }
    if (account.type != 'xtream') {
      throw const SyncFailure('Desteklenmeyen hesap türü.');
    }

    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    final username = account.username!;
    final password = account.password!;

    int liveCount = 0;
    int movieCount = 0;
    int seriesCount = 0;
    int catCount = 0;

    // Step 1: Categories
    onProgress(SyncProgress(step: 'Loading categories...'));
    catCount = await _syncCategoriesCount(url, username, password);
    onProgress(
      SyncProgress(step: 'Categories loaded', categoryCount: catCount),
    );

    // Step 2: Live channels
    onProgress(
      SyncProgress(step: 'Loading live channels...', categoryCount: catCount),
    );
    liveCount = await _syncStreamsCount(
      url,
      username,
      password,
      'get_live_streams',
      'live',
    );
    onProgress(
      SyncProgress(
        step: 'Live channels loaded',
        categoryCount: catCount,
        liveCount: liveCount,
      ),
    );

    // Step 3: Movies
    onProgress(
      SyncProgress(
        step: 'Loading movies...',
        categoryCount: catCount,
        liveCount: liveCount,
      ),
    );
    movieCount = await _syncStreamsCount(
      url,
      username,
      password,
      'get_vod_streams',
      'movie',
    );
    onProgress(
      SyncProgress(
        step: 'Movies loaded',
        categoryCount: catCount,
        liveCount: liveCount,
        movieCount: movieCount,
      ),
    );

    // Step 4: Series
    onProgress(
      SyncProgress(
        step: 'Loading series...',
        categoryCount: catCount,
        liveCount: liveCount,
        movieCount: movieCount,
      ),
    );
    seriesCount = await _syncStreamsCount(
      url,
      username,
      password,
      'get_series',
      'series',
    );
    onProgress(
      SyncProgress(
        step: 'Done',
        categoryCount: catCount,
        liveCount: liveCount,
        movieCount: movieCount,
        seriesCount: seriesCount,
        isDone: true,
      ),
    );
  }

  /// Sync categories and return count
  Future<int> _syncCategoriesCount(
    String url,
    String username,
    String password,
  ) async {
    int total = 0;
    final liveCats = await _api.getCategories(
      url,
      username,
      password,
      'get_live_categories',
    );
    await _saveCategories(liveCats, 'live');
    total += liveCats.length;

    final vodCats = await _api.getCategories(
      url,
      username,
      password,
      'get_vod_categories',
    );
    await _saveCategories(vodCats, 'movie');
    total += vodCats.length;

    final seriesCats = await _api.getCategories(
      url,
      username,
      password,
      'get_series_categories',
    );
    await _saveCategories(seriesCats, 'series');
    total += seriesCats.length;
    return total;
  }

  /// Validate before touching a type, then atomically upsert and prune it.
  Future<int> _syncStreamsCount(
    String url,
    String username,
    String password,
    String action,
    String type, {
    bool deltaOnly = false,
  }) async {
    final streams = await _api.getStreams(url, username, password, action);
    _db.checkAccountWrite();
    // A valid empty list is distinct from malformed/failed HTTP. Preserve the
    // old catalogue on empty responses, as some panels temporarily return [].
    if (streams.isEmpty) {
      final previous =
          await (_db.select(_db.channels)
                ..where((t) => t.type.equals(type))
                ..limit(1))
              .getSingleOrNull();
      if (previous != null) {
        throw const SyncFailure(
          'Sunucu boş katalog döndürdü. Önceki kayıtlar korundu.',
        );
      }
      return 0;
    }
    final keepIds = <int>{};
    final rows = <ChannelsCompanion>[];
    for (final item in streams) {
      if (item is! Map) throw const FormatException('Invalid catalogue row');
      final sid = int.tryParse('${item['stream_id'] ?? item['series_id']}');
      if (sid == null || sid <= 0) {
        throw const FormatException('Invalid stream ID');
      }
      keepIds.add(sid);
      rows.add(
        ChannelsCompanion.insert(
          streamId: sid,
          searchText: const Value(null),
          name: item['name']?.toString() ?? 'Unknown',
          type: type,
          categoryId: item['category_id']?.toString() ?? '0',
          streamIcon: Value.absentIfNull(
            item['stream_icon']?.toString() ?? item['cover']?.toString(),
          ),
          rating: Value.absentIfNull(
            double.tryParse(item['rating']?.toString() ?? ''),
          ),
          year: Value.absentIfNull(item['year']?.toString()),
          added: Value.absentIfNull(item['added']?.toString()),
          epgChannelId: Value.absentIfNull(item['epg_channel_id']?.toString()),
          streamUrl: Value.absentIfNull(item['direct_source']?.toString()),
          containerExtension: Value.absentIfNull(
            item['container_extension']?.toString(),
          ),
        ),
      );
    }
    await _db.transaction(() async {
      final existing = deltaOnly
          ? (await (_db.select(
                  _db.channels,
                )..where((t) => t.type.equals(type))).get())
                .map((c) => c.streamId)
                .toSet()
          : <int>{};
      for (var i = 0; i < rows.length; i += 500) {
        await _db.accountBatch((batch) {
          for (final row in rows.skip(i).take(500)) {
            if (existing.contains(row.streamId.value)) continue;
            batch.insert(_db.channels, row, onConflict: DoUpdate((_) => row));
          }
        });
      }
      await _pruneRemovedChannels(type, keepIds);
      _db.checkAccountWrite();
    });
    return keepIds.length;
  }

  // Never bind the entire catalogue into one NOT IN query (SQLite variable
  // limits differ across platforms). Read IDs, then delete only stale chunks.
  Future<void> _pruneRemovedChannels(String type, Set<int> keepIds) async {
    final rows =
        await (_db.selectOnly(_db.channels)
              ..addColumns([_db.channels.streamId])
              ..where(_db.channels.type.equals(type)))
            .get();
    final stale = rows
        .map((r) => r.read(_db.channels.streamId)!)
        .where((id) => !keepIds.contains(id))
        .toList();
    for (var i = 0; i < stale.length; i += 500) {
      final chunk = stale.skip(i).take(500);
      await (_db.delete(
        _db.channels,
      )..where((t) => t.type.equals(type) & t.streamId.isIn(chunk))).go();
    }
  }

  Future<void> _pruneRemovedCategories(String type, Set<String> keepIds) async {
    final rows =
        await (_db.selectOnly(_db.categories)
              ..addColumns([_db.categories.id])
              ..where(_db.categories.type.equals(type)))
            .get();
    final stale = rows
        .map((r) => r.read(_db.categories.id)!)
        .where((id) => !keepIds.contains(id))
        .toList();
    for (var i = 0; i < stale.length; i += 500) {
      final chunk = stale.skip(i).take(500);
      await (_db.delete(
        _db.categories,
      )..where((t) => t.type.equals(type) & t.id.isIn(chunk))).go();
    }
  }

  Future<void> syncCategories(Account account) {
    if (_db.accountScope != account.id) {
      return _bound(account.id).syncCategories(account);
    }
    return _run(account, SyncKind.categories, (_) async {
      if (account.type != 'xtream') return;
      await _syncCategoriesCount(
        account.url.replaceAll(RegExp(r'/+$'), ''),
        account.username!,
        account.password!,
      );
    });
  }

  Future<void> _syncStreams(
    String url,
    String username,
    String password,
    String action,
    String type, {
    bool deltaOnly = false,
  }) async {
    await _syncStreamsCount(
      url,
      username,
      password,
      action,
      type,
      deltaOnly: deltaOnly,
    );
  }

  Future<void> _saveCategories(List<dynamic> data, String type) async {
    _db.checkAccountWrite();
    if (data.isEmpty) {
      final previous =
          await (_db.select(_db.categories)
                ..where((t) => t.type.equals(type))
                ..limit(1))
              .getSingleOrNull();
      if (previous != null) {
        throw const SyncFailure(
          'Sunucu boş kategori listesi döndürdü. Önceki kayıtlar korundu.',
        );
      }
      return;
    }
    final rows = <CategoriesCompanion>[];
    final keepIds = <String>{};
    for (final item in data) {
      if (item is! Map ||
          item['category_id'] == null ||
          '${item['category_id']}'.isEmpty) {
        throw const FormatException('Invalid category row');
      }
      final id = '${item['category_id']}';
      keepIds.add(id);
      rows.add(
        CategoriesCompanion.insert(
          id: id,
          name: item['category_name']?.toString() ?? 'Unknown',
          type: type,
        ),
      );
    }
    await _db.transaction(() async {
      await _db.accountBatch((batch) {
        for (final row in rows) {
          batch.insert(_db.categories, row, onConflict: DoUpdate((_) => row));
        }
      });
      await _pruneRemovedCategories(type, keepIds);
      _db.checkAccountWrite();
    });
  }

  // ─── M3U Sync ───────────────────────────────────────────────────────────

  /// Sync M3U playlist with progress callback
  Future<void> _syncM3UWithProgress(
    Account account,
    void Function(SyncProgress) onProgress,
  ) async {
    onProgress(const SyncProgress(step: 'Downloading M3U playlist...'));

    M3URawResult rawResult;
    try {
      rawResult = await _loadM3u(account.url);
    } catch (e) {
      throw Exception('M3U indirilemedi: $e');
    }

    _db.checkAccountWrite();
    final entries = rawResult.entries;
    if (entries.isEmpty) throw const FormatException('Empty M3U playlist');

    onProgress(SyncProgress(step: 'Parsing channels (${entries.length})...'));

    final prepared = await prepareM3uAsync(
      entries,
      await _db.select(_db.m3uIdentities).get(),
      await _db.select(_db.channels).get(),
      legacyReferences: {
        for (final row in await _db.select(_db.favorites).get())
          (row.streamType, row.streamId),
        for (final row in await _db.select(_db.playbackProgress).get())
          (row.type, row.streamId),
        for (final row in await _db.select(_db.watchlist).get())
          (row.streamType, row.streamId),
      },
    );
    _db.checkAccountWrite();
    final result = prepared.summary;

    // Save categories
    onProgress(
      SyncProgress(
        step: 'Saving categories...',
        categoryCount: result.categories.length,
      ),
    );

    // Track keepers per type so we can prune what disappeared from
    // the playlist. Without this, removing a channel from the source
    // M3U leaves the row in the local DB indefinitely.
    final keepCatsByType = <String, Set<String>>{};
    final keepChannelsByType = <String, Set<int>>{};

    await _db.transaction(() async {
      await _db.accountBatch((batch) {
        for (final cat in result.categories) {
          keepCatsByType.putIfAbsent(cat.type, () => <String>{}).add(cat.id);
          final row = CategoriesCompanion.insert(
            id: cat.id,
            name: cat.name,
            type: cat.type,
          );
          batch.insert(_db.categories, row, onConflict: DoUpdate((_) => row));
        }
      });
      for (var i = 0; i < prepared.channels.length; i += 500) {
        final chunk = prepared.channels.skip(i).take(500);
        await _db.accountBatch((batch) {
          for (final channel in chunk) {
            final entry = channel.entry, identity = channel.identity;
            final mapping = M3uIdentitiesCompanion.insert(
              streamId: identity.streamId,
              type: identity.type,
              sourceKey: identity.sourceKey,
              sourceUrl: identity.sourceUrl,
            );
            batch.insert(
              _db.m3uIdentities,
              mapping,
              onConflict: DoUpdate((_) => mapping),
            );
            keepChannelsByType
                .putIfAbsent(identity.type, () => <int>{})
                .add(identity.streamId);
            final row = ChannelsCompanion.insert(
              streamId: identity.streamId,
              searchText: const Value(null),
              name: channel.name,
              type: identity.type,
              categoryId: entry.groupTitle ?? 'Diğer',
              streamIcon: Value(entry.tvgLogo),
              streamUrl: Value(entry.url),
              epgChannelId: Value(entry.tvgId),
            );
            batch.insert(_db.channels, row, onConflict: DoUpdate((_) => row));
          }
        });
      }
      // A verified nonempty whole playlist is authoritative for all media types.
      for (final type in ['live', 'movie', 'series']) {
        await _pruneRemovedChannels(type, keepChannelsByType[type] ?? {});
        await _pruneRemovedCategories(type, keepCatsByType[type] ?? {});
      }

      _db.checkAccountWrite();
    });
    if (rawResult.epgUrl != null) {
      _db.checkAccountWrite();
      await _saveEpgUrl(account.id, rawResult.epgUrl!);
    }

    onProgress(
      SyncProgress(
        step: 'Done',
        categoryCount: result.categories.length,
        liveCount: result.liveCount,
        movieCount: result.movieCount,
        seriesCount: result.seriesCount,
        isDone: true,
      ),
    );
  }

  // ─── EPG Sync ─────────────────────────────────────────────────────────────

  /// Sync EPG for a single channel (short EPG)
  Future<void> syncEpg(Account account, String streamId) async {
    if (_db.accountScope != account.id) {
      return _bound(account.id).syncEpg(account, streamId);
    }
    try {
      final url = account.url.replaceAll(RegExp(r'/+$'), '');
      final epgData = await _api.getEpg(
        url,
        account.username!,
        account.password!,
        streamId,
        limit: 20,
      );
      final listings = epgData['epg_listings'] as List<dynamic>?;
      if (listings == null || listings.isEmpty) return;

      final channelId = int.tryParse(streamId) ?? 0;

      await _replaceEpg(channelId, _epgRows(channelId, listings));
    } catch (_) {}
  }

  /// Batch sync EPG for multiple channels at once
  Future<int> syncEpgBatch(Account account, List<int> streamIds) async {
    if (_db.accountScope != account.id) {
      return _bound(account.id).syncEpgBatch(account, streamIds);
    }
    if (account.type != 'xtream') return 0;

    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    final username = account.username!;
    final password = account.password!;

    // First try get_simple_data_table for all EPG at once
    try {
      final allEpg = await _api.getAllEpg(url, username, password);
      final listings = allEpg['epg_listings'] as List<dynamic>?;
      if (listings != null && listings.isNotEmpty) {
        final saved = await _saveBatchEpg(listings, streamIds.toSet());
        if (saved > 0) return saved;
      }
    } catch (_) {
      // Fall back to per-channel fetch
    }

    // Fallback: fetch EPG per channel (throttled, max 10 concurrent)
    var saved = 0;
    const batchSize = 10;
    for (var i = 0; i < streamIds.length; i += batchSize) {
      _db.checkAccountWrite();
      final batch = streamIds.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((id) => _syncSingleChannelEpg(url, username, password, id)),
      );
      saved += results.where((success) => success).length;
      // Small delay to avoid hammering the server
      if (i + batchSize < streamIds.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return saved;
  }

  /// Sync EPG for all live channels of an account.
  /// For Xtream: uses API first, then XMLTV fallback for channels without EPG.
  /// For M3U: uses XMLTV directly (from url-tvg header).
  static final _epgJobs = <(AppDatabase, int), Future<int>>{};
  static final _epgBudgets = <(AppDatabase, int), SyncBudget>{};

  Future<int> syncAllLiveEpg(Account account, {bool force = false}) {
    if (_db.accountScope != account.id) {
      return _bound(account.id).syncAllLiveEpg(account, force: force);
    }
    final key = (_db, account.id);
    final existing = _epgJobs[key];
    if (existing != null) return existing;
    final budget = SyncBudget(const Duration(minutes: 3));
    _epgBudgets[key] = budget;
    late final Future<int> job;
    job = budget
        .execute(() => _syncAllLiveEpgImpl(account, force: force))
        .whenComplete(() {
          if (identical(_epgJobs[key], job)) {
            _epgJobs.remove(key);
            _epgBudgets.remove(key);
          }
        });
    _epgJobs[key] = job;
    return job;
  }

  Future<int> _syncAllLiveEpgImpl(
    Account account, {
    required bool force,
  }) async {
    if (account.type == 'm3u') {
      // M3U accounts: use XMLTV directly
      return syncEpgFromXmltv(account.id, force: force);
    }

    if (account.type != 'xtream') return 0;

    // Get all live channel stream IDs from database
    final liveChannels = await (_db.select(
      _db.channels,
    )..where((tbl) => tbl.type.equals('live'))).get();

    if (liveChannels.isEmpty) return 0;

    final streamIds = liveChannels.map((c) => c.streamId).toList();
    var saved = await syncEpgBatch(account, streamIds);

    // XMLTV fallback: check how many channels still lack EPG. One
    // aggregate COUNT(DISTINCT channelId) instead of a per-channel SELECT
    // loop — the old loop fired thousands of sequential queries on the UI
    // isolate right after sync, a major first-launch slowdown on TV.
    final now = DateTime.now();
    final withEpgExpr = _db.programs.channelId.count(distinct: true);
    final withEpgRow =
        await (_db.selectOnly(_db.programs)
              ..addColumns([withEpgExpr])
              ..where(_db.programs.stop.isBiggerThanValue(now)))
            .getSingle();
    final channelsWithEpg = withEpgRow.read(withEpgExpr) ?? 0;
    final channelsWithoutEpg = (liveChannels.length - channelsWithEpg).clamp(
      0,
      liveChannels.length,
    );

    // If >50% channels lack EPG, try XMLTV fallback
    if (channelsWithoutEpg > liveChannels.length * 0.5) {
      saved += await syncEpgFromXmltv(account.id, force: force);
    }
    return saved;
  }

  Future<bool> _syncSingleChannelEpg(
    String url,
    String username,
    String password,
    int streamId,
  ) async {
    try {
      final epgData = await _api.getEpg(
        url,
        username,
        password,
        streamId.toString(),
        limit: 20,
      );
      final listings = epgData['epg_listings'] as List<dynamic>?;
      if (listings == null || listings.isEmpty) return false;

      final rows = _epgRows(streamId, listings);
      if (rows.isEmpty) return false;
      await _replaceEpg(streamId, rows);
      return true;
    } on SyncFailure {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<int> _saveBatchEpg(
    List<dynamic> listings,
    Set<int> targetStreamIds,
  ) async {
    // Group listings by channel_id
    final Map<int, List<dynamic>> grouped = {};
    for (final item in listings) {
      if (item is! Map<String, dynamic>) continue;
      final channelId = int.tryParse(item['channel_id']?.toString() ?? '');
      if (channelId == null) continue;
      // Only process channels we care about
      if (targetStreamIds.isNotEmpty && !targetStreamIds.contains(channelId)) {
        continue;
      }
      grouped.putIfAbsent(channelId, () => []).add(item);
    }

    var saved = 0;
    for (final entry in grouped.entries) {
      final rows = _epgRows(entry.key, entry.value);
      if (rows.isEmpty) continue;
      await _replaceEpg(entry.key, rows);
      saved++;
    }
    return saved;
  }

  List<ProgramsCompanion> _epgRows(int channelId, List<dynamic> listings) {
    final rows = <ProgramsCompanion>[];
    for (final item in listings) {
      if (item is! Map<String, dynamic>) continue;
      final title = _decodeEpgString(item['title']?.toString());
      final description = _decodeEpgString(item['description']?.toString());
      final start = _parseEpgTimestamp(item), end = _parseEpgTimestampEnd(item);
      if (start == null ||
          end == null ||
          !end.isAfter(start) ||
          title.isEmpty) {
        continue;
      }
      rows.add(
        ProgramsCompanion.insert(
          channelId: channelId,
          title: title,
          description: Value(description.isEmpty ? null : description),
          start: start,
          stop: end,
        ),
      );
    }
    return rows;
  }

  Future<void> _replaceEpg(int channelId, List<ProgramsCompanion> rows) async {
    // An invalid/empty response must not erase an existing guide. SQL failures
    // roll the delete and all insertion chunks back together.
    if (rows.isEmpty) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.programs,
      )..where((t) => t.channelId.equals(channelId))).go();
      for (var i = 0; i < rows.length; i += 500) {
        await _db.accountBatch((batch) {
          for (final row in rows.skip(i).take(500)) {
            batch.insert(_db.programs, row);
          }
        });
      }
      _db.checkAccountWrite();
    });
  }

  // ─── XMLTV Fallback EPG ──────────────────────────────────────────────────

  /// Sync EPG from XMLTV source for all live channels of an account.
  /// Used as fallback when Xtream EPG returns empty, or for M3U accounts.
  Future<int> syncEpgFromXmltv(int accountId, {bool force = false}) async {
    if (_db.accountScope != accountId) {
      return _bound(accountId).syncEpgFromXmltv(accountId, force: force);
    }
    // Get EPG URL for this account
    final epgUrl = await getEpgUrl(accountId);
    if (epgUrl == null || epgUrl.isEmpty) return 0;

    // Fetch and parse XMLTV data
    final xmltv = await XmltvService.fetchAndParse(epgUrl, force: force);
    if (xmltv == null || xmltv.programsByChannel.isEmpty) return 0;

    // Get all live channels with their epgChannelId
    final liveChannels = await (_db.select(
      _db.channels,
    )..where((tbl) => tbl.type.equals('live'))).get();

    if (liveChannels.isEmpty) return 0;

    int matchedCount = 0;
    final now = DateTime.now();
    final cutoffPast = now.subtract(const Duration(hours: 6));

    for (final channel in liveChannels) {
      // Try to find matching XMLTV channel ID using multiple identifiers
      String? xmltvChannelId;

      // Priority 1: epgChannelId (tvg-id from M3U or epg_channel_id from Xtream)
      if (channel.epgChannelId != null && channel.epgChannelId!.isNotEmpty) {
        xmltvChannelId = findXmltvChannelId(channel.epgChannelId!, xmltv);
      }

      // Priority 2: channel name
      xmltvChannelId ??= findXmltvChannelId(channel.name, xmltv);

      if (xmltvChannelId == null) continue;

      final programs = xmltv.programsByChannel[xmltvChannelId];
      if (programs == null || programs.isEmpty) continue;

      // Filter to relevant programs (not too old, not too far future)
      final relevant = programs
          .where((p) => p.stop.isAfter(cutoffPast))
          .toList();

      if (relevant.isEmpty) continue;

      await _replaceEpg(channel.streamId, [
        for (final p in relevant)
          ProgramsCompanion.insert(
            channelId: channel.streamId,
            title: p.title,
            description: Value(p.description),
            start: p.start,
            stop: p.stop,
          ),
      ]);

      matchedCount++;
    }

    return matchedCount;
  }

  /// Sync EPG for a single channel using XMLTV fallback
  Future<bool> syncChannelEpgFromXmltv(int accountId, int streamId) async {
    if (_db.accountScope != accountId) {
      return _bound(accountId).syncChannelEpgFromXmltv(accountId, streamId);
    }
    final epgUrl = await getEpgUrl(accountId);
    if (epgUrl == null || epgUrl.isEmpty) return false;

    final xmltv = await XmltvService.fetchAndParse(epgUrl);
    if (xmltv == null) return false;

    final channel =
        await (_db.select(_db.channels)..where(
              (tbl) => tbl.streamId.equals(streamId) & tbl.type.equals('live'),
            ))
            .getSingleOrNull();
    if (channel == null) return false;

    // Match channel to XMLTV
    String? xmltvChannelId;
    if (channel.epgChannelId != null && channel.epgChannelId!.isNotEmpty) {
      xmltvChannelId = findXmltvChannelId(channel.epgChannelId!, xmltv);
    }
    xmltvChannelId ??= findXmltvChannelId(channel.name, xmltv);
    if (xmltvChannelId == null) return false;

    final programs = xmltv.programsByChannel[xmltvChannelId];
    if (programs == null || programs.isEmpty) return false;

    final cutoffPast = DateTime.now().subtract(const Duration(hours: 6));
    final relevant = programs.where((p) => p.stop.isAfter(cutoffPast)).toList();
    if (relevant.isEmpty) return false;

    await _replaceEpg(streamId, [
      for (final p in relevant)
        ProgramsCompanion.insert(
          channelId: streamId,
          title: p.title,
          description: Value(p.description),
          start: p.start,
          stop: p.stop,
        ),
    ]);

    return true;
  }

  // ─── EPG URL Persistence ─────────────────────────────────────────────────

  /// Save EPG (XMLTV) URL discovered from M3U header to SharedPreferences
  Future<void> _saveEpgUrl(int accountId, String epgUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _db.checkAccountWrite();
      await prefs.setString('epg_url_$accountId', epgUrl);
    } catch (_) {}
  }

  /// Get EPG (XMLTV) URL for an account
  static Future<String?> getEpgUrl(int accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('epg_url_$accountId');
    } catch (_) {
      return null;
    }
  }

  // ─── EPG Helpers ──────────────────────────────────────────────────────────

  /// Decode a possibly base64-encoded EPG string (Xtream often base64 encodes title/desc)
  String _decodeEpgString(String? raw) {
    if (raw == null || raw.isEmpty) return '';

    // Try base64 decode first
    try {
      // Check if it looks like base64 (only contains valid base64 chars)
      final base64Pattern = RegExp(r'^[A-Za-z0-9+/=\s]+$');
      if (base64Pattern.hasMatch(raw.trim()) && raw.trim().length > 3) {
        final decoded = utf8.decode(base64Decode(raw.trim()));
        if (decoded.isNotEmpty && !decoded.contains('\x00')) {
          return decoded.trim();
        }
      }
    } catch (_) {}

    // Return as-is if not base64
    return raw.trim();
  }

  /// Parse EPG start time - tries start_timestamp (Unix epoch) first, then 'start' string
  DateTime? _parseEpgTimestamp(Map<String, dynamic> item) {
    // Try Unix timestamp first (most reliable)
    final startTs = item['start_timestamp'];
    if (startTs != null) {
      final ts = int.tryParse(startTs.toString());
      if (ts != null && ts > 0) {
        return DateTime.fromMillisecondsSinceEpoch(
          ts * 1000,
          isUtc: true,
        ).toLocal();
      }
    }

    // Fall back to 'start' string
    return _parseEpgTimeString(item['start']?.toString());
  }

  /// Parse EPG end time - tries stop_timestamp first, then 'end'/'stop' string
  DateTime? _parseEpgTimestampEnd(Map<String, dynamic> item) {
    // Try Unix timestamp first
    final stopTs = item['stop_timestamp'] ?? item['end_timestamp'];
    if (stopTs != null) {
      final ts = int.tryParse(stopTs.toString());
      if (ts != null && ts > 0) {
        return DateTime.fromMillisecondsSinceEpoch(
          ts * 1000,
          isUtc: true,
        ).toLocal();
      }
    }

    // Fall back to 'end' or 'stop' string
    return _parseEpgTimeString(
      item['end']?.toString() ?? item['stop']?.toString(),
    );
  }

  /// Parse EPG time string in various formats
  DateTime? _parseEpgTimeString(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      // Format: "2024-01-15 20:00:00" or similar ISO format
      final parsed = DateTime.tryParse(timeStr);
      if (parsed != null) return parsed.toLocal();

      // Format: "20240115200000" (YYYYMMDDHHmmss)
      if (timeStr.length >= 14) {
        final cleaned = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.length >= 14) {
          return DateTime.utc(
            int.parse(cleaned.substring(0, 4)),
            int.parse(cleaned.substring(4, 6)),
            int.parse(cleaned.substring(6, 8)),
            int.parse(cleaned.substring(8, 10)),
            int.parse(cleaned.substring(10, 12)),
            int.parse(cleaned.substring(12, 14)),
          ).toLocal();
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Tiered Sync ─────────────────────────────────────────────────────────

  /// A full job already includes catalogue tiers 1–3, never episode tier 4.
  Future<void> runTieredSync(Account account, SyncMetadata meta) async {
    if (_db.accountScope != account.id) {
      return _bound(account.id).runTieredSync(account, meta);
    }
    meta = meta.forAccount(account.id);
    if (meta.isDailyLimitExceeded) {
      throw const SyncFailure('Günlük senkronizasyon istek sınırına ulaşıldı.');
    }
    if (meta.isTierDue(3)) return syncAll(account);
    return _run(account, SyncKind.tiered, (_) async {
      if (account.type == 'm3u') return;
      if (account.type != 'xtream') {
        throw const SyncFailure('Desteklenmeyen hesap türü.');
      }
      final url = account.url.replaceAll(RegExp(r'/+$'), '');
      final username = account.username!;
      final password = account.password!;
      if (meta.isTierDue(1)) {
        await _syncCategoriesCount(url, username, password);
        _db.checkAccountWrite();
        await meta.markTierSynced(1);
        await meta.incrementApiCalls(3);
      }
      if (meta.isTierDue(2)) {
        await _syncStreams(
          url,
          username,
          password,
          'get_live_streams',
          'live',
          deltaOnly: true,
        );
        await _syncStreams(
          url,
          username,
          password,
          'get_vod_streams',
          'movie',
          deltaOnly: true,
        );
        await _syncStreams(
          url,
          username,
          password,
          'get_series',
          'series',
          deltaOnly: true,
        );
        _db.checkAccountWrite();
        await meta.markTierSynced(2);
        await meta.incrementApiCalls(3);
      }
      if (meta.isTierDue(4)) {
        await _syncWatchedSeriesEpisodes(url, username, password);
        _db.checkAccountWrite();
        await meta.markTierSynced(4);
      }
    });
  }

  /// A failed episode lookup must not advance tier 4. Keep each profile's
  /// tracking independent even when both watched the same series.
  Future<void> _syncWatchedSeriesEpisodes(
    String url,
    String username,
    String password,
  ) async {
    final watched =
        await (_db.select(_db.playbackProgress)
              ..where(
                (t) =>
                    t.type.equals('series_parent') &
                    t.position.isBiggerThanValue(0),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(20))
            .get();
    final counts = <int, int>{};
    for (final progress in watched) {
      final id = progress.streamId;
      if (!counts.containsKey(id)) {
        final info = await _api.getSeriesInfo(url, username, password, id);
        final episodes = info?['episodes'];
        if (episodes is! Map ||
            episodes.values.any((value) => value is! List)) {
          throw const FormatException('Invalid episode response');
        }
        counts[id] = episodes.values.fold<int>(
          0,
          (n, eps) => n + (eps as List).length,
        );
      }
    }
    await _db.transaction(() async {
      for (final progress in watched) {
        final id = progress.streamId;
        final count = counts[id]!;
        final existing =
            await (_db.select(_db.seriesTracking)..where(
                  (t) =>
                      t.seriesId.equals(id) &
                      t.profileId.equals(progress.profileId),
                ))
                .getSingleOrNull();
        if (existing == null) {
          await _db
              .into(_db.seriesTracking)
              .insert(
                SeriesTrackingCompanion.insert(
                  seriesId: id,
                  profileId: Value(progress.profileId),
                  knownEpisodeCount: count,
                  lastCheckedAt: Value(DateTime.now()),
                ),
              );
        } else {
          final added = count > existing.knownEpisodeCount;
          await (_db.update(_db.seriesTracking)..where(
                (t) =>
                    t.seriesId.equals(id) &
                    t.profileId.equals(progress.profileId),
              ))
              .write(
                SeriesTrackingCompanion(
                  knownEpisodeCount: added
                      ? Value(count)
                      : const Value.absent(),
                  newEpisodeCount: added
                      ? Value(
                          existing.newEpisodeCount +
                              count -
                              existing.knownEpisodeCount,
                        )
                      : const Value.absent(),
                  hasNewEpisodes: added
                      ? const Value(true)
                      : const Value.absent(),
                  lastCheckedAt: Value(DateTime.now()),
                ),
              );
        }
      }
      _db.checkAccountWrite();
    });
  }
}

@riverpod
SyncService syncService(Ref ref) {
  return SyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(xtreamApiServiceProvider),
  );
}
