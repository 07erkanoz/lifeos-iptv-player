import 'dart:async';
import 'dart:convert';
import 'package:lifeostv/data/services/backup_service.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/services/sync_budget.dart';
import 'package:lifeostv/data/services/sync_coordinator.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase root;
  late AppDatabase db;
  late _Api api;
  late Account account;
  late SyncMetadata meta;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = AppDatabase.forTesting(NativeDatabase.memory());
    await root
        .into(root.accounts)
        .insert(
          AccountsCompanion.insert(
            id: const Value(1),
            name: 'Test',
            type: 'xtream',
            url: 'https://synthetic.invalid',
            username: const Value('test'),
            password: const Value('secret'),
            isActive: const Value(true),
          ),
        );
    account = await root.select(root.accounts).getSingle();
    db = root.forAccount(1);
    api = _Api();
    meta = SyncMetadata(await SharedPreferences.getInstance(), accountId: 1);
  });
  tearDown(() => root.close());

  Future<void> oldMovie() => db
      .into(db.channels)
      .insert(
        ChannelsCompanion.insert(
          streamId: 42,
          name: 'Keep',
          type: 'movie',
          categoryId: '1',
          plot: const Value('Rich plot'),
          containerExtension: const Value('mkv'),
        ),
      )
      .then((_) {});

  test(
    'M3U registry, metadata and history survive backup and absent media types prune',
    () async {
      final m3u = account.copyWith(type: 'm3u');
      await root.update(root.accounts).replace(m3u);
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'Live',
              name: 'Live',
              type: 'live',
              isHidden: const Value(true),
            ),
          );
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              streamId: 7,
              name: 'Old',
              type: 'live',
              categoryId: 'Live',
              streamUrl: const Value('https://example.invalid/live.ts'),
              plot: const Value('Keep details'),
            ),
          );
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              streamId: 7,
              streamType: 'live',
              name: 'Old',
            ),
          );
      await oldMovie();
      final parsed = parseM3URaw(
        '#EXTM3U\n#EXTINF:-1 group-title="Live" tvg-id="live",New\nhttps://example.invalid/live.ts',
      );
      final service = SyncService(db, api, loadM3u: (_) async => parsed);
      await service.syncAll(m3u);
      final channel = await db.select(db.channels).getSingle();
      expect(channel.streamId, 7);
      expect(channel.plot, 'Keep details');
      expect((await db.select(db.categories).getSingle()).isHidden, isTrue);
      final backup = BackupService(root);
      final json = await backup.exportToJson();
      expect(jsonDecode(json)['m3uIdentities'], hasLength(1));
      await backup.importFromJson(json);
      db = root.forAccount(1);
      await SyncService(db, api, loadM3u: (_) async => parsed).syncAll(m3u);
      expect((await db.select(db.channels).getSingle()).streamId, 7);
      expect((await db.select(db.favorites).getSingle()).streamId, 7);
    },
  );

  test(
    '100k M3U sync has no SQLite variable overflow and prunes stale chunks',
    () async {
      var entries = List.generate(
        100000,
        (i) =>
            M3UEntry(name: 'Channel $i', url: 'https://example.invalid/$i.ts'),
      );
      final service = SyncService(
        db,
        api,
        loadM3u: (_) async => M3URawResult(entries: entries),
      );
      final m3u = account.copyWith(type: 'm3u');
      await service.syncAll(m3u);
      expect(await db.select(db.channels).get(), hasLength(100000));
      entries = entries.take(3).toList();
      await service.syncAll(m3u);
      expect(await db.select(db.channels).get(), hasLength(3));
      expect(await db.select(db.m3uIdentities).get(), hasLength(100000));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'EPG replacement failure restores old programs; invalid dates never erase them',
    () async {
      await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              channelId: 42,
              title: 'Old guide',
              start: DateTime(2026),
              stop: DateTime(2027),
            ),
          );
      api.epg = [
        {'title': 'New', 'start_timestamp': '100', 'stop_timestamp': '200'},
        {'title': 'Abort', 'start_timestamp': '200', 'stop_timestamp': '300'},
      ];
      await root.customStatement(
        "CREATE TRIGGER abort_epg BEFORE INSERT ON programs WHEN NEW.title='Abort' BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
      );
      await SyncService(db, api).syncEpg(account, '42');
      expect((await db.select(db.programs).getSingle()).title, 'Old guide');
      api.epg = [
        {'title': 'Invalid', 'start_timestamp': '300', 'stop_timestamp': '100'},
      ];
      await SyncService(db, api).syncEpg(account, '42');
      expect((await db.select(db.programs).getSingle()).title, 'Old guide');
    },
  );

  for (final withProgress in [true, false]) {
    test(
      'network failure is not done or fresh (progress=$withProgress)',
      () async {
        await oldMovie();
        api.failMovies = true;
        final progress = <SyncProgress>[];
        final service = SyncService(db, api);
        await expectLater(
          withProgress
              ? service.syncAllWithProgress(account, progress.add)
              : service.runTieredSync(account, meta),
          throwsA(isA<SyncFailure>()),
        );
        expect(progress.any((p) => p.isDone), isFalse);
        expect(meta.isTierDue(3), isTrue);
        expect((await db.select(db.channels).getSingle()).name, 'Keep');
        expect(api.actions.contains('get_series'), isFalse);
      },
    );
  }

  test(
    'login, manual and automatic full refresh share one actual job',
    () async {
      api.release = Completer<void>();
      final service1 = SyncService(db, api);
      final service2 = SyncService(root, api);
      final first = <SyncProgress>[], second = <SyncProgress>[];
      final login = service1.syncAllWithProgress(account, first.add);
      await api.started.future;
      final automatic = service2.runTieredSync(account, meta);
      final manual = service2.syncAllWithProgress(account, second.add);
      var settled = false;
      final watching = manual.then((_) => settled = true);
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      api.release!.complete();
      await Future.wait([login, automatic, manual, watching]);
      expect(api.actions.length, 6);
      expect(first.last.isDone, isTrue);
      expect(second.last.isDone, isTrue);
      expect(meta.isTierDue(3), isFalse);
      expect(
        meta.isTierDue(4),
        isTrue,
        reason: 'Full catalogue does not check episode counts',
      );
    },
  );

  test(
    'all waiters receive failure and a later explicit retry works',
    () async {
      api.release = Completer<void>();
      api.failMovies = true;
      final service = SyncService(db, api);
      final first = expectLater(
        service.syncAll(account),
        throwsA(isA<SyncFailure>()),
      );
      await api.started.future;
      final second = expectLater(
        service.syncAll(account),
        throwsA(isA<SyncFailure>()),
      );
      api.release!.complete();
      await Future.wait([first, second]);
      expect(api.actions.length, 5);
      api.failMovies = false;
      api.release = null;
      await service.syncAll(account);
      expect(meta.isTierDue(3), isFalse);
    },
  );

  test(
    'full update preserves enriched fields and category visibility',
    () async {
      await oldMovie();
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: '1',
              name: 'Hidden',
              type: 'movie',
              isHidden: const Value(true),
            ),
          );
      await SyncService(db, api).syncAll(account);
      final movie = await db.select(db.channels).getSingle();
      expect(movie.name, 'Fetched');
      expect(movie.plot, 'Rich plot');
      expect(movie.containerExtension, 'mkv');
      final category = await (db.select(
        db.categories,
      )..where((c) => c.type.equals('movie'))).getSingle();
      expect(category.isHidden, isTrue);
    },
  );

  test('malformed row cannot partially rewrite or prune a type', () async {
    await oldMovie();
    api.rows = [
      {'stream_id': 42, 'name': 'Overwritten'},
      {'name': 'Broken'},
    ];
    await expectLater(
      SyncService(db, api).syncAll(account),
      throwsA(isA<SyncFailure>()),
    );
    expect((await db.select(db.channels).getSingle()).name, 'Keep');
    expect(meta.isTierDue(3), isTrue);
  });

  test('empty replacement of a previously populated type stays due', () async {
    await oldMovie();
    api.rows = [];
    await expectLater(
      SyncService(db, api).syncAll(account),
      throwsA(isA<SyncFailure>()),
    );
    expect((await db.select(db.channels).getSingle()).name, 'Keep');
    expect(meta.isTierDue(3), isTrue);
  });

  test('a failure in the second SQL chunk rolls back the first chunk', () async {
    await oldMovie();
    api.rows = List.generate(501, (i) => {'stream_id': i + 1, 'name': 'New'});
    await root.customStatement(
      "CREATE TRIGGER abort_sync BEFORE INSERT ON channels WHEN NEW.stream_id=501 BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
    );
    await expectLater(
      SyncService(db, api).syncAll(account),
      throwsA(isA<SyncFailure>()),
    );
    expect((await db.select(db.channels).getSingle()).name, 'Keep');
    expect(meta.isTierDue(3), isTrue);
  });

  for (final cancel in [true, false]) {
    test(
      'late response after ${cancel ? 'cancellation' : 'deadline'} cannot write',
      () async {
        await oldMovie();
        api.release = Completer<void>();
        final coordinator = SyncCoordinator<SyncProgress>(
          timeout: const Duration(milliseconds: 150),
        );
        final service = SyncService(db, api, coordinator: coordinator);
        final progress = <SyncProgress>[];
        final rejected = expectLater(
          service.syncAllWithProgress(account, progress.add),
          throwsA(isA<SyncFailure>()),
        );
        await api.started.future;
        if (cancel) service.cancelSync(1);
        await rejected;
        api.release!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect((await db.select(db.channels).getSingle()).name, 'Keep');
        expect(progress.any((p) => p.isDone), isFalse);
        expect(meta.isTierDue(3), isTrue);
      },
    );
  }

  test('M3U login and manual sync share one load and mark only tier 3', () async {
    final release = Completer<M3URawResult>();
    var loads = 0;
    final service = SyncService(
      root,
      api,
      loadM3u: (_) {
        loads++;
        return release.future;
      },
    );
    final m3u = account.copyWith(type: 'm3u');
    final a = service.syncAll(m3u);
    final b = service.syncAllWithProgress(m3u, (_) {});
    release.complete(
      parseM3URaw(
        '#EXTM3U\n#EXTINF:-1 group-title="Live",Test\nhttps://synthetic.invalid/live.ts',
      ),
    );
    await Future.wait([a, b]);
    expect(loads, 1);
    expect(await db.select(db.channels).get(), hasLength(1));
    expect(meta.isTierDue(3), isFalse);
    expect(meta.isTierDue(1), isTrue);
  });

  test('M3U SQL failure rolls back categories and channels together', () async {
    await oldMovie();
    await root.customStatement(
      "CREATE TRIGGER abort_m3u BEFORE INSERT ON channels BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
    );
    final service = SyncService(
      db,
      api,
      loadM3u: (_) async => parseM3URaw(
        '#EXTM3U\n#EXTINF:-1 group-title="New",Test\nhttps://synthetic.invalid/live.ts',
      ),
    );
    await expectLater(
      service.syncAll(account.copyWith(type: 'm3u')),
      throwsA(isA<SyncFailure>()),
    );
    expect(await db.select(db.categories).get(), isEmpty);
    expect(await db.select(db.m3uIdentities).get(), isEmpty);
    expect((await db.select(db.channels).getSingle()).name, 'Keep');
    expect(meta.isTierDue(3), isTrue);
  });

  test('late M3U parse after cancellation cannot replace data', () async {
    await oldMovie();
    final release = Completer<M3URawResult>();
    final service = SyncService(db, api, loadM3u: (_) => release.future);
    final rejected = expectLater(
      service.syncAll(account.copyWith(type: 'm3u')),
      throwsA(isA<SyncFailure>()),
    );
    service.cancelSync(1);
    await rejected;
    release.complete(
      parseM3URaw(
        '#EXTM3U\n#EXTINF:-1,Test\nhttps://synthetic.invalid/live.ts',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await db.select(db.channels).getSingle()).name, 'Keep');
    expect(meta.isTierDue(3), isTrue);
  });

  test('failed episode lookup leaves tier 4 due', () async {
    for (final tier in [1, 2, 3]) {
      await meta.markTierSynced(tier);
    }
    await db
        .into(db.playbackProgress)
        .insert(
          PlaybackProgressCompanion.insert(
            streamId: 42,
            type: 'series',
            position: 10,
            duration: 100,
          ),
        );
    await expectLater(
      SyncService(db, api).runTieredSync(account, meta),
      throwsA(isA<SyncFailure>()),
    );
    expect(meta.isTierDue(4), isTrue);
  });

  test(
    'episode tracking is independent for two profiles watching same series',
    () async {
      for (final tier in [1, 2, 3]) {
        await meta.markTierSynced(tier);
      }
      api.series = {
        'episodes': {
          '1': [{}, {}, {}],
        },
      };
      for (final pid in [1, 7]) {
        await db
            .into(db.playbackProgress)
            .insert(
              PlaybackProgressCompanion.insert(
                streamId: 42,
                type: 'series',
                position: 10,
                duration: 100,
                profileId: Value(pid),
              ),
            );
      }
      await SyncService(db, api).runTieredSync(account, meta);
      expect(
        (await db.select(db.seriesTracking).get())
            .map((r) => r.profileId)
            .toSet(),
        {1, 7},
      );
      expect(api.seriesCalls, 1);
      expect(meta.isTierDue(4), isFalse);
    },
  );
}

class _Api extends XtreamApiService {
  _Api() : super(Dio());
  List<dynamic> epg = [];
  @override
  Future<Map<String, dynamic>> getEpg(
    String url,
    String username,
    String password,
    String streamId, {
    int? limit,
  }) async => {'epg_listings': epg};
  final actions = <String>[];
  final started = Completer<void>();
  Completer<void>? release;
  bool failMovies = false;
  List<dynamic> rows = [
    {'stream_id': 42, 'name': 'Fetched', 'category_id': '1'},
  ];
  Map<String, dynamic>? series;
  int seriesCalls = 0;
  @override
  Future<List<dynamic>> getCategories(
    String url,
    String username,
    String password,
    String action,
  ) async {
    actions.add(action);
    return [
      {'category_id': '1', 'category_name': 'Category'},
    ];
  }

  @override
  Future<List<dynamic>> getStreams(
    String url,
    String username,
    String password,
    String action, {
    String? categoryId,
  }) async {
    actions.add(action);
    if (action != 'get_vod_streams') return [];
    if (!started.isCompleted) started.complete();
    await release?.future;
    if (failMovies) {
      throw StateError('secret provider detail must never reach the UI');
    }
    return rows;
  }

  @override
  Future<Map<String, dynamic>?> getSeriesInfo(
    String url,
    String username,
    String password,
    int seriesId,
  ) async {
    seriesCalls++;
    return series;
  }
}
