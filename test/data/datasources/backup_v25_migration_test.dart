import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  for (final journalAlreadyExists in [false, true]) {
    test(
      'v24 upgrade preserves profiles and favorites (partial=$journalAlreadyExists)',
      () async {
        final directory = await Directory.systemTemp.createTemp('iptv-v25-');
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/test.sqlite');
        final old = AppDatabase.forTesting(NativeDatabase(file));
        await old
            .into(old.profiles)
            .insert(
              ProfilesCompanion.insert(id: const Value(7), name: 'Protected'),
            );
        for (final profile in [1, 7]) {
          await old
              .into(old.favorites)
              .insert(
                FavoritesCompanion.insert(
                  streamId: 42,
                  streamType: 'movie',
                  name: 'Same title',
                  profileId: Value(profile),
                ),
              );
        }
        if (!journalAlreadyExists) {
          await old.customStatement('DROP TABLE backup_restore_journal');
        }
        await old.customStatement('PRAGMA user_version = 24');
        await old.close();
        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(upgraded.close);
        expect((await upgraded.select(upgraded.profiles).get()).length, 2);
        expect(
          (await upgraded.select(upgraded.favorites).get())
              .map((r) => r.profileId)
              .toSet(),
          {1, 7},
        );
        expect(
          await upgraded.select(upgraded.backupRestoreJournal).get(),
          isEmpty,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .data['user_version'],
          upgraded.schemaVersion,
        );
      },
    );
  }
}
