import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/services/backup_service.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase root;
  late AppDatabase a;
  late AppDatabase b;
  late AuthRepositoryImpl auth;
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = AppDatabase.forTesting(NativeDatabase.memory());
    for (final id in [1, 2]) {
      await root
          .into(root.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              name: 'Account $id',
              type: 'xtream',
              url: 'https://account$id.invalid',
              username: const Value('test'),
              password: const Value('synthetic'),
              isActive: Value(id == 1),
            ),
          );
    }
    a = root.forAccount(1);
    b = root.forAccount(2);
    auth = AuthRepositoryImpl(root, XtreamApiService(Dio()));
  });
  tearDown(() => root.close());

  Future<void> seed(AppDatabase db, String title) async {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'films',
            name: '$title category',
            type: 'movie',
          ),
        );
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            streamId: 42,
            name: title,
            type: 'movie',
            categoryId: 'films',
          ),
        );
  }

  test(
    'A-B-A preserves identical provider IDs and every profile history',
    () async {
      await root
          .into(root.profiles)
          .insert(ProfilesCompanion.insert(id: const Value(7), name: 'Second'));
      await seed(a, 'A title');
      await seed(b, 'B title');
      for (final db in [a, b]) {
        for (final pid in [1, 7]) {
          await FavoritesRepository(
            db,
            () => pid,
          ).addFavorite(42, 'movie', 'Account ${db.accountScope}', null);
          await PlayerRepository(
            db,
            () => pid,
          ).saveProgress(42, 'movie', db.accountScope! * pid * 1000, 100000);
        }
      }
      await auth.setActiveAccount(2);
      expect((await b.select(b.channels).getSingle()).name, 'B title');
      expect(
        (await PlayerRepository(b, () => 7).getProgress(42, 'movie'))?.position,
        14000,
      );
      await auth.setActiveAccount(1);
      expect((await a.select(a.channels).getSingle()).name, 'A title');
      expect(
        (await PlayerRepository(a, () => 7).getProgress(42, 'movie'))?.position,
        7000,
      );
      expect(await root.select(root.favorites).get(), hasLength(4));
      expect(await root.select(root.playbackProgress).get(), hasLength(4));
    },
  );

  test(
    'updates, deletes, upserts and batch writes stay inside their account',
    () async {
      await seed(a, 'A');
      await seed(b, 'B');
      await a
          .into(a.channels)
          .insertOnConflictUpdate(
            ChannelsCompanion.insert(
              streamId: 42,
              name: 'A updated',
              type: 'movie',
              categoryId: 'films',
            ),
          );
      await a.accountBatch((batch) {
        batch.update(
          a.channels,
          const ChannelsCompanion(name: Value('A batch')),
        );
        batch.insert(
          a.favorites,
          FavoritesCompanion.insert(
            streamId: 42,
            streamType: 'movie',
            name: 'A favorite',
          ),
        );
      });
      expect((await a.select(a.channels).getSingle()).name, 'A batch');
      expect((await b.select(b.channels).getSingle()).name, 'B');
      final count = b.channels.streamId.count();
      expect(
        (await (b.selectOnly(
          b.channels,
        )..addColumns([count])).getSingle()).read(count),
        1,
      );
      await a.delete(a.channels).go();
      expect(await a.select(a.channels).get(), isEmpty);
      expect(await b.select(b.channels).get(), hasLength(1));
      expect(await b.select(b.favorites).get(), isEmpty);
      final inserted = await a.select(a.favorites).getSingle();
      expect(inserted.accountId, 1);
    },
  );

  test(
    'JOIN cannot attach another account category, history or enrichment',
    () async {
      await seed(a, 'A');
      await seed(b, 'B');
      await a
          .into(a.contentEnrichment)
          .insert(
            ContentEnrichmentCompanion.insert(
              streamId: 42,
              type: 'movie',
              genres: const Value('A genre'),
            ),
          );
      await b
          .into(b.contentEnrichment)
          .insert(
            ContentEnrichmentCompanion.insert(
              streamId: 42,
              type: 'movie',
              genres: const Value('B genre'),
            ),
          );
      final repo = ContentRepository(
        a,
        SyncService(a, XtreamApiService(Dio())),
        () => 1,
      );
      final rows = await repo.watchAllChannelsByType('movie').first;
      expect(rows, hasLength(1));
      expect(rows.single.genre, 'A genre');
      await PlayerRepository(
        b,
        () => 1,
      ).saveProgress(42, 'movie', 10000, 100000);
      expect(await repo.tasteSignalsFromHistory(), isEmpty);
      await repo.toggleCategoryHidden('films', 'movie', true);
      expect((await a.select(a.categoryPrefs).getSingle()).isHidden, isTrue);
      expect(await b.select(b.categoryPrefs).get(), isEmpty);
      expect((await b.select(b.categories).getSingle()).isHidden, isFalse);
    },
  );

  test('bound query streams never jump to the newly active account', () async {
    await seed(a, 'A');
    await seed(b, 'B');
    final stream = a.select(a.channels).watch();
    final events = <List<Channel>>[];
    final ready = Completer<void>();
    final subscription = stream.listen((rows) {
      events.add(rows);
      if (!ready.isCompleted) ready.complete();
    });
    addTearDown(subscription.cancel);
    await ready.future;
    await auth.setActiveAccount(2);
    await b
        .update(b.channels)
        .write(const ChannelsCompanion(name: Value('B changed')));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      events.every(
        (rows) => rows.every((r) => r.accountId == 1 && r.name == 'A'),
      ),
      isTrue,
    );
  });

  test(
    'reactive provider replaces its bound handle after activation',
    () async {
      final container = ProviderContainer(
        overrides: [rootDatabaseProvider.overrideWithValue(root)],
      );
      addTearDown(container.dispose);
      final keepAlive = container.listen(databaseAccountIdProvider, (_, _) {});
      addTearDown(keepAlive.close);
      await container.read(databaseAccountIdProvider.future);
      final old = container.read(appDatabaseProvider);
      expect(old.accountScope, 1);
      final ready = Completer<void>();
      final sub = container.listen(databaseAccountIdProvider, (_, next) {
        if (next.value == 2 && !ready.isCompleted) ready.complete();
      });
      addTearDown(sub.close);
      await auth.setActiveAccount(2);
      await ready.future;
      expect(container.read(appDatabaseProvider).accountScope, 2);
      expect(old.accountScope, 1);
    },
  );

  test('delayed A sync finishing after B activation only updates A', () async {
    final api = _DelayedApi();
    final account = await (root.select(
      root.accounts,
    )..where((t) => t.id.equals(1))).getSingle();
    final sync = SyncService(root, api).syncAll(account);
    await api.started.future;
    await auth.setActiveAccount(2);
    await seed(b, 'B keep');
    api.release.complete();
    await sync;
    expect((await a.select(a.channels).getSingle()).name, 'A fetched');
    expect((await b.select(b.channels).getSingle()).name, 'B keep');
  });

  test('tier timestamps are shared per account, not across accounts', () async {
    final prefs = await SharedPreferences.getInstance();
    final one = SyncMetadata(prefs, accountId: 1);
    final same = SyncMetadata(prefs, accountId: 1);
    final other = SyncMetadata(prefs, accountId: 2);
    await one.markTierSynced(3);
    expect(same.isTierDue(3), isFalse);
    expect(other.isTierDue(3), isTrue);
  });

  test(
    'backup v3 round trip keeps the same favorite in both accounts',
    () async {
      await FavoritesRepository(a, () => 1).addFavorite(42, 'movie', 'A', null);
      await FavoritesRepository(b, () => 1).addFavorite(42, 'movie', 'B', null);
      final json = await BackupService(
        a,
      ).exportToJson(); // Scoped caller must export all accounts.
      expect(jsonDecode(json)['version'], 4);
      await BackupService(root).importFromJson(json);
      expect((await a.select(a.favorites).getSingle()).name, 'A');
      expect((await b.select(b.favorites).getSingle()).name, 'B');
    },
  );

  test(
    'v2 backup assigns previously unscoped rows to its active account',
    () async {
      await FavoritesRepository(
        a,
        () => 1,
      ).addFavorite(42, 'movie', 'Old', null);
      final payload =
          jsonDecode(await BackupService(root).exportToJson())
              as Map<String, dynamic>;
      payload['version'] = 2;
      for (final value in payload.values) {
        if (value is List) {
          for (final row in value) {
            if (row is Map) row.remove('accountId');
          }
        }
      }
      await BackupService(root).importFromJson(jsonEncode(payload));
      expect((await a.select(a.favorites).getSingle()).name, 'Old');
      expect(await b.select(b.favorites).get(), isEmpty);
    },
  );

  test(
    'deleting A removes only A and rejects delayed writes from its handle',
    () async {
      await seed(a, 'A');
      await seed(b, 'B');
      await FavoritesRepository(a, () => 1).addFavorite(42, 'movie', 'A', null);
      await FavoritesRepository(b, () => 1).addFavorite(42, 'movie', 'B', null);
      await auth.deleteAccount(1);
      expect(await a.select(a.channels).get(), isEmpty);
      expect((await b.select(b.channels).getSingle()).name, 'B');
      expect((await b.select(b.favorites).getSingle()).name, 'B');
      expect((await auth.getCurrentAccount())?.id, 2);
      await expectLater(
        () => FavoritesRepository(
          a,
          () => 1,
        ).addFavorite(43, 'movie', 'Late', null),
        throwsStateError,
      );
    },
  );

  test(
    'restore revokes old handles including already constructed deletes',
    () async {
      await FavoritesRepository(
        a,
        () => 1,
      ).addFavorite(42, 'movie', 'Saved', null);
      final pendingDelete = a.delete(a.favorites);
      final backup = await BackupService(root).exportToJson();
      await BackupService(root).importFromJson(backup);
      await expectLater(() => pendingDelete.go(), throwsStateError);
      await expectLater(
        () => FavoritesRepository(
          a,
          () => 1,
        ).addFavorite(43, 'movie', 'Late', null),
        throwsStateError,
      );
      final fresh = root.forAccount(1);
      expect(identical(a, fresh), isFalse);
      await FavoritesRepository(
        fresh,
        () => 1,
      ).addFavorite(44, 'movie', 'New', null);
      expect((await fresh.select(fresh.favorites).get()).map((r) => r.name), [
        'Saved',
        'New',
      ]);
      await expectLater(() => fresh.batch((_) {}), throwsStateError);
    },
  );

  test(
    'restore refreshes providers even when the active account ID is unchanged',
    () async {
      final container = ProviderContainer(
        overrides: [rootDatabaseProvider.overrideWithValue(root)],
      );
      addTearDown(container.dispose);
      final listener = container.listen(appDatabaseProvider, (_, _) {});
      addTearDown(listener.close);
      await container.read(databaseAccountIdProvider.future);
      await container.read(databaseEpochProvider.future);
      final old = container.read(appDatabaseProvider);
      final renewed = Completer<AppDatabase>();
      final change = container.listen(appDatabaseProvider, (_, next) {
        if (next.accountScope == 1 &&
            !identical(next, old) &&
            !renewed.isCompleted) {
          renewed.complete(next);
        }
      });
      addTearDown(change.close);
      await BackupService(
        root,
      ).importFromJson(await BackupService(root).exportToJson());
      final fresh = await renewed.future.timeout(const Duration(seconds: 2));
      expect(fresh.accountScope, 1);
      expect(() => old.forAccount(1), throwsStateError);
      await FavoritesRepository(
        fresh,
        () => 1,
      ).addFavorite(42, 'movie', 'Fresh', null);
    },
  );

  test('a paused batch cannot commit after restore', () async {
    final staged = Completer<void>();
    final release = Completer<void>();
    final batch = a.accountBatch((b) async {
      b.insert(
        a.favorites,
        FavoritesCompanion.insert(
          streamId: 99,
          streamType: 'movie',
          name: 'Late',
        ),
      );
      staged.complete();
      await release.future;
    });
    final rejected = expectLater(batch, throwsStateError);
    await staged.future;
    await BackupService(
      root,
    ).importFromJson(await BackupService(root).exportToJson());
    release.complete();
    await rejected;
    expect(await root.select(root.favorites).get(), isEmpty);
  });

  test(
    'backup with unknown account is rejected before modifying data',
    () async {
      await FavoritesRepository(
        a,
        () => 1,
      ).addFavorite(42, 'movie', 'Keep', null);
      final payload =
          jsonDecode(await BackupService(root).exportToJson())
              as Map<String, dynamic>;
      payload['favorites'][0]['accountId'] = 999;
      await expectLater(
        BackupService(root).importFromJson(jsonEncode(payload)),
        throwsFormatException,
      );
      expect((await a.select(a.favorites).getSingle()).name, 'Keep');
    },
  );

  test('catalogue and EPG plans use account-leading indexes', () async {
    for (final query in [
      'SELECT * FROM channels WHERE account_id=1 AND type=\'movie\' AND category_id=\'films\'',
      'SELECT * FROM programs WHERE account_id=1 AND channel_id=42 ORDER BY start',
    ]) {
      final plan = await root.customSelect('EXPLAIN QUERY PLAN $query').get();
      expect(
        plan.map((r) => r.read<String>('detail')).join(' '),
        contains('account_'),
      );
    }
  });

  for (final identity in ['matching', 'unknown', 'missing']) {
    test('LAN import $identity account identity while B is active', () async {
      await auth.setActiveAccount(2);
      await FavoritesRepository(
        b,
        () => 1,
      ).addFavorite(42, 'movie', 'B keep', null);
      final payload = <String, dynamic>{
        if (identity != 'missing')
          'contentAccountKey': jsonEncode([
            'xtream',
            identity == 'matching'
                ? 'https://account1.invalid'
                : 'https://unknown.invalid',
            'test',
          ]),
        'favorites': [
          {
            'streamId': 42,
            'streamType': 'movie',
            'name': 'A imported',
            'addedAt': 1000,
            'profileId': 1,
          },
        ],
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await subscription.cancel();
      });
      final prefs = await SharedPreferences.getInstance();
      final importing = HttpOverrides.runWithHttpOverrides(
        () => LanSyncService(b, prefs).pullAndApply(
          peer: SyncPeer(
            name: 'Synthetic',
            host: '127.0.0.1',
            port: server.port,
          ),
          pin: '123456',
          cats: {SyncCategory.favorites},
          activeProfileId: 1,
        ),
        _LocalHttp(),
      );
      if (identity == 'matching') {
        await importing;
        expect((await a.select(a.favorites).getSingle()).name, 'A imported');
      } else {
        await expectLater(importing, throwsFormatException);
        expect(await a.select(a.favorites).get(), isEmpty);
      }
      expect((await b.select(b.favorites).getSingle()).name, 'B keep');
    });
  }

  for (final version in [23, 24, 25]) {
    test(
      'real legacy v$version tables migrate without losing user/catalogue rows',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'iptv-account-migrate-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/legacy.sqlite');
        final old = AppDatabase.forTesting(NativeDatabase(file));
        await old
            .into(old.accounts)
            .insert(
              AccountsCompanion.insert(
                id: const Value(9),
                name: 'Legacy owner',
                type: 'm3u',
                url: 'synthetic',
                isActive: const Value(true),
              ),
            );
        await seed(old.forAccount(9), 'Preserved title');
        await FavoritesRepository(
          old.forAccount(9),
          () => 1,
        ).addFavorite(42, 'movie', 'Preserved favorite', null);
        await old
            .into(old.profiles)
            .insert(
              ProfilesCompanion.insert(
                id: const Value(7),
                name: 'Other profile',
              ),
            );
        await FavoritesRepository(
          old.forAccount(9),
          () => 7,
        ).addFavorite(42, 'movie', 'Profile seven', null);
        // Strip the new account column and keys to construct an actual pre-v26
        // schema. Merely changing user_version would not test the data copy.
        for (final table in old.allTables.where(
          (t) => t.columnsByName.containsKey('account_id'),
        )) {
          final name = table.actualTableName;
          final row = await old
              .customSelect(
                "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
                variables: [Variable(name)],
              )
              .getSingle();
          var sql = row.read<String>('sql');
          sql = sql.replaceFirst('"$name"', '"legacy_$name"');
          sql = sql.replaceAll(
            RegExp(r'"account_id" INTEGER NOT NULL DEFAULT 0,?\s*'),
            '',
          );
          sql = sql.replaceAll(RegExp(r',\s*"account_id"'), '');
          sql = sql.replaceAll(', )', ')');
          expect(sql, isNot(contains('account_id')), reason: sql);
          final columns = table.$columns
              .where((c) => c.$name != 'account_id')
              .map((c) => '"${c.$name}"')
              .join(',');
          await old.customStatement(sql);
          await old.customStatement(
            'INSERT INTO "legacy_$name" ($columns) SELECT $columns FROM "$name"',
          );
          await old.customStatement('DROP TABLE "$name"');
          await old.customStatement(
            'ALTER TABLE "legacy_$name" RENAME TO "$name"',
          );
        }
        if (version == 23) {
          await old.customStatement(
            'ALTER TABLE channels DROP COLUMN container_extension',
          );
        }
        await old.customStatement('PRAGMA user_version = $version');
        await old.close();
        final migrated = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(migrated.close);
        final saved = migrated.forAccount(9);
        expect(
          (await saved.select(saved.channels).getSingle()).name,
          'Preserved title',
        );
        expect(
          (await saved.select(saved.favorites).get())
              .map((f) => f.profileId)
              .toSet(),
          {1, 7},
        );
        expect(
          await migrated.forAccount(10).select(migrated.favorites).get(),
          isEmpty,
        );
        for (final table in migrated.allTables.where(
          (t) => t.columnsByName.containsKey('account_id'),
        )) {
          final columns = await migrated
              .customSelect('PRAGMA table_info("${table.actualTableName}")')
              .get();
          final pk = columns
              .where((r) => r.read<int>('pk') > 0)
              .map((r) => r.read<String>('name'))
              .toSet();
          expect(
            pk,
            table.$primaryKey.map((c) => c.$name).toSet(),
            reason: table.actualTableName,
          );
        }
      },
    );
  }
}

class _DelayedApi extends XtreamApiService {
  final started = Completer<void>();
  final release = Completer<void>();
  _DelayedApi() : super(Dio());
  @override
  Future<List<dynamic>> getCategories(
    String url,
    String username,
    String password,
    String action,
  ) async => [
    {'category_id': 'films', 'category_name': 'A category'},
  ];
  @override
  Future<List<dynamic>> getStreams(
    String url,
    String username,
    String password,
    String action, {
    String? categoryId,
  }) async {
    if (action != 'get_vod_streams') return [];
    started.complete();
    await release.future;
    return [
      {'stream_id': 42, 'name': 'A fetched', 'category_id': 'films'},
    ];
  }
}

class _LocalHttp extends HttpOverrides {}
