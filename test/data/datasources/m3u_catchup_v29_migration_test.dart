import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  test(
    'v28 adds nullable catch-up metadata without losing channels or progress',
    () async {
      final folder = await Directory.systemTemp.createTemp('iptv-v29-');
      final file = File('${folder.path}/test.sqlite');
      addTearDown(() => folder.delete(recursive: true));
      var db = AppDatabase.forTesting(NativeDatabase(file));
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              streamId: 42,
              name: 'Keep',
              type: 'live',
              categoryId: 'cat',
              streamUrl: const Value('https://example.invalid/a.ts'),
            ),
          );
      await db
          .into(db.playbackProgress)
          .insert(
            PlaybackProgressCompanion.insert(
              streamId: 42,
              type: 'live',
              position: 1,
              duration: 100,
            ),
          );
      await db.customStatement(
        'ALTER TABLE channels DROP COLUMN catchup_metadata',
      );
      await db.customStatement('PRAGMA user_version=28');
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      final channel = await db.select(db.channels).getSingle();
      expect(channel.streamId, 42);
      expect(channel.catchupMetadata, isNull);
      expect((await db.select(db.playbackProgress).getSingle()).position, 1);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        29,
      );
    },
  );
}
