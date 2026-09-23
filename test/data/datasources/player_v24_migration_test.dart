import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';

void main() {
  for (final columnAlreadyPresent in [false, true]) {
    test(
      'v23 to v24 preserves catalogue and progress (column present=$columnAlreadyPresent)',
      () async {
        final dir = await Directory.systemTemp.createTemp('iptv-v24-test-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/test.sqlite');
        final legacy = AppDatabase.forTesting(NativeDatabase(file));
        await legacy
            .into(legacy.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'films',
                name: 'Films',
                type: 'movie',
              ),
            );
        await legacy
            .into(legacy.channels)
            .insert(
              ChannelsCompanion.insert(
                streamId: 123456789,
                name: 'M3U Film',
                type: 'movie',
                categoryId: 'films',
                streamUrl: const Value(
                  'https://example.invalid/title?token=a%2Fb',
                ),
              ),
            );
        await PlayerRepository(
          legacy,
          () => 1,
        ).saveProgress(123456789, 'movie', 50000, 100000);
        // Derive the previous schema: v24 changes only this nullable column.
        if (!columnAlreadyPresent) {
          await legacy.customStatement(
            'ALTER TABLE channels DROP COLUMN container_extension',
          );
        }
        await legacy.customStatement('PRAGMA user_version = 23');
        await legacy.close();

        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(upgraded.close);
        final channel = await upgraded.select(upgraded.channels).getSingle();
        expect(channel.streamId, 123456789);
        expect(channel.streamUrl, 'https://example.invalid/title?token=a%2Fb');
        expect(channel.containerExtension, isNull);
        final progress = await PlayerRepository(
          upgraded,
          () => 1,
        ).getProgress(123456789, 'movie');
        expect(progress?.position, 50000);
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data['user_version'], upgraded.schemaVersion);
        await (upgraded.update(
          upgraded.channels,
        )).write(const ChannelsCompanion(containerExtension: Value('mp4')));
        expect(
          (await upgraded.select(upgraded.channels).getSingle())
              .containerExtension,
          'mp4',
        );
      },
    );
  }
}
