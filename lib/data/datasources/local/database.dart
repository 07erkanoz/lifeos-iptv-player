import 'package:lifeostv/data/services/sync_budget.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Provider, StreamProvider;
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'database.g.dart';
part 'account_scope.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Profiles,
    Categories,
    Channels,
    Programs,
    PlaybackProgress,
    Favorites,
    Watchlist,
    SeriesTracking,
    IntroMarkers,
    PlotAiCache,
    PersonalizedPicksCache,
    AiCallLogs,
    AiFeedback,
    SearchHistory,
    AiSimilarCache,
    ContentEnrichment,
    ContentEmbeddings,
    SyncTombstones,
    CategoryPrefs,
    BackupRestoreJournal,
    M3uIdentities,
  ],
)
class AppDatabase extends _$AppDatabase with AccountQueries {
  final AppDatabase? _root;
  final int _boundEpoch;
  int _scopeEpoch = 0;
  bool _restoring = false;
  final Set<int> _deletedAccounts = {};
  final _scopeChanges = StreamController<int>.broadcast();

  @override
  void checkAccountWrite() {
    SyncBudget.current?.check();
    if (accountScope != null &&
        (root._restoring ||
            _boundEpoch != root._scopeEpoch ||
            root._deletedAccounts.contains(accountScope))) {
      throw StateError('Account operation is no longer current');
    }
  }

  void beginRestore() {
    root._restoring = true;
    root._scopeEpoch++;
    root._scopes.clear();
    root._deletedAccounts.clear();
  }

  void finishRestore() {
    root._restoring = false;
    root._scopeChanges.add(root._scopeEpoch);
  }

  void blockAccount(int id) => root._deletedAccounts.add(id);
  void unblockAccount(int id) => root._deletedAccounts.remove(id);

  @override
  final int? accountScope;
  final Map<int, AppDatabase> _scopes = {};
  AppDatabase get root => _root ?? this;
  @override
  AppDatabase get attachedDatabase => root;

  AppDatabase forAccount(int id) {
    // A revoked background job must not acquire a fresh handle after restore.
    checkAccountWrite();
    return root._scopes.putIfAbsent(id, () => AppDatabase._scoped(root, id));
  }

  AppDatabase._scoped(AppDatabase owner, this.accountScope)
    : _root = owner,
      _boundEpoch = owner._scopeEpoch,
      super(owner.connection);

  @override
  Future<void> close() async {
    if (_root != null) return;
    await _scopeChanges.close();
    await super.close();
  }

  AppDatabase()
    : _root = null,
      _boundEpoch = 0,
      accountScope = null,
      super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor)
    : _root = null,
      _boundEpoch = 0,
      accountScope = null,
      super(executor);

  @override
  int get schemaVersion => 30;

  @override
  MigrationStrategy get migration =>
      _root?.migration ??
      MigrationStrategy(
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
          if (from < 23) {
            // Precomputed normalised search haystack column. Additive +
            // nullable → safe simple addColumn (no PK change, cf. ONEMLI.md).
            // Rows are backfilled off the UI isolate by
            // ContentRepository.refreshSearchIndex() at startup / after sync.
            await m.addColumn(channels, channels.searchText);
          }
          if (from < 24) {
            // Nullable metadata only; catalogue keys and user progress are unchanged.
            // Probe first to support builds that applied the column before user_version.
            final columns = await customSelect(
              'PRAGMA table_info(channels)',
            ).get();
            if (!columns.any(
              (row) => row.data['name'] == 'container_extension',
            )) {
              await m.addColumn(channels, channels.containerExtension);
            }
          }
          final introColumns = await customSelect(
            'PRAGMA table_info(intro_markers)',
          ).get();
          if (from < 30 &&
              !introColumns.any((r) => r.data['name'] == 'episode_id')) {
            // Drift rebuilds the primary key while preserving existing markers.
            // The migration is covered by the v29→v30 data preservation test.
            await m.alterTable(
              // ignore: experimental_member_use
              TableMigration(
                introMarkers,
                newColumns: [
                  introMarkers.season,
                  introMarkers.episodeId,
                  introMarkers.source,
                  introMarkers.confidence,
                  introMarkers.isDeleted,
                ],
                columnTransformer: {
                  introMarkers.source: const Constant('legacy'),
                  introMarkers.confidence: const Constant(0.0),
                },
              ),
            );
          }
        },
        beforeOpen: (details) async {
          // Nullable, additive metadata; no primary key changes. Probe also
          // recovers off-fork builds with an already advanced user_version.
          final channelColumns = await customSelect(
            'PRAGMA table_info(channels)',
          ).get();
          if (!channelColumns.any(
            (row) => row.data['name'] == 'playback_headers',
          )) {
            await Migrator(this).addColumn(channels, channels.playbackHeaders);
          }
          if (!channelColumns.any(
            (row) => row.data['name'] == 'catchup_metadata',
          )) {
            await Migrator(this).addColumn(channels, channels.catchupMetadata);
          }
          // Additive table; idempotent for partially applied upgrades too.
          await Migrator(this).createTable(m3uIdentities);

          // Additive recovery table; safe for partially applied schema upgrades.
          await customStatement(
            'CREATE TABLE IF NOT EXISTS backup_restore_journal '
            '(id INTEGER NOT NULL PRIMARY KEY, preferences_json TEXT NOT NULL)',
          );
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
          await _migrateAccountScope(Migrator(this));

          // Derived search/vector data must not outlive its source metadata.
          // Runs after account migrations so every predicate includes account_id.
          await customStatement(
            '''CREATE TRIGGER IF NOT EXISTS channels_ai_invalidate
            AFTER UPDATE OF name, genre, year, plot, cast, director ON channels
            WHEN OLD.name IS NOT NEW.name OR OLD.genre IS NOT NEW.genre
              OR OLD.year IS NOT NEW.year OR OLD.plot IS NOT NEW.plot
              OR OLD.cast IS NOT NEW.cast OR OLD.director IS NOT NEW.director
            BEGIN
              DELETE FROM content_embeddings WHERE account_id = NEW.account_id
                AND stream_id = NEW.stream_id AND type = NEW.type;
              UPDATE channels SET search_text = NULL WHERE account_id = NEW.account_id
                AND stream_id = NEW.stream_id AND type = NEW.type;
            END''',
          );
          await customStatement(
            '''CREATE TRIGGER IF NOT EXISTS enrichment_ai_invalidate
            AFTER INSERT ON content_enrichment
            BEGIN
              DELETE FROM content_embeddings WHERE account_id = NEW.account_id
                AND stream_id = NEW.stream_id AND type = NEW.type;
            END''',
          );
          await customStatement(
            '''CREATE TRIGGER IF NOT EXISTS channels_ai_cleanup
            AFTER DELETE ON channels
            BEGIN
              DELETE FROM content_embeddings WHERE account_id = OLD.account_id
                AND stream_id = OLD.stream_id AND type = OLD.type;
              DELETE FROM content_enrichment WHERE account_id = OLD.account_id
                AND stream_id = OLD.stream_id AND type = OLD.type;
            END''',
          );

          // Belt-and-braces seed: if the user nuked their DB or this is
          // a fresh install on v18+, ensure profile 1 exists before any
          // FK-bound query fires. INSERT OR IGNORE — no-op when present.
          await customStatement(
            "INSERT OR IGNORE INTO profiles (id, name, avatar_key, "
            "is_kids, created_at) VALUES (1, 'Varsayılan', 'default', "
            "0, ${DateTime.now().millisecondsSinceEpoch ~/ 1000})",
          );

          // ── Hot-query indexes ─────────────────────────────────────────
          // Drift creates no secondary indexes by default, so every grid
          // load was a full channels-table scan (~15k rows). IF NOT EXISTS
          // → idempotent, no schema-version bump needed. Numeric expression
          // index on `added` (a TEXT unix-epoch) backs the newest-first
          // sorts.
          // Account-leading indexes keep catalogue scans local as accounts grow.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_account_category ON channels (account_id, type, category_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_account_added ON channels (account_id, type, CAST(added AS INTEGER) DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_categories_account_hidden ON categories (account_id, type, is_hidden)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_progress_account_profile ON playback_progress (account_id, profile_id, type, is_finished)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_favorites_account_profile ON favorites (account_id, profile_id, stream_type)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_programs_account_channel ON programs (account_id, channel_id, start)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_type_cat ON channels (type, category_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_channels_type_added ON channels (type, CAST(added AS INTEGER) DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_categories_type_hidden ON categories (type, is_hidden)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_progress_profile_type ON playback_progress (profile_id, type, is_finished)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_favorites_profile_type ON favorites (profile_id, stream_type)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_programs_channel_start ON programs (channel_id, start)',
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

  /// Probe-and-add helper. Reads `PRAGMA table_info(tableName)` —
  /// returns one row per column with the column's name in field 1.
  /// If `profile_id` is already there, no-op. Otherwise issue the
  /// ADD COLUMN statement with the same defaults the Drift schema
  /// declares (`INTEGER NOT NULL DEFAULT 1`).
  Future<void> _addProfileIdIfMissing(String tableName) async {
    final rows = await customSelect('PRAGMA table_info($tableName)').get();
    final hasIt = rows.any((r) => r.data['name'] == 'profile_id');
    if (hasIt) return;
    await customStatement(
      'ALTER TABLE $tableName ADD COLUMN profile_id INTEGER NOT NULL DEFAULT 1',
    );
  }

  /// TableMigration rebuilds composite keys and copies every existing column.
  /// The account that owned the legacy global catalogue owns its user data.
  Future<void> _migrateAccountScope(Migrator migrator) async {
    final active = await customSelect(
      'SELECT id FROM accounts WHERE is_active = 1 '
      'ORDER BY id DESC LIMIT 1',
    ).getSingleOrNull();
    final owner = active?.read<int>('id') ?? 0;
    await transaction(() async {
      for (final table in allTables) {
        final account = table.columnsByName['account_id'];
        if (account == null) continue;
        final columns = await customSelect(
          'PRAGMA table_info("${table.actualTableName}")',
        ).get();
        final names = columns.map((r) => r.read<String>('name')).toSet();
        final actualPk = columns
            .where((r) => r.read<int>('pk') > 0)
            .map((r) => r.read<String>('name'))
            .toSet();
        final expectedPk = table.$primaryKey.map((c) => c.$name).toSet();
        if (names.contains('account_id') &&
            actualPk.length == expectedPk.length &&
            actualPk.containsAll(expectedPk)) {
          continue;
        }
        // Drift migration API required for composite primary keys.
        await migrator.alterTable(
          // ignore: experimental_member_use
          TableMigration(
            table,
            newColumns: [if (!names.contains('account_id')) account],
            columnTransformer: {
              if (!names.contains('account_id')) account: Constant(owner),
            },
          ),
        );
      }
    });
  }
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'lifeostv');
}

/// Shared registry/backup connection. Normal content consumers use the
/// account-bound provider below, never this unfiltered connection.
final rootDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final databaseEpochProvider = StreamProvider<int>((ref) async* {
  final root = ref.watch(rootDatabaseProvider);
  yield root._scopeEpoch;
  yield* root._scopeChanges.stream;
});

final databaseAccountIdProvider = StreamProvider<int>((ref) {
  final root = ref.watch(rootDatabaseProvider);
  return (root.select(root.accounts)
        ..where((a) => a.isActive.equals(true))
        ..orderBy([(a) => OrderingTerm.desc(a.id)])
        ..limit(1))
      .watchSingleOrNull()
      .map((a) => a?.id ?? 0);
});

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final root = ref.watch(rootDatabaseProvider);
  ref.watch(databaseEpochProvider);
  return root.forAccount(ref.watch(databaseAccountIdProvider).value ?? 0);
}
