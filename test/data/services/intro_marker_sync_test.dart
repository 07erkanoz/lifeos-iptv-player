import 'dart:convert';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/intro_marker_repository.dart';
import 'package:lifeostv/data/services/backup_document.dart';
import 'package:lifeostv/data/services/backup_service.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';
import 'package:lifeostv/data/services/m3u_lan_identity.dart';

void main() {
  late AppDatabase root, scoped;
  late SharedPreferences prefs;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    root = AppDatabase.forTesting(NativeDatabase.memory());
    for (var id = 1; id <= 2; id++) {
      await root
          .into(root.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              name: 'A$id',
              type: 'xtream',
              url: 'https://example.invalid/$id',
            ),
          );
    }
    scoped = root.forAccount(1);
  });
  tearDown(() async {
    await root.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  test(
    'delete and immediate re-create advances the stored timestamp',
    () async {
      final repo = IntroMarkerRepository(scoped);
      await repo.clearMarker(20, season: 1, episodeId: 11);
      final deletion = (await scoped.select(scoped.introMarkers).getSingle())
          .toJson();
      await repo.setMarker(
        20,
        season: 1,
        episodeId: 11,
        introStartMs: 1000,
        introEndMs: 10000,
      );
      final marker = await repo.getMarker(20, season: 1, episodeId: 11);
      expect(marker, isNotNull);
      expect(
        marker!.updatedAt.isAfter(IntroMarker.fromJson(deletion).updatedAt),
        true,
      );
      expect(await repo.merge([deletion]), 0);
      expect(await repo.getMarker(20, season: 1, episodeId: 11), isNotNull);
    },
  );
  test(
    'same series has independent episode, season and account markers',
    () async {
      final repo = IntroMarkerRepository(scoped);
      await repo.setMarker(
        20,
        season: 1,
        episodeId: 11,
        introStartMs: 1000,
        introEndMs: 10000,
        durationMs: 20000,
      );
      expect(await repo.getMarker(20, season: 1, episodeId: 12), isNull);
      expect(await repo.getMarker(20, season: 2, episodeId: 11), isNull);
      expect(
        await IntroMarkerRepository(
          root.forAccount(2),
        ).getMarker(20, season: 1, episodeId: 11),
        isNull,
      );
      await expectLater(
        repo.setMarker(20, introStartMs: 10000, introEndMs: 5000),
        throwsArgumentError,
      );
      await expectLater(
        repo.setMarker(
          20,
          introStartMs: 0,
          introEndMs: 30000,
          durationMs: 20000,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'LAN snapshot preserves scoped markers and prevents stale resurrection',
    () async {
      final repo = IntroMarkerRepository(scoped);
      await repo.setMarker(
        20,
        season: 1,
        episodeId: 11,
        introStartMs: 1000,
        introEndMs: 10000,
      );
      final service = LanSyncService(scoped, prefs),
          snapshot = await LanSyncService(scoped, prefs).buildSyncSnapshot();
      expect((snapshot['introMarkers'] as List).length, 1);
      await repo.clearMarker(20, season: 1, episodeId: 11);
      await service.mergeSyncSnapshot(snapshot);
      expect(await repo.getMarker(20, season: 1, episodeId: 11), isNull);
      final deleted = await service.buildSyncSnapshot();
      expect((deleted['introMarkers'] as List).single['isDeleted'], true);
      await LanSyncService(
        root.forAccount(2),
        prefs,
      ).mergeSyncSnapshot(snapshot);
      expect(await root.forAccount(2).select(root.introMarkers).get(), isEmpty);
    },
  );
  test(
    'v4 backup upgrades stored rows as unverified legacy evidence',
    () async {
      await IntroMarkerRepository(
        scoped,
      ).setMarker(20, introStartMs: 1000, introEndMs: 10000);
      final payload =
          jsonDecode(
                await BackupService(root, preferences: prefs).exportToJson(),
              )
              as Map<String, dynamic>;
      payload['version'] = 4;
      for (final row in payload['introMarkers'] as List) {
        for (final key in [
          'season',
          'episodeId',
          'source',
          'confidence',
          'isDeleted',
        ]) {
          row.remove(key);
        }
      }
      final document = BackupDocument.parse(jsonEncode(payload));
      expect(document.tables['introMarkers']!.single['source'], 'legacy');
      expect(document.tables['introMarkers']!.single['confidence'], 0);
      await BackupService(
        root,
        preferences: prefs,
      ).importFromJson(jsonEncode(payload));
      expect(
        (await scoped.select(scoped.introMarkers).getSingle()).episodeId,
        0,
      );
    },
  );
  test(
    'M3U maps both parent and episode identities and refuses unmapped rows',
    () {
      final local = [
        for (final id in [20, 11])
          M3uIdentity(
            streamId: id,
            accountId: 1,
            type: 'series',
            sourceKey: 'key$id',
            sourceUrl: 'https://example.invalid/$id',
          ),
      ];
      final payload = {
        'm3uIdentities': [
          {'streamId': 200, 'type': 'series', 'sourceKey': 'key20'},
          {'streamId': 110, 'type': 'series', 'sourceKey': 'key11'},
        ],
        'introMarkers': [
          {'seriesId': 200, 'episodeId': 110},
          {'seriesId': 200, 'episodeId': 0},
        ],
      };
      final rows =
          remapM3uLanPayload(payload, local, requireAll: true)['introMarkers']
              as List;
      expect(rows.first['seriesId'], 20);
      expect(rows.first['episodeId'], 11);
      expect(rows.last['episodeId'], 0);
      expect(remapM3uLanPayload(payload, [])['introMarkers'], isEmpty);
      expect(
        () => remapM3uLanPayload(payload, [], requireAll: true),
        throwsFormatException,
      );
    },
  );
}
