import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/utils/search_normalizer.dart';

void main() {
  late AppDatabase root, db;
  late ContentRepository repo;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = AppDatabase.forTesting(NativeDatabase.memory());
    db = root.forAccount(1);
    repo = ContentRepository(
      db,
      SyncService(db, XtreamApiService(Dio())),
      () => 1,
      autoHideAdult: () => true,
    );
    for (final account in [1, 2]) {
      final scope = root.forAccount(account);
      for (final (id, name, hidden) in [
        ('normal', 'Normal', false),
        ('hidden', 'Hidden', true),
        ('adult', 'XXX', false),
      ]) {
        await scope
            .into(scope.categories)
            .insert(
              CategoriesCompanion.insert(
                id: id,
                name: name,
                type: 'movie',
                isHidden: Value(hidden),
              ),
            );
      }
    }
  });
  tearDown(() async {
    await root.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  Future<void> insert(
    int id,
    String name, {
    double rating = 1,
    String? searchText,
    String? plot,
    String category = 'normal',
    AppDatabase? scope,
  }) async {
    final d = scope ?? db;
    await d
        .into(d.channels)
        .insert(
          ChannelsCompanion.insert(
            streamId: id,
            name: name,
            type: 'movie',
            categoryId: category,
            rating: Value(rating),
            searchText: Value(searchText),
            plot: Value(plot),
          ),
        );
  }

  test(
    'unindexed and fuzzy targets beyond old 6000 cap remain searchable',
    () async {
      await db.accountBatch((b) {
        for (var i = 1; i <= 6001; i++) {
          b.insert(
            db.channels,
            ChannelsCompanion.insert(
              streamId: i,
              name: 'Ordinary $i',
              type: 'movie',
              categoryId: 'normal',
              rating: const Value(9),
              searchText: Value('ordinary $i'),
            ),
          );
        }
      });
      await insert(6002, 'İnterstellar');
      expect(
        (await repo.searchChannelsByType(
          'interstellar',
          'movie',
        )).single.streamId,
        6002,
      );
      expect(
        (await repo.searchChannelsByType(
          'intersttellar',
          'movie',
        )).single.streamId,
        6002,
      );
    },
  );

  test(
    'global title ranking includes unindexed rows after indexed metadata hits',
    () async {
      await insert(
        1,
        'Documentary',
        plot: 'Interstellar',
        searchText: 'documentary interstellar',
        rating: 10,
      );
      await insert(2, 'İnterstellar', rating: 0);
      await insert(
        3,
        'İnterstellar sequel',
        searchText: 'interstellar sequel',
        rating: 9,
      );
      final hits = await repo.searchChannelsByType(
        'interstellar',
        'movie',
        limit: 2,
      );
      expect(hits.map((c) => c.streamId), [2, 3]);
    },
  );

  test(
    'short tokens, numeric sequels and SQL wildcard literals agree',
    () async {
      await insert(1, 'A B', searchText: 'a b');
      await insert(2, 'A C', searchText: 'a c');
      await insert(3, 'Toy Story 2', searchText: 'toy story 2');
      await insert(4, 'Toy Story 3', searchText: 'toy story 3');
      await insert(5, '100%_film', searchText: '100%_film');
      expect(
        (await repo.searchChannelsByType('a b', 'movie')).single.streamId,
        1,
      );
      expect(
        (await repo.searchChannelsByType(
          'toy story 2',
          'movie',
        )).single.streamId,
        3,
      );
      expect(
        (await repo.searchChannelsByType('%_', 'movie')).single.streamId,
        5,
      );
      expect(SearchNormalizer.tokens('a a b'), ['a', 'b']);
    },
  );

  test(
    'both search phases retain account, category and adult boundaries',
    () async {
      await insert(1, 'İnterstellar', category: 'hidden');
      await insert(2, 'İnterstellar', category: 'adult');
      await insert(3, 'İnterstellar', scope: root.forAccount(2));
      await insert(4, 'İnterstellar');
      for (final q in ['interstellar', 'intersttellar']) {
        expect(
          (await repo.searchChannelsByType(q, 'movie')).map((c) => c.streamId),
          [4],
        );
      }
    },
  );

  test('index worker accepts plain rows and backfills Turkish text', () async {
    await insert(1, 'Şımarık İki');
    await repo.refreshSearchIndex();
    final row = await db.select(db.channels).getSingle();
    expect(row.searchText, contains('simarik iki'));
    expect(
      (await repo.searchChannelsByType('simarik iki', 'movie')).single.streamId,
      1,
    );
  });

  test('index pass yields when playback requests a pause', () async {
    await insert(1, 'Target');
    await repo.refreshSearchIndex(shouldPause: () => true);
    expect((await db.select(db.channels).getSingle()).searchText, isNull);
  });

  test('obsolete search stops before scanning more pages', () async {
    var checks = 0;
    await insert(1, 'Target');
    final hits = await repo.searchChannelsByType(
      'target',
      'movie',
      shouldCancel: () => ++checks >= 4,
    );
    expect(hits, isEmpty);
    expect(checks, lessThanOrEqualTo(6));
    expect(
      await repo.searchChannelsByType('target', 'movie', limit: 0),
      isEmpty,
    );
  });
}
