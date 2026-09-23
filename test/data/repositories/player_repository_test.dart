import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';

void main() {
  late AppDatabase db;
  late PlayerRepository repo;
  var profile = 1;
  setUp(() {
    profile = 1;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PlayerRepository(db, () => profile);
  });
  tearDown(() => db.close());

  test(
    'a series summary never overwrites an episode with the same numeric ID',
    () async {
      await repo.saveEpisodeProgress(42, 10000, 100000, parentSeriesId: 9);
      await repo.saveEpisodeProgress(7, 50000, 100000, parentSeriesId: 42);
      expect((await repo.getProgress(42, 'series'))?.position, 10000);
      expect((await repo.getProgress(42, 'series_parent'))?.position, 50000);
      await repo.saveEpisodeProgress(9, 12000, 100000, parentSeriesId: 9);
      expect((await repo.getProgress(9, 'series'))?.position, 12000);
      expect((await repo.getProgress(9, 'series_parent'))?.position, 12000);
    },
  );
  test(
    'M3U episode writes do not mirror into the representative episode',
    () async {
      await repo.saveEpisodeProgress(1, 20000, 100000);
      await repo.saveEpisodeProgress(2, 70000, 100000);
      expect((await repo.getProgress(1, 'series'))?.position, 20000);
      expect(await repo.getProgress(1, 'series_parent'), isNull);
    },
  );
  test('episode and summary updates roll back together', () async {
    await repo.saveEpisodeProgress(1, 10000, 100000, parentSeriesId: 5);
    await db.customStatement(
      "CREATE TRIGGER abort_summary BEFORE INSERT ON playback_progress WHEN NEW.type='series_parent' BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      repo.saveEpisodeProgress(1, 50000, 100000, parentSeriesId: 5),
      throwsA(isA<Exception>()),
    );
    expect((await repo.getProgress(1, 'series'))?.position, 10000);
  });
  test('large season operations are bounded and profile scoped', () async {
    final ids = List.generate(1200, (i) => i + 1);
    await repo.markEpisodesAsWatched(ids);
    expect(await repo.finishedCount(ids), 1200);
    profile = 2;
    await repo.saveEpisodeProgress(1200, 15000, 100000);
    expect(await repo.finishedCount(ids), 0);
    profile = 1;
    await db
        .update(db.playbackProgress)
        .write(PlaybackProgressCompanion(updatedAt: Value(DateTime(2026))));
    await repo.saveEpisodeProgress(1000, 60000, 100000);
    expect((await repo.getLatestSeriesProgress(ids))?.streamId, 1000);
    await repo.unmarkEpisodes(ids);
    expect(await repo.getLatestSeriesProgress(ids), isNull);
    profile = 2;
    expect((await repo.getProgress(1200, 'series'))?.position, 15000);
  });

  test(
    'M3U hash ID round-trips independently of numeric media filename',
    () async {
      final id = stableM3uChannelId(
        url: 'https://example.invalid/77.mp4?token=one',
        name: 'Film',
      );
      await repo.saveProgress(id, 'movie', 35000, 100000);
      expect((await repo.getProgress(id, 'movie'))?.position, 35000);
      expect(await repo.getProgress(77, 'movie'), isNull);
      expect(await repo.getProgress(id, 'live'), isNull);
    },
  );

  test('progress and resume stay isolated by active profile', () async {
    await repo.saveProgress(123, 'movie', 20000, 100000);
    profile = 2;
    expect(await repo.getProgress(123, 'movie'), isNull);
    await repo.saveProgress(123, 'movie', 40000, 100000);
    profile = 1;
    expect((await repo.getProgress(123, 'movie'))?.position, 20000);
  });

  test(
    'invalid duration/negative position cannot overwrite saved progress',
    () async {
      await repo.saveProgress(123, 'movie', 20000, 100000);
      await repo.saveProgress(123, 'movie', 50000, 0);
      await repo.saveProgress(123, 'movie', -5000, 100000);
      expect((await repo.getProgress(123, 'movie'))?.position, 20000);
    },
  );

  test('overshooting the end is bounded and marked finished', () async {
    await repo.saveProgress(123, 'movie', 120000, 100000);
    final saved = await repo.getProgress(123, 'movie');
    expect(saved?.position, 100000);
    expect(saved?.isFinished, isTrue);
  });
}
