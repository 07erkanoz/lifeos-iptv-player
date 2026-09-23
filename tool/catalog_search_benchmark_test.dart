// flutter test tool/catalog_search_benchmark_test.dart --reporter expanded
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/utils/search_normalizer.dart';
import 'playlist_benchmark_test.dart' show measure;

void main() {
  test('10k catalogue exact and typo search responsiveness', () async {
    final root = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(root.close);
    final db = root.forAccount(1);
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'movies',
            name: 'Movies',
            type: 'movie',
          ),
        );
    await db.accountBatch((b) {
      for (var i = 0; i < 10000; i++) {
        b.insert(
          db.channels,
          ChannelsCompanion.insert(
            streamId: i,
            name: i == 9999 ? 'İnterstellar' : 'Catalogue Film $i',
            type: 'movie',
            categoryId: 'movies',
            rating: Value(i == 9999 ? 1 : 9),
            plot: const Value(
              'Adventure exploring distant places with a family',
            ),
          ),
        );
      }
    });
    final repo = ContentRepository(
      db,
      SyncService(db, XtreamApiService(Dio())),
      () => 1,
    );
    final samples = <Map<String, dynamic>>[];
    // A full-main comparison has equal coverage, unlike the old truncated path.
    samples.add(
      await measure('full-catalogue-fuzzy', 1, 0, 'full-main', () async {
        final all = await db.select(db.channels).get();
        final tokens = SearchNormalizer.tokens('intersttellar');
        return all
            .where(
              (c) => SearchNormalizer.matchesFuzzy(
                SearchNormalizer.buildHaystack(
                  name: c.name,
                  categoryName: 'Movies',
                  plot: c.plot,
                ),
                tokens,
              ),
            )
            .length;
      }),
    );
    for (final query in ['interstellar', 'intersttellar']) {
      samples.add(
        await measure(query, 1, 0, 'paged-worker-unindexed', () async {
          final hits = await repo.searchChannelsByType(query, 'movie');
          expect(hits.single.streamId, 9999);
          return hits.length;
        }),
      );
    }
    await repo.refreshSearchIndex();
    samples.add(
      await measure(
        'interstellar',
        1,
        0,
        'indexed-worker',
        () async =>
            (await repo.searchChannelsByType('interstellar', 'movie')).length,
      ),
    );
    final output = {
      'note':
          'Synthetic 10000-row Linux host fixture. NativeDatabase.memory runs SQLite in the test isolate; production DB uses a worker. Timer gaps are not frame times. Full-main comparison has equal catalogue coverage; old 6000-row fallback omitted target.',
      'samples': samples,
    };
    File(
      'docs/catalog-performance-2026-09-23/search-benchmark.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
    // ignore: avoid_print
    print(jsonEncode(output));
  });
}
