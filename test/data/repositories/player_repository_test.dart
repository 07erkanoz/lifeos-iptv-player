import 'package:drift/native.dart';
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
