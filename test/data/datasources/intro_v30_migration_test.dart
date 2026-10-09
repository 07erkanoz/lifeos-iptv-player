import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  test(
    'v29 series markers are preserved without trusting an episode-wide guess',
    () async {
      final folder = await Directory.systemTemp.createTemp('lifeos-v30-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/db.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: const Value(1),
              name: 'A',
              type: 'xtream',
              url: 'https://example.invalid',
            ),
          );
      await db.customStatement('DROP TABLE intro_markers');
      await db.customStatement(
        'CREATE TABLE intro_markers (series_id INTEGER NOT NULL, account_id INTEGER NOT NULL DEFAULT 0, intro_start_ms INTEGER NOT NULL, intro_end_ms INTEGER NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(series_id,account_id))',
      );
      await db.customStatement(
        'INSERT INTO intro_markers VALUES(20,1,1000,10000,1700000000)',
      );
      await db.customStatement('PRAGMA user_version=29');
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      final marker = await db.forAccount(1).select(db.introMarkers).getSingle();
      expect(marker.introStartMs, 1000);
      expect(marker.introEndMs, 10000);
      expect(marker.source, 'legacy');
      expect(marker.confidence, 0);
      expect(marker.episodeId, 0);
      await db
          .forAccount(1)
          .into(db.introMarkers)
          .insert(
            IntroMarkersCompanion.insert(
              seriesId: 20,
              season: const Value(1),
              episodeId: const Value(11),
              introStartMs: 2000,
              introEndMs: 12000,
            ),
          );
      expect((await db.select(db.introMarkers).get()).length, 2);
    },
  );
}
