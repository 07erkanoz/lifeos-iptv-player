import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/data/services/m3u_series_catalog.dart';

void main() {
  late AppDatabase root, db;
  late ContentRepository content;
  late PlayerRepository player;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = AppDatabase.forTesting(NativeDatabase.memory());
    await root
        .into(root.accounts)
        .insert(
          AccountsCompanion.insert(
            id: const Value(1),
            name: 'Xtream',
            type: 'xtream',
            url: 'https://example.invalid',
          ),
        );
    db = root.forAccount(1);
    content = ContentRepository(
      db,
      SyncService(db, XtreamApiService(Dio())),
      () => 1,
    );
    player = PlayerRepository(db, () => 1);
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'series',
            name: 'Series',
            type: 'series',
          ),
        );
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            streamId: 42,
            name: 'Show',
            type: 'series',
            categoryId: 'series',
          ),
        );
  });
  tearDown(() async {
    await root.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  test(
    'legacy series history survives; new summary wins and hides stale legacy mirrors',
    () async {
      await player.saveProgress(42, 'series', 10000, 100000);
      expect(await content.watchContinueWatching('series').first, hasLength(1));
      await player.saveEpisodeProgress(7, 30000, 100000, parentSeriesId: 42);
      expect(await content.watchContinueWatching('series').first, hasLength(1));
      await player.saveEpisodeProgress(7, 100000, 100000, parentSeriesId: 42);
      expect(await content.watchContinueWatching('series').first, isEmpty);
      expect((await player.getProgress(42, 'series'))?.position, 10000);
    },
  );
  test(
    'removing series history preserves colliding episode and blocks legacy resurfacing',
    () async {
      await player.saveProgress(42, 'series', 20000, 100000);
      await player.removeSeriesFromHistory(42);
      expect(await content.watchContinueWatching('series').first, isEmpty);
      expect((await player.getProgress(42, 'series'))?.position, 20000);
      await player.saveEpisodeProgress(8, 10000, 100000, parentSeriesId: 42);
      expect(await content.watchContinueWatching('series').first, hasLength(1));
    },
  );
  test(
    'M3U catalogue excludes hidden categories and other accounts before grouping',
    () async {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'hidden',
              name: 'Hidden',
              type: 'series',
              isHidden: const Value(true),
            ),
          );
      for (final (id, cat) in [(1, 'series'), (2, 'hidden')]) {
        await db
            .into(db.channels)
            .insert(
              ChannelsCompanion.insert(
                streamId: id,
                name: 'Show S01E0$id',
                type: 'series',
                categoryId: cat,
                streamUrl: Value('https://example.invalid/$id.mp4'),
              ),
            );
      }
      final other = root.forAccount(2);
      await other
          .into(other.channels)
          .insert(
            ChannelsCompanion.insert(
              streamId: 3,
              name: 'Show S01E03',
              type: 'series',
              categoryId: 'series',
              streamUrl: const Value('https://example.invalid/3.mp4'),
            ),
          );
      final index = buildM3uSeriesCatalog(
        await content.watchAllChannelsByType('series').first,
      );
      expect(index.series.single.episodes.map((e) => e.streamId), [1]);
    },
  );
}
