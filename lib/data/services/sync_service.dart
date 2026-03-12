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
  final String step;      // Current step description
  final int liveCount;    // Number of live channels synced
  final int movieCount;   // Number of movies synced
  final int seriesCount;  // Number of series synced
  final int categoryCount;// Number of categories synced
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

  SyncService(this._db, this._api);

  Future<void> syncAll(Account account) async {
    if (account.type == 'm3u') {
      await _syncM3U(account);
      return;
    }
    if (account.type != 'xtream') return;

    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    final username = account.username!;
    final password = account.password!;

    await syncCategories(account);
    await _syncStreams(url, username, password, 'get_live_streams', 'live');
    await _syncStreams(url, username, password, 'get_vod_streams', 'movie');
    await _syncStreams(url, username, password, 'get_series', 'series');
  }

  /// Sync all data with progress callback
  Future<void> syncAllWithProgress(Account account, void Function(SyncProgress) onProgress) async {
    if (account.type == 'm3u') {
      await _syncM3UWithProgress(account, onProgress);
      return;
    }
    if (account.type != 'xtream') {
      onProgress(const SyncProgress(step: 'Done', isDone: true));
      return;
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
    onProgress(SyncProgress(step: 'Categories loaded', categoryCount: catCount));

    // Step 2: Live channels
    onProgress(SyncProgress(step: 'Loading live channels...', categoryCount: catCount));
    liveCount = await _syncStreamsCount(url, username, password, 'get_live_streams', 'live');
    onProgress(SyncProgress(step: 'Live channels loaded', categoryCount: catCount, liveCount: liveCount));

    // Step 3: Movies
    onProgress(SyncProgress(step: 'Loading movies...', categoryCount: catCount, liveCount: liveCount));
    movieCount = await _syncStreamsCount(url, username, password, 'get_vod_streams', 'movie');
    onProgress(SyncProgress(step: 'Movies loaded', categoryCount: catCount, liveCount: liveCount, movieCount: movieCount));

    // Step 4: Series
    onProgress(SyncProgress(step: 'Loading series...', categoryCount: catCount, liveCount: liveCount, movieCount: movieCount));
    seriesCount = await _syncStreamsCount(url, username, password, 'get_series', 'series');
    onProgress(SyncProgress(
      step: 'Done',
      categoryCount: catCount,
      liveCount: liveCount,
      movieCount: movieCount,
      seriesCount: seriesCount,
      isDone: true,
    ));
  }

  /// Sync categories and return count
  Future<int> _syncCategoriesCount(String url, String username, String password) async {
    int total = 0;
    try {
      final liveCats = await _api.getCategories(url, username, password, 'get_live_categories');
      await _saveCategories(liveCats, 'live');
      total += liveCats.length;

      final vodCats = await _api.getCategories(url, username, password, 'get_vod_categories');
      await _saveCategories(vodCats, 'movie');
      total += vodCats.length;

      final seriesCats = await _api.getCategories(url, username, password, 'get_series_categories');
      await _saveCategories(seriesCats, 'series');
      total += seriesCats.length;
    } catch (_) {}
    return total;
  }

  /// Sync streams and return count
  Future<int> _syncStreamsCount(String url, String username, String password, String action, String type) async {
    try {
      final streams = await _api.getStreams(url, username, password, action);
      if (streams.isEmpty) return 0;

      for (var i = 0; i < streams.length; i += 500) {
        final chunk = streams.skip(i).take(500).toList();
        await _db.batch((batch) {
          for (final item in chunk) {
            final streamId = item['stream_id'] ?? item['series_id'];
            if (streamId == null) continue;

            batch.insert(
              _db.channels,
              ChannelsCompanion.insert(
                streamId: int.tryParse(streamId.toString()) ?? 0,
                name: item['name']?.toString() ?? 'Unknown',
                type: type,
                categoryId: item['category_id']?.toString() ?? '0',
                streamIcon: Value(item['stream_icon']?.toString() ?? item['cover']?.toString()),
                rating: Value(double.tryParse(item['rating']?.toString() ?? '')),
                year: Value(item['year']?.toString()),
                added: Value(item['added']?.toString()),
                epgChannelId: Value(item['epg_channel_id']?.toString()),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      }
      return streams.length;
    } catch (_) {}
    return 0;
  }

  Future<void> syncCategories(Account account) async {
    if (account.type != 'xtream') return;

    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    final username = account.username!;
    final password = account.password!;

    final liveCats = await _api.getCategories(url, username, password, 'get_live_categories');
    await _saveCategories(liveCats, 'live');

    final vodCats = await _api.getCategories(url, username, password, 'get_vod_categories');
    await _saveCategories(vodCats, 'movie');

    final seriesCats = await _api.getCategories(url, username, password, 'get_series_categories');
    await _saveCategories(seriesCats, 'series');
  }

  Future<void> _syncStreams(String url, String username, String password, String action, String type) async {
    try {
      final streams = await _api.getStreams(url, username, password, action);
      if (streams.isEmpty) return;

      for (var i = 0; i < streams.length; i += 500) {
        final chunk = streams.skip(i).take(500).toList();
        await _db.batch((batch) {
          for (final item in chunk) {
            final streamId = item['stream_id'] ?? item['series_id'];
            if (streamId == null) continue;

            batch.insert(
              _db.channels,
              ChannelsCompanion.insert(
                streamId: int.tryParse(streamId.toString()) ?? 0,
                name: item['name']?.toString() ?? 'Unknown',
                type: type,
                categoryId: item['category_id']?.toString() ?? '0',
                streamIcon: Value(item['stream_icon']?.toString() ?? item['cover']?.toString()),
                rating: Value(double.tryParse(item['rating']?.toString() ?? '')),
                year: Value(item['year']?.toString()),
                added: Value(item['added']?.toString()),
                epgChannelId: Value(item['epg_channel_id']?.toString()),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCategories(List<dynamic> data, String type) async {
    await _db.batch((batch) {
      for (final item in data) {
        batch.insert(
          _db.categories,
          CategoriesCompanion.insert(
            id: item['category_id']?.toString() ?? '',
            name: item['category_name']?.toString() ?? 'Unknown',
            type: type,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  // ─── M3U Sync ───────────────────────────────────────────────────────────

  /// Sync M3U playlist with progress callback
  Future<void> _syncM3UWithProgress(Account account, void Function(SyncProgress) onProgress) async {
    onProgress(const SyncProgress(step: 'Downloading M3U playlist...'));

    M3URawResult rawResult;
    try {
      rawResult = await parseM3UFromUrlRaw(account.url);
    } catch (e) {
      throw Exception('M3U indirilemedi: $e');
    }

    final entries = rawResult.entries;

    // Save EPG URL from M3U header if available
    if (rawResult.epgUrl != null) {
      _saveEpgUrl(account.id, rawResult.epgUrl!);
    }

    onProgress(SyncProgress(step: 'Parsing channels (${entries.length})...'));

    final result = buildParseResult(entries, epgUrl: rawResult.epgUrl);

    // Save categories
    onProgress(SyncProgress(
      step: 'Saving categories...',
      categoryCount: result.categories.length,
    ));

    await _db.batch((batch) {
      for (final cat in result.categories) {
        batch.insert(
          _db.categories,
          CategoriesCompanion.insert(
            id: cat.id,
            name: cat.name,
            type: cat.type,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    // Save channels in 500-item batches
    onProgress(SyncProgress(
      step: 'Saving channels...',
      categoryCount: result.categories.length,
    ));

    for (var i = 0; i < entries.length; i += 500) {
      final chunk = entries.skip(i).take(500).toList();
      await _db.batch((batch) {
        for (var idx = 0; idx < chunk.length; idx++) {
          final entry = chunk[idx];
          final globalIdx = i + idx;
          final streamType = classifyStreamType(
            url: entry.url,
            name: entry.name,
            tvgType: entry.tvgType,
            groupTitle: entry.groupTitle,
          );

          // Channel name priority
          var channelName = entry.name;
          if (channelName.isEmpty) channelName = entry.tvgName ?? '';
          if (channelName.isEmpty) {
            try {
              final urlPath = Uri.parse(entry.url).pathSegments.lastOrNull ?? '';
              channelName = Uri.decodeComponent(urlPath)
                  .replaceAll(RegExp(r'\.\w{2,4}$'), '')
                  .replaceAll(RegExp(r'[_-]'), ' ')
                  .trim();
            } catch (_) {}
          }
          if (channelName.isEmpty) channelName = 'Kanal ${globalIdx + 1}';

          batch.insert(
            _db.channels,
            ChannelsCompanion.insert(
              streamId: globalIdx,
              name: channelName,
              type: streamType,
              categoryId: entry.groupTitle ?? 'Diğer',
              streamIcon: Value(entry.tvgLogo),
              streamUrl: Value(entry.url),
              epgChannelId: Value(entry.tvgId),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }

    onProgress(SyncProgress(
      step: 'Done',
      categoryCount: result.categories.length,
      liveCount: result.liveCount,
      movieCount: result.movieCount,
      seriesCount: result.seriesCount,
      isDone: true,
    ));
  }

  /// Sync M3U account (no progress callback)
  Future<void> _syncM3U(Account account) async {
    final rawResult = await parseM3UFromUrlRaw(account.url);
    final entries = rawResult.entries;
    final result = buildParseResult(entries, epgUrl: rawResult.epgUrl);

    // Save EPG URL from M3U header if available
    if (rawResult.epgUrl != null) {
      _saveEpgUrl(account.id, rawResult.epgUrl!);
    }

    await _db.batch((batch) {
      for (final cat in result.categories) {
        batch.insert(
          _db.categories,
          CategoriesCompanion.insert(id: cat.id, name: cat.name, type: cat.type),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    for (var i = 0; i < entries.length; i += 500) {
      final chunk = entries.skip(i).take(500).toList();
      await _db.batch((batch) {
        for (var idx = 0; idx < chunk.length; idx++) {
          final entry = chunk[idx];
          final globalIdx = i + idx;
          final streamType = classifyStreamType(
            url: entry.url, name: entry.name,
            tvgType: entry.tvgType, groupTitle: entry.groupTitle,
          );
          var channelName = entry.name.isNotEmpty ? entry.name : (entry.tvgName ?? 'Kanal ${globalIdx + 1}');

          batch.insert(
            _db.channels,
            ChannelsCompanion.insert(
              streamId: globalIdx,
              name: channelName,
              type: streamType,
              categoryId: entry.groupTitle ?? 'Diğer',
              streamIcon: Value(entry.tvgLogo),
              streamUrl: Value(entry.url),
              epgChannelId: Value(entry.tvgId),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
  }

  // ─── EPG Sync ─────────────────────────────────────────────────────────────

  /// Sync EPG for a single channel (short EPG)
  Future<void> syncEpg(Account account, String streamId) async {
    try {
      final url = account.url.replaceAll(RegExp(r'/+$'), '');
      final epgData = await _api.getEpg(
        url, account.username!, account.password!, streamId,
        limit: 20,
      );
      final listings = epgData['epg_listings'] as List<dynamic>?;
      if (listings == null || listings.isEmpty) return;

      final channelId = int.tryParse(streamId) ?? 0;

      // Delete old programs for this channel first
      await (_db.delete(_db.programs)
        ..where((tbl) => tbl.channelId.equals(channelId))
      ).go();

      await _db.batch((batch) {
        for (final item in listings) {
          final title = _decodeEpgString(item['title']?.toString());
          final description = _decodeEpgString(item['description']?.toString());
          final start = _parseEpgTimestamp(item);
          final end = _parseEpgTimestampEnd(item);

          if (start != null && end != null && title.isNotEmpty) {
            batch.insert(
              _db.programs,
              ProgramsCompanion.insert(
                channelId: channelId,
                title: title,
                description: Value(description.isNotEmpty ? description : null),
                start: start,
                stop: end,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
    } catch (_) {}
  }

  /// Batch sync EPG for multiple channels at once
  Future<void> syncEpgBatch(Account account, List<int> streamIds) async {
    if (account.type != 'xtream') return;

    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    final username = account.username!;
    final password = account.password!;

    // First try get_simple_data_table for all EPG at once
    try {
      final allEpg = await _api.getAllEpg(url, username, password);
      final listings = allEpg['epg_listings'] as List<dynamic>?;
      if (listings != null && listings.isNotEmpty) {
        await _saveBatchEpg(listings, streamIds.toSet());
        return;
      }
    } catch (_) {
      // Fall back to per-channel fetch
    }

    // Fallback: fetch EPG per channel (throttled, max 10 concurrent)
    const batchSize = 10;
    for (var i = 0; i < streamIds.length; i += batchSize) {
      final batch = streamIds.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((id) => _syncSingleChannelEpg(url, username, password, id)),
      );
      // Small delay to avoid hammering the server
      if (i + batchSize < streamIds.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  /// Sync EPG for all live channels of an account.
  /// For Xtream: uses API first, then XMLTV fallback for channels without EPG.
  /// For M3U: uses XMLTV directly (from url-tvg header).
  Future<void> syncAllLiveEpg(Account account) async {
    if (account.type == 'm3u') {
      // M3U accounts: use XMLTV directly
      await syncEpgFromXmltv(account.id);
      return;
    }

    if (account.type != 'xtream') return;

    // Get all live channel stream IDs from database
    final liveChannels = await (_db.select(_db.channels)
      ..where((tbl) => tbl.type.equals('live'))
    ).get();

    if (liveChannels.isEmpty) return;

    final streamIds = liveChannels.map((c) => c.streamId).toList();
    await syncEpgBatch(account, streamIds);

    // XMLTV fallback: check for channels still without EPG data
    final now = DateTime.now();
    int channelsWithoutEpg = 0;
    for (final ch in liveChannels) {
      final hasPrograms = await (_db.select(_db.programs)
        ..where((tbl) => tbl.channelId.equals(ch.streamId))
        ..where((tbl) => tbl.stop.isBiggerThanValue(now))
        ..limit(1)
      ).get();
      if (hasPrograms.isEmpty) channelsWithoutEpg++;
    }

    // If >50% channels lack EPG, try XMLTV fallback
    if (channelsWithoutEpg > liveChannels.length * 0.5) {
      await syncEpgFromXmltv(account.id);
    }
  }

  Future<void> _syncSingleChannelEpg(
    String url, String username, String password, int streamId,
  ) async {
    try {
      final epgData = await _api.getEpg(
        url, username, password, streamId.toString(),
        limit: 20,
      );
      final listings = epgData['epg_listings'] as List<dynamic>?;
      if (listings == null || listings.isEmpty) return;

      // Delete old programs for this channel
      await (_db.delete(_db.programs)
        ..where((tbl) => tbl.channelId.equals(streamId))
      ).go();

      await _db.batch((batch) {
        for (final item in listings) {
          final title = _decodeEpgString(item['title']?.toString());
          final description = _decodeEpgString(item['description']?.toString());
          final start = _parseEpgTimestamp(item);
          final end = _parseEpgTimestampEnd(item);

          if (start != null && end != null && title.isNotEmpty) {
            batch.insert(
              _db.programs,
              ProgramsCompanion.insert(
                channelId: streamId,
                title: title,
                description: Value(description.isNotEmpty ? description : null),
                start: start,
                stop: end,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _saveBatchEpg(List<dynamic> listings, Set<int> targetStreamIds) async {
    // Group listings by channel_id
    final Map<int, List<dynamic>> grouped = {};
    for (final item in listings) {
      final channelId = int.tryParse(item['channel_id']?.toString() ?? '');
      if (channelId == null) continue;
      // Only process channels we care about
      if (targetStreamIds.isNotEmpty && !targetStreamIds.contains(channelId)) continue;
      grouped.putIfAbsent(channelId, () => []).add(item);
    }

    // Delete old programs for these channels
    for (final channelId in grouped.keys) {
      await (_db.delete(_db.programs)
        ..where((tbl) => tbl.channelId.equals(channelId))
      ).go();
    }

    // Insert new programs in batches
    for (final entry in grouped.entries) {
      final channelId = entry.key;
      final items = entry.value;

      await _db.batch((batch) {
        for (final item in items) {
          final title = _decodeEpgString(item['title']?.toString());
          final description = _decodeEpgString(item['description']?.toString());
          final start = _parseEpgTimestamp(item);
          final end = _parseEpgTimestampEnd(item);

          if (start != null && end != null && title.isNotEmpty) {
            batch.insert(
              _db.programs,
              ProgramsCompanion.insert(
                channelId: channelId,
                title: title,
                description: Value(description.isNotEmpty ? description : null),
                start: start,
                stop: end,
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
    }
  }

  // ─── XMLTV Fallback EPG ──────────────────────────────────────────────────

  /// Sync EPG from XMLTV source for all live channels of an account.
  /// Used as fallback when Xtream EPG returns empty, or for M3U accounts.
  Future<int> syncEpgFromXmltv(int accountId) async {
    // Get EPG URL for this account
    final epgUrl = await getEpgUrl(accountId);
    if (epgUrl == null || epgUrl.isEmpty) return 0;

    // Fetch and parse XMLTV data
    final xmltv = await XmltvService.fetchAndParse(epgUrl);
    if (xmltv == null || xmltv.programsByChannel.isEmpty) return 0;

    // Get all live channels with their epgChannelId
    final liveChannels = await (_db.select(_db.channels)
      ..where((tbl) => tbl.type.equals('live'))
    ).get();

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
      if (xmltvChannelId == null) {
        xmltvChannelId = findXmltvChannelId(channel.name, xmltv);
      }

      if (xmltvChannelId == null) continue;

      final programs = xmltv.programsByChannel[xmltvChannelId];
      if (programs == null || programs.isEmpty) continue;

      // Filter to relevant programs (not too old, not too far future)
      final relevant = programs.where(
        (p) => p.stop.isAfter(cutoffPast),
      ).toList();

      if (relevant.isEmpty) continue;

      // Delete old programs for this channel
      await (_db.delete(_db.programs)
        ..where((tbl) => tbl.channelId.equals(channel.streamId))
      ).go();

      // Insert XMLTV programs
      await _db.batch((batch) {
        for (final program in relevant) {
          batch.insert(
            _db.programs,
            ProgramsCompanion.insert(
              channelId: channel.streamId,
              title: program.title,
              description: Value(program.description),
              start: program.start,
              stop: program.stop,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });

      matchedCount++;
    }

    return matchedCount;
  }

  /// Sync EPG for a single channel using XMLTV fallback
  Future<bool> syncChannelEpgFromXmltv(int accountId, int streamId) async {
    final epgUrl = await getEpgUrl(accountId);
    if (epgUrl == null || epgUrl.isEmpty) return false;

    final xmltv = await XmltvService.fetchAndParse(epgUrl);
    if (xmltv == null) return false;

    final channel = await (_db.select(_db.channels)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals('live'))
    ).getSingleOrNull();
    if (channel == null) return false;

    // Match channel to XMLTV
    String? xmltvChannelId;
    if (channel.epgChannelId != null && channel.epgChannelId!.isNotEmpty) {
      xmltvChannelId = findXmltvChannelId(channel.epgChannelId!, xmltv);
    }
    if (xmltvChannelId == null) {
      xmltvChannelId = findXmltvChannelId(channel.name, xmltv);
    }
    if (xmltvChannelId == null) return false;

    final programs = xmltv.programsByChannel[xmltvChannelId];
    if (programs == null || programs.isEmpty) return false;

    final cutoffPast = DateTime.now().subtract(const Duration(hours: 6));
    final relevant = programs.where((p) => p.stop.isAfter(cutoffPast)).toList();
    if (relevant.isEmpty) return false;

    await (_db.delete(_db.programs)
      ..where((tbl) => tbl.channelId.equals(streamId))
    ).go();

    await _db.batch((batch) {
      for (final program in relevant) {
        batch.insert(
          _db.programs,
          ProgramsCompanion.insert(
            channelId: streamId,
            title: program.title,
            description: Value(program.description),
            start: program.start,
            stop: program.stop,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    return true;
  }

  // ─── EPG URL Persistence ─────────────────────────────────────────────────

  /// Save EPG (XMLTV) URL discovered from M3U header to SharedPreferences
  Future<void> _saveEpgUrl(int accountId, String epgUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
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
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
      }
    }

    // Fall back to 'end' or 'stop' string
    return _parseEpgTimeString(item['end']?.toString() ?? item['stop']?.toString());
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

  /// Run tiered sync: checks each tier and syncs only what's due.
  /// Tier 1 (30m): categories, Tier 2 (2h): channel count delta,
  /// Tier 3 (6h): full refresh, Tier 4 (1h): watched series episodes
  Future<void> runTieredSync(Account account, SyncMetadata meta) async {
    if (!meta.tryAcquireMutex()) return; // Already syncing

    try {
      if (meta.isDailyLimitExceeded) return;

      if (account.type == 'm3u') {
        // M3U: only Tier 3 (full refresh)
        if (meta.isTierDue(3)) {
          await _syncM3U(account);
          await meta.markTierSynced(3);
        }
        return;
      }

      if (account.type != 'xtream') return;

      final url = account.url.replaceAll(RegExp(r'/+$'), '');
      final username = account.username!;
      final password = account.password!;

      // Tier 3 (6h) — Full content refresh (most expensive, check first)
      if (meta.isTierDue(3)) {
        // Clear account-specific cache
        final accountId = '$username@$url';
        ApiCache.instance.invalidateForAccount(accountId);

        await syncCategories(account);
        await _syncStreams(url, username, password, 'get_live_streams', 'live');
        await _syncStreams(url, username, password, 'get_vod_streams', 'movie');
        await _syncStreams(url, username, password, 'get_series', 'series');
        await meta.markTierSynced(3);
        // Tier 3 covers tiers 1 and 2 as well
        await meta.markTierSynced(1);
        await meta.markTierSynced(2);
        await meta.incrementApiCalls(4); // 3 stream calls + 3 category calls ≈ 4 effective
        return;
      }

      // Tier 1 (30m) — Lightweight category refresh
      if (meta.isTierDue(1)) {
        await syncCategories(account);
        await meta.markTierSynced(1);
        await meta.incrementApiCalls(3);
      }

      // Tier 2 (2h) — Channel count delta (re-sync only changed categories)
      if (meta.isTierDue(2)) {
        // For now, just re-sync all streams (could be optimized with delta in future)
        await _syncStreams(url, username, password, 'get_live_streams', 'live');
        await _syncStreams(url, username, password, 'get_vod_streams', 'movie');
        await _syncStreams(url, username, password, 'get_series', 'series');
        await meta.markTierSynced(2);
        await meta.incrementApiCalls(3);
      }

      // Tier 4 (1h) — Watched series episode check
      if (meta.isTierDue(4)) {
        await _syncWatchedSeriesEpisodes(url, username, password);
        await meta.markTierSynced(4);
      }
    } finally {
      meta.releaseMutex();
    }
  }

  /// Check for new episodes in watched series and update tracking
  Future<void> _syncWatchedSeriesEpisodes(
    String url, String username, String password,
  ) async {
    try {
      // Get series with playback progress (watched)
      final watchedSeries = await (_db.select(_db.playbackProgress)
        ..where((tbl) => tbl.type.equals('series'))
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.updatedAt, mode: OrderingMode.desc)])
        ..limit(20)
      ).get();

      if (watchedSeries.isEmpty) return;

      // Get unique series IDs
      final seriesIds = watchedSeries.map((p) => p.streamId).toSet();

      for (final seriesId in seriesIds) {
        try {
          final info = await _api.getSeriesInfo(url, username, password, seriesId);
          if (info == null) continue;

          // Count total episodes across all seasons
          final episodes = info['episodes'];
          int totalEpisodes = 0;
          if (episodes is Map) {
            for (final seasonEps in episodes.values) {
              if (seasonEps is List) {
                totalEpisodes += seasonEps.length;
              }
            }
          }

          if (totalEpisodes == 0) continue;

          // Check against stored tracking data
          final existing = await (_db.select(_db.seriesTracking)
            ..where((tbl) => tbl.seriesId.equals(seriesId))
          ).getSingleOrNull();

          if (existing == null) {
            // First time tracking — store current count, no "new" flag
            await _db.into(_db.seriesTracking).insert(
              SeriesTrackingCompanion.insert(
                seriesId: Value(seriesId),
                knownEpisodeCount: totalEpisodes,
                lastCheckedAt: Value(DateTime.now()),
              ),
            );
          } else if (totalEpisodes > existing.knownEpisodeCount) {
            // New episodes found!
            final newCount = totalEpisodes - existing.knownEpisodeCount;
            await (_db.update(_db.seriesTracking)
              ..where((tbl) => tbl.seriesId.equals(seriesId))
            ).write(SeriesTrackingCompanion(
              knownEpisodeCount: Value(totalEpisodes),
              newEpisodeCount: Value(newCount),
              hasNewEpisodes: const Value(true),
              lastCheckedAt: Value(DateTime.now()),
            ));
          } else {
            // No change, just update timestamp
            await (_db.update(_db.seriesTracking)
              ..where((tbl) => tbl.seriesId.equals(seriesId))
            ).write(SeriesTrackingCompanion(
              lastCheckedAt: Value(DateTime.now()),
            ));
          }
        } catch (_) {
          // Skip failed fetches
        }
      }
    } catch (_) {}
  }
}

@riverpod
SyncService syncService(Ref ref) {
  return SyncService(ref.watch(appDatabaseProvider), ref.watch(xtreamApiServiceProvider));
}
