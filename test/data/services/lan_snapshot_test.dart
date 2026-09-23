import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/settings_repository.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';

void main() {
  late AppDatabase root, db;
  late SharedPreferences prefs;
  late LanSyncService service;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    root = AppDatabase.forTesting(NativeDatabase.memory());
    await root
        .into(root.accounts)
        .insert(
          AccountsCompanion.insert(
            id: const Value(1),
            name: 'Account',
            type: 'xtream',
            url: 'https://example.invalid',
          ),
        );
    db = root.forAccount(1);
    service = LanSyncService(db, prefs);
    await SettingsRepository(prefs).saveSettings(
      const AppSettings(
        geminiApiKey: 'local-key',
        opensubtitlesApiKey: 'subtitle-key',
        parentalPin: '5678',
      ),
    );
  });
  tearDown(() async {
    await root.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'manual public settings and auto snapshots never export API keys',
    () async {
      final plain = await service.exportSnapshot({
        SyncCategory.settings,
        SyncCategory.profiles,
      });
      expect(plain['settings'], isNot(contains('geminiApiKey')));
      expect(plain['settings'], isNot(contains('parentalPin')));
      expect((plain['profiles'] as List).first, isNot(contains('pin')));
      final auto = await service.buildSyncSnapshot();
      expect(auto, isNot(contains('geminiApiKey')));
      final explicit = await service.exportSnapshot({SyncCategory.secrets});
      expect((explicit['secrets'] as Map)['geminiApiKey'], 'local-key');
    },
  );

  test(
    'older manual peer cannot replace local secrets without selection',
    () async {
      await service.importSnapshot(
        {
          'settings': {
            'geminiApiKey': 'remote-key',
            'parentalPin': '1234',
            'parentalControlEnabled': true,
            'showTrailer': false,
          },
        },
        cats: {SyncCategory.settings},
        activeProfileId: 1,
      );
      final settings = SettingsRepository(prefs).loadSettings();
      expect(settings.geminiApiKey, 'local-key');
      expect(settings.parentalPin, '5678');
      expect(settings.parentalControlEnabled, false);
      expect(settings.showTrailer, false);
      await service.importSnapshot(
        {
          'secrets': {'geminiApiKey': 'selected-key'},
        },
        cats: {SyncCategory.secrets},
        activeProfileId: 1,
      );
      expect(
        SettingsRepository(prefs).loadSettings().geminiApiKey,
        'selected-key',
      );
    },
  );

  test('old automatic peer cannot inject a missing Gemini key', () async {
    await SettingsRepository(prefs).saveSettings(const AppSettings());
    final snap = await service.buildSyncSnapshot();
    snap['geminiApiKey'] = 'old-remote-key';
    await service.mergeSyncSnapshot(snap);
    expect(SettingsRepository(prefs).loadSettings().geminiApiKey, isNull);
  });

  test(
    'unselected profiles match by name instead of collapsing into active profile',
    () async {
      final one = await root.select(root.profiles).getSingle();
      final two = await root
          .into(root.profiles)
          .insert(ProfilesCompanion.insert(name: 'Child'));
      final identity = (await service.exportSnapshot({}))['contentAccountKey'];
      final payload = {
        'contentAccountKey': identity,
        'profileRefs': [
          {'oldId': 101, 'name': one.name},
          {'oldId': 102, 'name': 'Child'},
        ],
        'favorites': [
          for (final pid in [101, 102])
            {
              'profileId': pid,
              'streamId': 7,
              'streamType': 'movie',
              'name': 'Film',
            },
        ],
      };
      await service.importSnapshot(
        payload,
        cats: {SyncCategory.favorites},
        activeProfileId: one.id,
      );
      expect(
        (await db.select(db.favorites).get()).map((f) => f.profileId),
        unorderedEquals([one.id, two]),
      );
    },
  );

  test(
    'ambiguous legacy profiles abort and roll back all imported rows',
    () async {
      final identity = (await service.exportSnapshot({}))['contentAccountKey'];
      final payload = {
        'contentAccountKey': identity,
        'accounts': [
          {
            'name': 'Must roll back',
            'type': 'm3u',
            'url': 'https://example.invalid/new.m3u',
          },
        ],
        'favorites': [
          for (final pid in [101, 102])
            {
              'profileId': pid,
              'streamId': pid,
              'streamType': 'movie',
              'name': 'Film',
            },
        ],
      };
      await expectLater(
        service.importSnapshot(
          payload,
          cats: {SyncCategory.account, SyncCategory.favorites},
          activeProfileId: 1,
        ),
        throwsFormatException,
      );
      expect(await db.select(db.favorites).get(), isEmpty);
      expect(await root.select(root.accounts).get(), hasLength(1));
    },
  );
}
