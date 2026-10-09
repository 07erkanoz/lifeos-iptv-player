import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  for (final partial in [false, true]) {
    test(
      'v26 upgrade retains catalogue; registry already exists=$partial',
      () async {
        final dir = await Directory.systemTemp.createTemp('iptv-v27-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/test.sqlite');
        final old = AppDatabase.forTesting(NativeDatabase(file));
        await old
            .into(old.channels)
            .insert(
              ChannelsCompanion.insert(
                streamId: 799436981,
                name: 'Old',
                type: 'live',
                categoryId: 'Live',
                streamUrl: const Value('https://example.invalid/18310.ts'),
              ),
            );
        if (!partial) await old.customStatement('DROP TABLE m3u_identities');
        await old.customStatement('PRAGMA user_version=26');
        await old.close();
        final upgraded = AppDatabase.forTesting(NativeDatabase(file));
        addTearDown(upgraded.close);
        expect(
          (await upgraded.select(upgraded.channels).getSingle()).streamId,
          799436981,
        );
        expect(await upgraded.select(upgraded.m3uIdentities).get(), isEmpty);
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          upgraded.schemaVersion,
        );
      },
    );
  }
}
