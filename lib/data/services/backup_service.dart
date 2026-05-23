import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeostv/data/datasources/local/database.dart';

/// User-data backup / restore.
///
/// Exports a single JSON file with: accounts, favorites, playback progress,
/// series tracking, and SharedPreferences (settings, EPG URLs, last-chosen
/// audio/sub language, etc.). XMLTV cache and image caches are intentionally
/// skipped — both are large and trivially regenerable.
///
/// Restore wipes the matching tables in a transaction before inserting, so a
/// half-applied backup can't leave the DB in a mixed state.
class BackupService {
  final AppDatabase _db;

  /// Sentinel value written into every backup so importer can reject random
  /// JSON files. Bump [_currentVersion] when the on-disk schema changes; the
  /// importer refuses files with a higher version than it understands.
  static const String _magic = 'lifeos-tv-backup';
  static const int _currentVersion = 1;

  /// SharedPreferences keys we never include in backups (regenerable, large,
  /// or intentionally per-device).
  static const Set<String> _excludedPrefKeys = {};
  static const List<String> _excludedPrefPrefixes = [
    'xmltv_cache_',
    'xmltv_ts_',
  ];

  BackupService(this._db);

  // ─── Export ──────────────────────────────────────────────────────────────

  /// Build the full backup as a pretty-printed JSON string.
  Future<String> exportToJson() async {
    final accounts = await _db.select(_db.accounts).get();
    final favorites = await _db.select(_db.favorites).get();
    final watchlist = await _db.select(_db.watchlist).get();
    final progress = await _db.select(_db.playbackProgress).get();
    final tracking = await _db.select(_db.seriesTracking).get();

    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_excludedPrefKeys.contains(key)) continue;
      if (_excludedPrefPrefixes.any(key.startsWith)) continue;
      final value = prefs.get(key);
      // SharedPreferences only stores bool/int/double/String/List<String>;
      // jsonEncode handles all of them natively.
      settings[key] = value;
    }

    final payload = <String, dynamic>{
      'magic': _magic,
      'version': _currentVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'accounts': accounts.map(_accountToMap).toList(),
      'favorites': favorites.map(_favoriteToMap).toList(),
      'watchlist': watchlist.map(_watchlistToMap).toList(),
      'playbackProgress': progress.map(_progressToMap).toList(),
      'seriesTracking': tracking.map(_trackingToMap).toList(),
      'settings': settings,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Write the backup into the app's documents directory.
  /// Returns the absolute file path so the caller can show it in a SnackBar.
  Future<String> exportToFile() async {
    final json = await exportToJson();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/lifeostv-backup-$ts.json');
    await file.writeAsString(json);
    return file.path;
  }

  // ─── Import ──────────────────────────────────────────────────────────────

  /// Restore from a JSON string. Throws [FormatException] if the payload is
  /// not a valid LifeOs TV backup (missing magic / unsupported version).
  Future<void> importFromJson(String json) async {
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Backup is not valid JSON');
    }
    if (payload['magic'] != _magic) {
      throw const FormatException('Not a LifeOs TV backup file');
    }
    final version = payload['version'] as int? ?? 0;
    if (version > _currentVersion) {
      throw FormatException(
        'Backup version $version is newer than supported ($_currentVersion). '
        'Please update the app.',
      );
    }

    // Restore in a transaction so a half-applied backup can never leave the
    // DB in a partially-mutated state.
    await _db.transaction(() async {
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.favorites).go();
      await _db.delete(_db.watchlist).go();
      await _db.delete(_db.playbackProgress).go();
      await _db.delete(_db.seriesTracking).go();

      for (final raw in (payload['accounts'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        await _db.into(_db.accounts).insert(AccountsCompanion.insert(
              name: m['name'] as String? ?? 'Unnamed',
              type: m['type'] as String? ?? 'xtream',
              url: m['url'] as String? ?? '',
              username: Value(m['username'] as String?),
              password: Value(m['password'] as String?),
              isActive: Value(m['isActive'] as bool? ?? false),
              createdAt: Value(_parseDate(m['createdAt']) ?? DateTime.now()),
            ));
      }

      for (final raw in (payload['favorites'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        await _db.into(_db.favorites).insert(FavoritesCompanion.insert(
              streamId: m['streamId'] as int,
              streamType: m['streamType'] as String,
              name: m['name'] as String? ?? '',
              thumbnail: Value(m['thumbnail'] as String?),
              addedAt: Value(_parseDate(m['addedAt']) ?? DateTime.now()),
            ));
      }

      // Watchlist (added in schema v11). Older backups won't carry the key.
      for (final raw in (payload['watchlist'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        await _db.into(_db.watchlist).insert(WatchlistCompanion.insert(
              streamId: m['streamId'] as int,
              streamType: m['streamType'] as String,
              name: m['name'] as String? ?? '',
              thumbnail: Value(m['thumbnail'] as String?),
              addedAt: Value(_parseDate(m['addedAt']) ?? DateTime.now()),
            ));
      }

      for (final raw in (payload['playbackProgress'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        await _db
            .into(_db.playbackProgress)
            .insert(PlaybackProgressCompanion.insert(
              streamId: m['streamId'] as int,
              type: m['type'] as String,
              position: m['position'] as int? ?? 0,
              duration: m['duration'] as int? ?? 0,
              isFinished: Value(m['isFinished'] as bool? ?? false),
              updatedAt: Value(_parseDate(m['updatedAt']) ?? DateTime.now()),
            ));
      }

      for (final raw in (payload['seriesTracking'] as List? ?? const [])) {
        final m = raw as Map<String, dynamic>;
        await _db
            .into(_db.seriesTracking)
            .insert(SeriesTrackingCompanion.insert(
              seriesId: m['seriesId'] as int,
              knownEpisodeCount: m['knownEpisodeCount'] as int? ?? 0,
              newEpisodeCount: Value(m['newEpisodeCount'] as int? ?? 0),
              hasNewEpisodes: Value(m['hasNewEpisodes'] as bool? ?? false),
              lastCheckedAt:
                  Value(_parseDate(m['lastCheckedAt']) ?? DateTime.now()),
            ));
      }
    });

    // Settings are persisted to SharedPreferences after the DB transaction so
    // a SharedPrefs failure can't leave us with new DB rows pointing at old
    // setting values.
    final settings = payload['settings'];
    if (settings is Map<String, dynamic>) {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in settings.entries) {
        final v = entry.value;
        if (v is bool) {
          await prefs.setBool(entry.key, v);
        } else if (v is int) {
          await prefs.setInt(entry.key, v);
        } else if (v is double) {
          await prefs.setDouble(entry.key, v);
        } else if (v is String) {
          await prefs.setString(entry.key, v);
        } else if (v is List) {
          await prefs.setStringList(
            entry.key,
            v.map((e) => e.toString()).toList(),
          );
        }
      }
    }
  }

  /// Read a backup file from disk and import it.
  Future<void> importFromFile(String filePath) async {
    final json = await File(filePath).readAsString();
    await importFromJson(json);
  }

  // ─── Row → Map helpers ───────────────────────────────────────────────────

  Map<String, dynamic> _accountToMap(Account a) => {
        'id': a.id,
        'name': a.name,
        'type': a.type,
        'url': a.url,
        'username': a.username,
        'password': a.password,
        'isActive': a.isActive,
        'createdAt': a.createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _favoriteToMap(Favorite f) => {
        'streamId': f.streamId,
        'streamType': f.streamType,
        'name': f.name,
        'thumbnail': f.thumbnail,
        'addedAt': f.addedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _watchlistToMap(WatchlistData w) => {
        'streamId': w.streamId,
        'streamType': w.streamType,
        'name': w.name,
        'thumbnail': w.thumbnail,
        'addedAt': w.addedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _progressToMap(PlaybackProgressData p) => {
        'streamId': p.streamId,
        'type': p.type,
        'position': p.position,
        'duration': p.duration,
        'isFinished': p.isFinished,
        'updatedAt': p.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _trackingToMap(SeriesTrackingData s) => {
        'seriesId': s.seriesId,
        'knownEpisodeCount': s.knownEpisodeCount,
        'newEpisodeCount': s.newEpisodeCount,
        'hasNewEpisodes': s.hasNewEpisodes,
        'lastCheckedAt': s.lastCheckedAt.toUtc().toIso8601String(),
      };

  static DateTime? _parseDate(Object? raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});
