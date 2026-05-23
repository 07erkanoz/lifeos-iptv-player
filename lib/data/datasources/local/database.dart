import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Accounts, Profiles, Categories, Channels, Programs, PlaybackProgress, Favorites, Watchlist, SeriesTracking, IntroMarkers, PlotAiCache, PersonalizedPicksCache, AiCallLogs, AiFeedback, SearchHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
       await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
       if (from < 2) {
         await m.createTable(categories);
         await m.createTable(channels);
       }
       if (from < 3) {
         await m.createTable(programs);
       }
       if (from < 4) {
         await m.createTable(playbackProgress);
       }
       if (from < 5) {
         await m.addColumn(categories, categories.isHidden);
       }
       if (from < 6) {
         await m.createTable(favorites);
         await m.addColumn(channels, channels.backdropPath);
         await m.addColumn(channels, channels.youtubeTrailer);
       }
       if (from < 7) {
         await m.addColumn(channels, channels.genre);
         await m.addColumn(channels, channels.plot);
         await m.addColumn(channels, channels.director);
         await m.addColumn(channels, channels.cast);
       }
       if (from < 8) {
         await m.addColumn(channels, channels.streamUrl);
       }
       if (from < 9) {
         await m.addColumn(channels, channels.epgChannelId);
       }
       if (from < 10) {
         await m.createTable(seriesTracking);
       }
       if (from < 11) {
         await m.createTable(watchlist);
       }
       if (from < 12) {
         // Skip-Intro feature: per-series intro position markers.
         await m.createTable(introMarkers);
       }
       if (from < 13) {
         // AI plot enrichment cache (translate / summarize /
         // fillIn / detailedInfo).
         await m.createTable(plotAiCache);
       }
       if (from < 14) {
         // Dashboard "Sana Özel" personalised picks cache.
         await m.createTable(personalizedPicksCache);
       }
       if (from < 15) {
         // AI call telemetry ring buffer (Settings → Debug panel).
         await m.createTable(aiCallLogs);
       }
       if (from < 16) {
         // Per-title AI feedback ("Sevmedim" / "Bunun gibi daha").
         await m.createTable(aiFeedback);
       }
       if (from < 17) {
         // Recent / trending search queries. Client-side only —
         // never synced to a remote, so the user's search history
         // stays private to the device.
         await m.createTable(searchHistory);
       }
       if (from < 18) {
         // ───── Multiple Profiles foundation ─────
         //
         // Netflix-style per-person personas. Six existing
         // user-specific tables grow a `profileId` column; we seed
         // a "Varsayılan" profile (id=1) and every pre-existing row
         // backfills to it. Single-user installs see no behavioural
         // change — they just get one implicit profile.
         //
         // CRITICAL: every step is wrapped in idempotent guards.
         // Reason: some users were running an off-fork binary
         // (versionCode 2001) whose schema already had profileId
         // columns + the profiles table even though Drift's
         // user_version pragma still reported < 18. Without these
         // guards the ALTER TABLE raised "duplicate column" and
         // crashed the app on launch — the v1.1.0 disaster. Each
         // statement now uses IF-NOT-EXISTS semantics (raw SQL)
         // so re-running the migration on a half-applied DB is
         // safe.
         await _migrateToV18(m);
       }
    },
    beforeOpen: (details) async {
      // Idempotent safety net: covers off-fork builds where the
      // schema has the profiles columns but Drift's user_version
      // pragma doesn't reflect v18 yet (so onUpgrade(< 18, …)
      // didn't fire). Apply any missing parts here too.
      await _migrateToV18Idempotent();

      // Belt-and-braces seed: if the user nuked their DB or this is
      // a fresh install on v18+, ensure profile 1 exists before any
      // FK-bound query fires. INSERT OR IGNORE — no-op when present.
      await customStatement(
        "INSERT OR IGNORE INTO profiles (id, name, avatar_key, "
        "is_kids, created_at) VALUES (1, 'Varsayılan', 'default', "
        "0, ${DateTime.now().millisecondsSinceEpoch ~/ 1000})",
      );
    },
  );

  /// Apply the v18 schema changes via idempotent SQL. Used by both
  /// the `onUpgrade(from < 18, …)` branch AND the `beforeOpen` hook
  /// because a previous attempt may have half-applied the schema
  /// (e.g. profile_id column already added but profiles table not
  /// created, or vice versa) and Drift's user_version pragma alone
  /// isn't enough to tell the two states apart.
  ///
  /// Every statement uses `CREATE TABLE IF NOT EXISTS` or a
  /// try-add-column wrapper so re-running on an already-migrated
  /// schema is a silent no-op.
  Future<void> _migrateToV18(Migrator m) async {
    // 1. Profiles table — IF NOT EXISTS via raw SQL because
    //    `m.createTable(profiles)` would throw "table already
    //    exists" on a half-applied schema.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        avatar_key TEXT NOT NULL DEFAULT 'default',
        is_kids INTEGER NOT NULL DEFAULT 0,
        pin TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // 2. Per-table profile_id column adds. SQLite doesn't support
    //    "ALTER TABLE … ADD COLUMN IF NOT EXISTS", so we probe
    //    PRAGMA table_info first and only ADD when the column is
    //    actually missing.
    await _addProfileIdIfMissing('favorites');
    await _addProfileIdIfMissing('playback_progress');
    await _addProfileIdIfMissing('watchlist');
    await _addProfileIdIfMissing('series_tracking');
    await _addProfileIdIfMissing('ai_feedback');
    await _addProfileIdIfMissing('search_history');

    // 3. Seed the default profile (no-op when already present).
    await customStatement(
      "INSERT OR IGNORE INTO profiles (id, name, avatar_key, "
      "is_kids, created_at) VALUES (1, 'Varsayılan', 'default', "
      "0, ${DateTime.now().millisecondsSinceEpoch ~/ 1000})",
    );
  }

  /// Same operations as [_migrateToV18] but bound to `beforeOpen`
  /// — no Migrator available, so we use the customStatement path
  /// throughout. Idempotent.
  Future<void> _migrateToV18Idempotent() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        avatar_key TEXT NOT NULL DEFAULT 'default',
        is_kids INTEGER NOT NULL DEFAULT 0,
        pin TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await _addProfileIdIfMissing('favorites');
    await _addProfileIdIfMissing('playback_progress');
    await _addProfileIdIfMissing('watchlist');
    await _addProfileIdIfMissing('series_tracking');
    await _addProfileIdIfMissing('ai_feedback');
    await _addProfileIdIfMissing('search_history');
  }

  /// Probe-and-add helper. Reads PRAGMA table_info(<tableName>) —
  /// returns one row per column with the column's name in field 1.
  /// If `profile_id` is already there, no-op. Otherwise issue the
  /// ADD COLUMN statement with the same defaults the Drift schema
  /// declares (`INTEGER NOT NULL DEFAULT 1`).
  Future<void> _addProfileIdIfMissing(String tableName) async {
    final rows = await customSelect(
      'PRAGMA table_info($tableName)',
    ).get();
    final hasIt = rows.any((r) => r.data['name'] == 'profile_id');
    if (hasIt) return;
    await customStatement(
      'ALTER TABLE $tableName ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1',
    );
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'lifeostv');
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  return AppDatabase();
}
