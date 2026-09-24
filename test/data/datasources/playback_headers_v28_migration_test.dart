import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  test('v27 adds nullable playback headers without changing channels or history', () async {
    final folder = await Directory.systemTemp.createTemp('iptv-v28-');
    final file = File('${folder.path}/test.sqlite');
    addTearDown(() => folder.delete(recursive: true));
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.into(db.channels).insert(ChannelsCompanion.insert(streamId: 42, name: 'Keep', type: 'movie', categoryId: 'cat', streamUrl: const Value('https://example.invalid/a.mp4')));
    await db.into(db.playbackProgress).insert(PlaybackProgressCompanion.insert(streamId: 42, type: 'movie', position: 1000, duration: 10000));
    await db.customStatement('ALTER TABLE channels DROP COLUMN playback_headers');
    await db.customStatement('PRAGMA user_version=27');
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final channel = await db.select(db.channels).getSingle();
    expect(channel.streamId, 42);
    expect(channel.name, 'Keep');
    expect(channel.playbackHeaders, isNull);
    expect((await db.select(db.playbackProgress).getSingle()).position, 1000);
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.single, 29);
  });
}
