import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'backup_document.dart';

/// Versioned, profile-preserving backup. Catalogues and derived caches are
/// regenerated. Account credentials and profile PINs are part of the file;
/// device pairing identities and external API keys stay on their own device.
class BackupService {
  final AppDatabase _db;
  final SharedPreferences? _preferences;
  static final _busy = Expando<bool>();

  BackupService(AppDatabase db, {SharedPreferences? preferences})
    : _db = db.root,
      _preferences = preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? await SharedPreferences.getInstance();

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy[_db] == true) {
      throw StateError('Backup operation already running');
    }
    _busy[_db] = true;
    try {
      return await action();
    } finally {
      _busy[_db] = false;
    }
  }

  Future<String> exportToJson() => _exclusive(() async {
    final prefs = await _prefs;
    await _recover(prefs);
    final payload = await _db.transaction(
      () async => <String, dynamic>{
        'magic': BackupDocument.magic,
        'version': BackupDocument.version,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'accounts': (await _db.select(_db.accounts).get())
            .map((r) => r.toJson())
            .toList(),
        'profiles': (await _db.select(_db.profiles).get())
            .map((r) => r.toJson())
            .toList(),
        'favorites': (await _db.select(_db.favorites).get())
            .map((r) => r.toJson())
            .toList(),
        'watchlist': (await _db.select(_db.watchlist).get())
            .map((r) => r.toJson())
            .toList(),
        'playbackProgress': (await _db.select(_db.playbackProgress).get())
            .map((r) => r.toJson())
            .toList(),
        'seriesTracking': (await _db.select(_db.seriesTracking).get())
            .map((r) => r.toJson())
            .toList(),
        'introMarkers': (await _db.select(_db.introMarkers).get())
            .map((r) => r.toJson())
            .toList(),
        'aiFeedback': (await _db.select(_db.aiFeedback).get())
            .map((r) => r.toJson())
            .toList(),
        'searchHistory': (await _db.select(_db.searchHistory).get())
            .map((r) => r.toJson())
            .toList(),
        'categoryPrefs': (await _db.select(_db.categoryPrefs).get())
            .map((r) => r.toJson())
            .toList(),
        'syncTombstones': (await _db.select(_db.syncTombstones).get())
            .map((r) => r.toJson())
            .toList(),
        'm3uIdentities': (await _db.select(_db.m3uIdentities).get())
            .map((r) => r.toJson())
            .toList(),
        'settings': {
          for (final key in prefs.getKeys())
            if (BackupDocument.isPortableSetting(key)) key: prefs.get(key),
        },
        'excluded': [
          'catalogue',
          'EPG cache',
          'AI derived caches/telemetry',
          'device pairing',
          'external API keys',
          'sync timestamps',
        ],
      },
    );
    return const JsonEncoder.withIndent('  ').convert(payload);
  });

  /// Write the backup into the app's documents directory.
  /// Returns the absolute file path so the caller can show it in a
  /// SnackBar.
  ///
  /// IMPORTANT: this path lives inside the app's PRIVATE sandbox
  /// (`/data/data/<package>/app_flutter/`). On non-rooted Android,
  /// the user has NO way to access this file once the app is
  /// uninstalled — defeating the whole point of a backup. Prefer
  /// [exportToUserPickedFile] for any user-facing backup flow.
  /// This older API survives for callers that want a quick
  /// internal snapshot (e.g. before a destructive migration).
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

  /// Export the backup to a user-picked location (Downloads, Drive,
  /// SD card, etc.) via the platform Storage Access Framework. The
  /// file lives OUTSIDE the app sandbox, so a future uninstall
  /// won't take the backup with it.
  ///
  /// Returns the saved file path on success, null if the user
  /// dismissed the picker. Caller is expected to surface a snackbar
  /// on either branch.
  ///
  /// Uses `file_picker.saveFile` so the same call works on Android,
  /// iOS, and desktop. On Android the SAF picker lets the user pick
  /// any folder they have write access to.
  Future<String?> exportToUserPickedFile({
    String dialogTitle = 'LifeOS TV backup',
  }) async {
    final json = await exportToJson();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final suggestedName = 'lifeostv-backup-$ts.json';
    final bytes = utf8.encode(json);

    // saveFile on Android 11+ writes the file directly via SAF when
    // we pass `bytes`; older flow only returns the chosen path and
    // expects us to write. Handle both:
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (picked == null) return null;

    // saveFile + bytes already wrote the file on Android. On desktop
    // and older API levels we still need to write. Check whether the
    // file actually exists at the returned path; if not, write it
    // manually.
    final file = File(picked);
    if (Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS ||
        !await file.exists() ||
        await file.length() == 0) {
      await file.writeAsString(json);
    }
    return picked;
  }

  Future<void> importFromJson(String source) => _exclusive(() async {
    // Full validation happens BEFORE even creating the rollback journal.
    final document = BackupDocument.parse(source);
    final prefs = await _prefs;
    await _recover(prefs);
    _db.beginRestore();
    try {
      final previous = <String, dynamic>{
        for (final key in prefs.getKeys())
          if (!BackupDocument.isDeviceSetting(key)) key: prefs.get(key),
      };

      // Durable before the transaction: a crash rolls the DB back, while this
      // record lets startup roll preferences back before constructing providers.
      await _db
          .into(_db.backupRestoreJournal)
          .insert(
            BackupRestoreJournalCompanion.insert(
              id: const Value(0),
              preferencesJson: jsonEncode(previous),
            ),
            mode: InsertMode.insertOrReplace,
          );
      try {
        await _db.transaction(() async {
          // Clear derived rows from the old catalogue so reused provider IDs
          // cannot inherit another account's metadata or cached suggestions.
          for (final table in <TableInfo<Table, dynamic>>[
            _db.programs,
            _db.channels,
            _db.categories,
            _db.plotAiCache,
            _db.personalizedPicksCache,
            _db.aiSimilarCache,
            _db.contentEnrichment,
            _db.contentEmbeddings,
            _db.aiCallLogs,
          ]) {
            await _db.delete(table).go();
          }
          await _replace(_db.accounts, document, 'accounts', Account.fromJson);
          await _replace(_db.profiles, document, 'profiles', Profile.fromJson);
          await _replace(
            _db.favorites,
            document,
            'favorites',
            Favorite.fromJson,
          );
          await _replace(
            _db.watchlist,
            document,
            'watchlist',
            WatchlistData.fromJson,
          );
          await _replace(
            _db.playbackProgress,
            document,
            'playbackProgress',
            PlaybackProgressData.fromJson,
          );
          await _replace(
            _db.seriesTracking,
            document,
            'seriesTracking',
            SeriesTrackingData.fromJson,
          );
          await _replace(
            _db.introMarkers,
            document,
            'introMarkers',
            IntroMarker.fromJson,
          );
          await _replace(
            _db.aiFeedback,
            document,
            'aiFeedback',
            AiFeedbackData.fromJson,
          );
          await _replace(
            _db.searchHistory,
            document,
            'searchHistory',
            SearchHistoryData.fromJson,
          );
          await _replace(
            _db.categoryPrefs,
            document,
            'categoryPrefs',
            CategoryPref.fromJson,
          );
          await _replace(
            _db.syncTombstones,
            document,
            'syncTombstones',
            SyncTombstone.fromJson,
          );
          await _replace(
            _db.m3uIdentities,
            document,
            'm3uIdentities',
            M3uIdentity.fromJson,
          );
          await _replacePreferences(prefs, document.settings);
          // If COMMIT fails, this deletion rolls back with the restored rows.
          await _db.delete(_db.backupRestoreJournal).go();
        });
      } catch (_) {
        await _recover(prefs);
        rethrow;
      }
      ApiCache.instance.clear();
    } finally {
      _db.finishRestore();
    }
  });

  Future<void> _replace<T extends DataClass>(
    TableInfo<Table, T> table,
    BackupDocument document,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) async {
    final rows = document.tables[key]!.map(decode).toList();
    await _db.delete(table).go();
    await _db.batch(
      (batch) => batch.insertAll(
        table,
        rows.map((row) => row as Insertable<T>).toList(),
      ),
    );
  }

  /// Must finish before normal startup reads preferences. Also called before
  /// each backup operation, allowing a failed write to be retried safely.
  Future<void> recoverPendingRestore() => _exclusive(() async {
    await _recover(await _prefs);
  });

  Future<void> _recover(SharedPreferences prefs) async {
    final pending = await _db
        .select(_db.backupRestoreJournal)
        .getSingleOrNull();
    if (pending == null) return;
    final previous =
        jsonDecode(pending.preferencesJson) as Map<String, dynamic>;
    BackupDocument.validateSettings(previous);
    await _replacePreferences(prefs, previous);
    await _db.delete(_db.backupRestoreJournal).go();
  }

  Future<void> _replacePreferences(
    SharedPreferences prefs,
    Map<String, dynamic> values,
  ) async {
    for (final key in prefs.getKeys().toList()) {
      if (!BackupDocument.isDeviceSetting(key) && !values.containsKey(key)) {
        if (!await prefs.remove(key)) {
          throw StateError('Preference removal failed');
        }
      }
    }
    for (final entry in values.entries) {
      if (BackupDocument.isDeviceSetting(entry.key)) continue;
      final value = entry.value;
      final bool saved;
      if (value is bool) {
        saved = await prefs.setBool(entry.key, value);
      } else if (value is int) {
        saved = await prefs.setInt(entry.key, value);
      } else if (value is double) {
        saved = await prefs.setDouble(entry.key, value);
      } else if (value is String) {
        saved = await prefs.setString(entry.key, value);
      } else {
        saved = await prefs.setStringList(
          entry.key,
          (value as List).cast<String>(),
        );
      }
      if (!saved) throw StateError('Preference write failed');
    }
  }

  Future<void> importFromFile(String filePath) async {
    await importFromJson(await File(filePath).readAsString());
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(rootDatabaseProvider));
});
