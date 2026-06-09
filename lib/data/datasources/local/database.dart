import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Accounts, Profiles, Categories, Channels, Programs, PlaybackProgress, Favorites, Watchlist, SeriesTracking, IntroMarkers, PlotAiCache, PersonalizedPicksCache, AiCallLogs, AiFeedback, SearchHistory, AiSimilarCache, ContentEnrichment, ContentEmbeddings, SyncTombstones, CategoryPrefs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 22;

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
       if (from < 19) {
         // AI similar-content cache. New table, no PK rewrite —
         // safe to use `createTable` directly. IF NOT EXISTS via
         // raw SQL so a half-applied state isn't an issue.
         await customStatement('''
           CREATE TABLE IF NOT EXISTS ai_similar_cache (
             stream_id INTEGER NOT NULL,
             type TEXT NOT NULL,
             payload_json TEXT NOT NULL,
             source_hash TEXT NOT NULL,
             generated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
             PRIMARY KEY (stream_id, type)
           )
         ''');
       }
       if (from < 20) {
         // AI catalogue enrichment (fills sparse genre/year/mood for
         // Turkish IPTV catalogues). New table, additive — no PK
         // rewrite. IF NOT EXISTS so a half-applied state is safe.
         await customStatement('''
           CREATE TABLE IF NOT EXISTS content_enrichment (
             stream_id INTEGER NOT NULL,
             type TEXT NOT NULL,
             genres TEXT,
             year INTEGER,
             mood_tags TEXT,
             themes TEXT,
             content_warnings TEXT,
             age_rating TEXT,
             confidence REAL,
             source TEXT,
             updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
             PRIMARY KEY (stream_id, type)
           )
         ''');
       }
       if (from < 21) {
         // Semantic embeddings (offline similarity / search). New
         // table, additive — IF NOT EXISTS for half-applied safety.
         await customStatement('''
           CREATE TABLE IF NOT EXISTS content_embeddings (
             stream_id INTEGER NOT NULL,
             type TEXT NOT NULL,
             vector BLOB NOT NULL,
             dims INTEGER NOT NULL,
             updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
             PRIMARY KEY (stream_id, type)
           )
         ''');
       }
       if (from < 22) {
         // Delete-propagation tombstones + category-visibility prefs
         // for LAN sync. Both additive, IF NOT EXISTS for half-applied
         // safety.
         await customStatement('''
           CREATE TABLE IF NOT EXISTS sync_tombstones (
             entity TEXT NOT NULL,
             stream_id INTEGER NOT NULL,
             stream_type TEXT NOT NULL,
             profile_id INTEGER NOT NULL DEFAULT 1,
             deleted_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
             PRIMARY KEY (entity, stream_id, stream_type, profile_id)
           )
         ''');
         await customStatement('''
           CREATE TABLE IF NOT EXISTS category_prefs (
             category_id TEXT NOT NULL,
             type TEXT NOT NULL,
             is_hidden INTEGER NOT NULL DEFAULT 0,
             updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
             PRIMARY KEY (category_id, type)
           )
         ''');
         // Backfill prefs from any categories the user already hid, so
         // existing choices survive the first catalogue refresh.
         await customStatement('''
           INSERT OR IGNORE INTO category_prefs (category_id, type, is_hidden, updated_at)
           SELECT id, type, is_hidden, (strftime('%s','now'))
           FROM categories WHERE is_hidden = 1
         ''');
       }
    },
    beforeOpen: (details) async {
      // Idempotent safety net: covers off-fork builds where the
      // schema has the profiles columns but Drift's user_version
      // pragma doesn't reflect v18 yet (so onUpgrade(< 18, …)
      // didn't fire). Apply any missing parts here too.
      await _migrateToV18Idempotent();

      // ⚠️ CRITICAL — see ONEMLI.md.
      //
      // The Sprint 2a addColumn-only migration left every per-
      // profile table with the OLD primary key (streamId,
      // streamType) instead of the new composite (streamId,
      // streamType, profileId). The Drift-generated code expects
      // the new PK, so inserts/upserts misbehave (the "favori
      // butonu çalışmıyor" report).
      //
      // Fix: rebuild each table with the correct PK via create-
      // copy-drop-rename. Probe PRAGMA table_info first so we only
      // pay the cost on devices that genuinely have the wrong PK.
      await _fixCompositePrimaryKeys();

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

  /// Walk every per-profile table and rebuild any whose primary
  /// key still excludes `profile_id`. Idempotent: tables that
  /// already have the correct composite PK skip immediately.
  ///
  /// PRAGMA table_info column shape: cid, name, type, notnull,
  /// dflt_value, pk — `pk` is 0 for non-PK columns, and a 1-based
  /// position when it IS part of the PK. We compare the actual
  /// profile_id pk position to "should be part of PK"; mismatch
  /// triggers the recreate-with-copy.
  Future<void> _fixCompositePrimaryKeys() async {
    // Each entry: (table name, full CREATE TABLE statement with
    // correct PK, list of columns to copy). Column lists are
    // verbatim from tables.dart so a future schema edit forces
    // an update here too (which is the whole point — schema
    // changes go through this file).
    final tables = <_PkFix>[
      _PkFix(
        name: 'favorites',
        recreateSql: '''
          CREATE TABLE favorites (
            stream_id INTEGER NOT NULL,
            stream_type TEXT NOT NULL,
            name TEXT NOT NULL,
            thumbnail TEXT,
            added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (stream_id, stream_type, profile_id)
          )
        ''',
        columns: ['stream_id', 'stream_type', 'name', 'thumbnail',
            'added_at', 'profile_id'],
      ),
      _PkFix(
        name: 'playback_progress',
        recreateSql: '''
          CREATE TABLE playback_progress (
            stream_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            position INTEGER NOT NULL,
            duration INTEGER NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            is_finished INTEGER NOT NULL DEFAULT 0,
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (stream_id, type, profile_id)
          )
        ''',
        columns: ['stream_id', 'type', 'position', 'duration',
            'updated_at', 'is_finished', 'profile_id'],
      ),
      _PkFix(
        name: 'watchlist',
        recreateSql: '''
          CREATE TABLE watchlist (
            stream_id INTEGER NOT NULL,
            stream_type TEXT NOT NULL,
            name TEXT NOT NULL,
            thumbnail TEXT,
            added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (stream_id, stream_type, profile_id)
          )
        ''',
        columns: ['stream_id', 'stream_type', 'name', 'thumbnail',
            'added_at', 'profile_id'],
      ),
      _PkFix(
        name: 'series_tracking',
        recreateSql: '''
          CREATE TABLE series_tracking (
            series_id INTEGER NOT NULL,
            known_episode_count INTEGER NOT NULL,
            new_episode_count INTEGER NOT NULL DEFAULT 0,
            has_new_episodes INTEGER NOT NULL DEFAULT 0,
            last_checked_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (series_id, profile_id)
          )
        ''',
        columns: ['series_id', 'known_episode_count',
            'new_episode_count', 'has_new_episodes', 'last_checked_at',
            'profile_id'],
      ),
      _PkFix(
        name: 'ai_feedback',
        recreateSql: '''
          CREATE TABLE ai_feedback (
            stream_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            action TEXT NOT NULL,
            feature TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (stream_id, type, action, profile_id)
          )
        ''',
        columns: ['stream_id', 'type', 'action', 'feature',
            'created_at', 'profile_id'],
      ),
      _PkFix(
        name: 'search_history',
        recreateSql: '''
          CREATE TABLE search_history (
            query TEXT NOT NULL,
            last_used_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            use_count INTEGER NOT NULL DEFAULT 1,
            profile_id INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (query, profile_id)
          )
        ''',
        columns: ['query', 'last_used_at', 'use_count', 'profile_id'],
      ),
    ];
    for (final t in tables) {
      if (await _isProfileIdMissingFromPk(t.name)) {
        await _recreateTableWithPk(t);
      }
    }
  }

  /// Returns true when [tableName] exists but `profile_id`'s `pk`
  /// column in PRAGMA table_info is 0 (= not part of the primary
  /// key). Tables that don't exist yet return false — the create
  /// path handles them.
  Future<bool> _isProfileIdMissingFromPk(String tableName) async {
    final rows = await customSelect(
      'PRAGMA table_info($tableName)',
    ).get();
    if (rows.isEmpty) return false; // table doesn't exist yet
    final profileRow =
        rows.where((r) => r.data['name'] == 'profile_id').firstOrNull;
    if (profileRow == null) return false; // column also missing
    final pk = profileRow.data['pk'] as int? ?? 0;
    return pk == 0;
  }

  /// Recreate [fix.name] with the correct composite PK. Order:
  ///   1. Begin transaction
  ///   2. Rename old → <name>_old_pk
  ///   3. CREATE new table with the right schema
  ///   4. INSERT INTO new SELECT cols FROM <name>_old_pk
  ///   5. DROP <name>_old_pk
  ///   6. Commit
  /// All inside one `transaction { … }` block so a crash mid-step
  /// rolls back rather than leaving the table half-renamed.
  Future<void> _recreateTableWithPk(_PkFix fix) async {
    await transaction(() async {
      final tmp = '${fix.name}_old_pk';
      await customStatement('ALTER TABLE ${fix.name} RENAME TO $tmp');
      await customStatement(fix.recreateSql);
      final cols = fix.columns.join(', ');
      await customStatement(
        'INSERT INTO ${fix.name} ($cols) SELECT $cols FROM $tmp',
      );
      await customStatement('DROP TABLE $tmp');
    });
  }
}

/// Helper record for [AppDatabase._fixCompositePrimaryKeys]. Holds
/// the SQL needed to rebuild one table with the correct composite
/// primary key + the column list used for the data copy.
class _PkFix {
  final String name;
  final String recreateSql;
  final List<String> columns;

  const _PkFix({
    required this.name,
    required this.recreateSql,
    required this.columns,
  });
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'lifeostv');
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  return AppDatabase();
}
