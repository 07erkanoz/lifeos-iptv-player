import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/backup_document.dart';
import 'package:lifeostv/data/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SharedPreferences prefs;
  late BackupService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = BackupService(db, preferences: prefs);
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> fixture() async {
    for (final id in [10, 20]) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              name: 'Account $id',
              type: 'xtream',
              url: 'https://example.invalid/$id',
              username: const Value('test'),
              password: const Value('synthetic'),
              isActive: Value(id == 20),
            ),
          );
    }
    for (final id in [7, 12]) {
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: Value(id),
              name: 'Profile $id',
              isKids: Value(id == 7),
              pin: const Value('1234'),
              avatarKey: const Value('cat'),
            ),
          );
    }
    for (final id in [1, 7, 12]) {
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              streamId: 42,
              streamType: 'movie',
              name: 'Same title',
              profileId: Value(id),
            ),
          );
      await db
          .into(db.watchlist)
          .insert(
            WatchlistCompanion.insert(
              streamId: 42,
              streamType: 'movie',
              name: 'Same title',
              profileId: Value(id),
            ),
          );
      await db
          .into(db.playbackProgress)
          .insert(
            PlaybackProgressCompanion.insert(
              streamId: 42,
              type: 'movie',
              position: id * 1000,
              duration: 90000,
              profileId: Value(id),
            ),
          );
      await db
          .into(db.seriesTracking)
          .insert(
            SeriesTrackingCompanion.insert(
              seriesId: 5,
              knownEpisodeCount: id,
              profileId: Value(id),
            ),
          );
      await db
          .into(db.aiFeedback)
          .insert(
            AiFeedbackCompanion.insert(
              streamId: 42,
              type: 'movie',
              action: 'dislike',
              profileId: Value(id),
            ),
          );
      await db
          .into(db.searchHistory)
          .insert(
            SearchHistoryCompanion.insert(
              query: 'same query',
              profileId: Value(id),
            ),
          );
      await db
          .into(db.syncTombstones)
          .insert(
            SyncTombstonesCompanion.insert(
              entity: 'favorite',
              streamId: 99,
              streamType: 'movie',
              profileId: Value(id),
            ),
          );
    }
    await db
        .into(db.categoryPrefs)
        .insert(
          CategoryPrefsCompanion.insert(
            categoryId: 'films',
            type: 'movie',
            isHidden: const Value(true),
          ),
        );
    await db
        .into(db.introMarkers)
        .insert(
          IntroMarkersCompanion.insert(
            seriesId: 5,
            introStartMs: 5000,
            introEndMs: 40000,
          ),
        );
    await prefs.setInt('default_account_id', 20);
    await prefs.setInt('active_profile_id', 7);
    await prefs.setString('epg_url_10', 'https://example.invalid/a.xml');
    await prefs.setString('epg_url_20', 'https://example.invalid/b.xml');
    await prefs.setString('app_language', 'tr');
    return jsonDecode(await service.exportToJson()) as Map<String, dynamic>;
  }

  test(
    'v2 round trip preserves two accounts and three independent profiles',
    () async {
      final payload = await fixture();
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      await target
          .into(target.accounts)
          .insert(
            AccountsCompanion.insert(
              id: const Value(80),
              name: 'Old account',
              type: 'm3u',
              url: 'old',
            ),
          );
      await target
          .into(target.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'old',
              name: 'Old category',
              type: 'movie',
            ),
          );
      await target
          .into(target.channels)
          .insert(
            ChannelsCompanion.insert(
              streamId: 42,
              name: 'Wrong account title',
              type: 'movie',
              categoryId: 'old',
            ),
          );
      await target
          .into(target.contentEnrichment)
          .insert(
            ContentEnrichmentCompanion.insert(
              streamId: 42,
              type: 'movie',
              genres: const Value('stale'),
            ),
          );
      await prefs.setString('epg_url_80', 'old');
      await prefs.setInt('sync_meta_tier3_last', 123456);
      await prefs.setString('old_setting', 'remove');
      await BackupService(
        target,
        preferences: prefs,
      ).importFromJson(jsonEncode(payload));

      expect((await target.select(target.accounts).get()).map((r) => r.id), [
        10,
        20,
      ]);
      final accounts = await target.select(target.accounts).get();
      expect(accounts.where((r) => r.isActive).single.id, 20);
      expect(accounts.first.password, 'synthetic');
      final profiles = await target.select(target.profiles).get();
      expect(profiles.map((r) => r.id), [1, 7, 12]);
      expect(profiles.singleWhere((r) => r.id == 7).pin, '1234');
      expect(profiles.singleWhere((r) => r.id == 7).isKids, isTrue);
      expect((await target.select(target.favorites).get()).length, 3);
      expect((await target.select(target.watchlist).get()).length, 3);
      expect(
        (await target.select(target.playbackProgress).get())
            .map((r) => r.position)
            .toSet(),
        {1000, 7000, 12000},
      );
      expect((await target.select(target.seriesTracking).get()).length, 3);
      expect((await target.select(target.aiFeedback).get()).length, 3);
      expect((await target.select(target.searchHistory).get()).length, 3);
      expect((await target.select(target.syncTombstones).get()).length, 3);
      expect(
        (await target.select(target.categoryPrefs).getSingle()).isHidden,
        isTrue,
      );
      expect(
        (await target.select(target.introMarkers).getSingle()).introEndMs,
        40000,
      );
      expect(await target.select(target.channels).get(), isEmpty);
      expect(await target.select(target.contentEnrichment).get(), isEmpty);
      expect(prefs.getInt('default_account_id'), 20);
      expect(prefs.getInt('active_profile_id'), 7);
      expect(prefs.getString('epg_url_10'), 'https://example.invalid/a.xml');
      expect(prefs.getString('epg_url_20'), 'https://example.invalid/b.xml');
      expect(prefs.containsKey('epg_url_80'), isFalse);
      expect(prefs.containsKey('sync_meta_tier3_last'), isFalse);
      expect(prefs.containsKey('old_setting'), isFalse);
      expect(await target.select(target.backupRestoreJournal).get(), isEmpty);
      // IDs remain stable even when SQLite's previous autoincrement was larger.
      final next = await target
          .into(target.accounts)
          .insert(
            AccountsCompanion.insert(name: 'Next', type: 'm3u', url: 'next'),
          );
      expect(next, greaterThan(80));
    },
  );

  test(
    'device pairing and external API keys never travel through backup',
    () async {
      await prefs.setString('lan_sync_device_id', 'local-device');
      await prefs.setString('lan_sync_trusted_peers', 'local-peers');
      await prefs.setBool('auto_sync_enabled', true);
      await prefs.setString('gemini_api_key', 'local-secret');
      await prefs.setString('opensubtitles_api_key', 'local-sub-secret');
      final payload = await fixture();
      final settings = payload['settings'] as Map<String, dynamic>;
      expect(settings.keys.any(BackupDocument.isDeviceSetting), isFalse);
      settings.addAll({
        'lan_sync_device_id': 'foreign-device',
        'gemini_api_key': 'foreign-secret',
      });
      await service.importFromJson(jsonEncode(payload));
      expect(prefs.getString('lan_sync_device_id'), 'local-device');
      expect(prefs.getString('lan_sync_trusted_peers'), 'local-peers');
      expect(prefs.getString('gemini_api_key'), 'local-secret');
      expect(prefs.getString('opensubtitles_api_key'), 'local-sub-secret');
      expect(prefs.getBool('auto_sync_enabled'), isTrue);
    },
  );

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'missing table': (p) => p.remove('favorites'),
    'future version': (p) => p['version'] = 999,
    'missing version': (p) => p.remove('version'),
    'duplicate row': (p) =>
        (p['favorites'] as List).add((p['favorites'] as List).first),
    'unknown profile': (p) => (p['favorites'] as List).first['profileId'] = 999,
    'bad row type': (p) => (p['favorites'] as List).first['streamId'] = '42',
    'invalid preference': (p) => p['settings']['bad'] = {'nested': 'map'},
    'invalid selection': (p) => p['settings']['active_profile_id'] = '7',
    'negative position': (p) =>
        (p['playbackProgress'] as List).first['position'] = -1,
    'bad date': (p) =>
        (p['accounts'] as List).first['createdAt'] = 'invalid-date',
  };
  for (final entry in corruptions.entries) {
    test('${entry.key} is rejected before modifying existing data', () async {
      final payload = await fixture();
      final before = await service.exportToJson();
      final prefsBefore = {for (final k in prefs.getKeys()) k: prefs.get(k)};
      entry.value(payload);
      await expectLater(
        service.importFromJson(jsonEncode(payload)),
        throwsFormatException,
      );
      final after =
          jsonDecode(await service.exportToJson()) as Map<String, dynamic>;
      final expected = jsonDecode(before) as Map<String, dynamic>;
      after.remove('createdAt');
      expected.remove('createdAt');
      expect(after, expected);
      expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, prefsBefore);
      expect(await db.select(db.backupRestoreJournal).get(), isEmpty);
    });
  }

  test(
    'legacy v1 preserves account IDs/EPG and seeds the default profile',
    () async {
      final payload = {
        'magic': BackupDocument.magic,
        'version': 1,
        'accounts': [
          {
            'id': 17,
            'name': 'Legacy',
            'type': 'm3u',
            'url': 'playlist',
            'isActive': true,
            'createdAt': '2026-01-01T00:00:00Z',
          },
        ],
        'favorites': [
          {'streamId': 42, 'streamType': 'movie', 'name': 'Legacy title'},
        ],
        'playbackProgress': [
          {
            'streamId': 42,
            'type': 'movie',
            'position': 4000,
            'duration': 10000,
          },
        ],
        'seriesTracking': [],
        'settings': {
          'default_account_id': 17,
          'active_profile_id': 99,
          'epg_url_17': 'https://example.invalid/epg.xml',
          'epg_url_99': 'orphan',
        },
      };
      await service.importFromJson(jsonEncode(payload));
      expect((await db.select(db.accounts).getSingle()).id, 17);
      expect((await db.select(db.favorites).getSingle()).profileId, 1);
      expect((await db.select(db.playbackProgress).getSingle()).position, 4000);
      expect((await db.select(db.profiles).getSingle()).id, 1);
      expect(prefs.getInt('active_profile_id'), 1);
      expect(prefs.getString('epg_url_17'), 'https://example.invalid/epg.xml');
      expect(prefs.containsKey('epg_url_99'), isFalse);
    },
  );

  test(
    'DB active account takes precedence over stale preference in backup',
    () async {
      final payload = await fixture();
      payload['settings']['default_account_id'] = 10;
      await service.importFromJson(jsonEncode(payload));
      expect(prefs.getInt('default_account_id'), 20);
      expect(
        (await db.select(db.accounts).get()).where((r) => r.isActive).single.id,
        20,
      );
    },
  );

  test(
    'preference write failure rolls DB and preferences back together',
    () async {
      final payload = await fixture();
      payload['accounts'][0]['name'] = 'Must not commit';
      payload['settings']['app_language'] = 'en';
      final failing = _FailingPreferences(prefs)..failures = 1;
      await expectLater(
        BackupService(
          db,
          preferences: failing,
        ).importFromJson(jsonEncode(payload)),
        throwsStateError,
      );
      expect((await db.select(db.accounts).get()).first.name, 'Account 10');
      expect(prefs.getString('app_language'), 'tr');
      expect(await db.select(db.backupRestoreJournal).get(), isEmpty);
    },
  );

  test(
    'failed rollback keeps durable journal for a later successful retry',
    () async {
      final payload = await fixture();
      payload['settings']['app_language'] = 'en';
      final failing = _FailingPreferences(prefs)..failures = 2;
      await expectLater(
        BackupService(
          db,
          preferences: failing,
        ).importFromJson(jsonEncode(payload)),
        throwsStateError,
      );
      expect(await db.select(db.backupRestoreJournal).get(), hasLength(1));
      await service.recoverPendingRestore();
      expect(prefs.getString('app_language'), 'tr');
      expect(await db.select(db.backupRestoreJournal).get(), isEmpty);
    },
  );

  test(
    'SQL failure after deletions leaves catalogue and user rows intact',
    () async {
      final payload = await fixture();
      await db.customStatement(
        "CREATE TRIGGER reject_restore BEFORE INSERT ON accounts BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(
        service.importFromJson(jsonEncode(payload)),
        throwsA(isA<Exception>()),
      );
      expect((await db.select(db.accounts).get()).length, 2);
      expect((await db.select(db.favorites).get()).length, 3);
      expect(prefs.getInt('default_account_id'), 20);
      expect(await db.select(db.backupRestoreJournal).get(), isEmpty);
    },
  );

  test(
    'startup recovers preferences after a terminated DB transaction',
    () async {
      final directory = await Directory.systemTemp.createTemp('iptv-restore-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');
      final original = AppDatabase.forTesting(NativeDatabase(file));
      await original
          .into(original.accounts)
          .insert(
            AccountsCompanion.insert(
              id: const Value(31),
              name: 'Original',
              type: 'm3u',
              url: 'original',
            ),
          );
      await original
          .into(original.backupRestoreJournal)
          .insert(
            BackupRestoreJournalCompanion.insert(
              id: const Value(0),
              preferencesJson: jsonEncode({
                'default_account_id': 31,
                'app_language': 'tr',
              }),
            ),
          );
      // Equivalent durable state after SQLite rolls an uncommitted restore back.
      await prefs.setInt('default_account_id', 200);
      await prefs.setString('app_language', 'en');
      await prefs.setString('new_incomplete_setting', 'partial');
      await original.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      await BackupService(reopened, preferences: prefs).recoverPendingRestore();
      expect((await reopened.select(reopened.accounts).getSingle()).id, 31);
      expect(prefs.getInt('default_account_id'), 31);
      expect(prefs.getString('app_language'), 'tr');
      expect(prefs.containsKey('new_incomplete_setting'), isFalse);
      expect(
        await reopened.select(reopened.backupRestoreJournal).get(),
        isEmpty,
      );
    },
  );
}

class _FailingPreferences implements SharedPreferences {
  final SharedPreferences delegate;
  int failures = 0;
  _FailingPreferences(this.delegate);
  @override
  Set<String> getKeys() => delegate.getKeys();
  @override
  Object? get(String key) => delegate.get(key);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setBool(String key, bool value) => delegate.setBool(key, value);
  @override
  Future<bool> setInt(String key, int value) => delegate.setInt(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      delegate.setDouble(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      delegate.setStringList(key, value);
  @override
  Future<bool> setString(String key, String value) async {
    if (key == 'app_language' && failures-- > 0) return false;
    return delegate.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
