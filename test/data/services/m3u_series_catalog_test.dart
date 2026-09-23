import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/m3u_series_catalog.dart';
import 'package:lifeostv/data/services/series_episode.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';

Channel ch(
  int id,
  String name, {
  String category = 'Series',
  int account = 1,
  String? url,
}) => Channel(
  streamId: id,
  name: name,
  type: 'series',
  categoryId: category,
  accountId: account,
  streamUrl: url ?? 'https://example.invalid/$id.mkv?token=keep%2Fexact',
);
Account acc(String type) => Account(
  id: 1,
  name: 'Test',
  type: type,
  url: 'https://provider.invalid',
  username: 'user',
  password: 'password',
  isActive: true,
  createdAt: DateTime(2026),
);

void main() {
  test(
    'groups and orders seasons/episodes without using provider numeric filename IDs',
    () async {
      final catalog = await buildM3uSeriesCatalogAsync([
        ch(9003, 'Show S02E01 - Next season'),
        ch(9001, 'Show S01E10'),
        ch(9002, 'Show S01E02'),
      ]);
      expect(catalog.cards(), hasLength(1));
      expect(catalog.cards().single.name, 'Show');
      final episodes = sortedSeriesEpisodes(
        catalog.series.single.toSeriesInfo(),
      );
      expect(episodes.map((e) => e['id']), [9002, 9001, 9003]);
      expect(episodes.map((e) => e['_season']), ['1', '1', '2']);
      expect(
        seriesEpisodeUrl(acc('m3u'), episodes.first),
        'https://example.invalid/9002.mkv?token=keep%2Fexact',
      );
    },
  );
  test(
    'same titles in other categories/accounts stay separate; ambiguous names remain playable',
    () {
      final catalog = buildM3uSeriesCatalog([
        ch(1, 'Show S01E01'),
        ch(2, 'Show 1x02'),
        ch(3, 'Show S01E01', category: 'Other language'),
        ch(1, 'Show S01E01', account: 2),
        ch(4, 'Unknown special'),
        ch(5, 'Unknown special'),
      ]);
      expect(catalog.series, hasLength(5));
      expect(catalog.forChannel(ch(2, ''))!.episodes, hasLength(2));
      expect(
        catalog
            .forChannel(ch(4, ''))!
            .toSeriesInfo()['episodes']['1']
            .single['id'],
        4,
      );
      expect(catalog.forChannel(ch(1, '', account: 2))!.card.accountId, 2);
    },
  );
  test(
    'Turkish episode labels classify as series and support season zero specials',
    () {
      final name = 'Dizi Adı - 2. Sezon 12. Bölüm';
      final label = parseM3uEpisodeLabel(name);
      expect(
        (label.seriesTitle, label.season, label.number),
        ('Dizi Adı', 2, 12),
      );
      expect(
        classifyStreamType(url: 'https://example.invalid/film.mp4', name: name),
        'series',
      );
      expect(parseM3uEpisodeLabel('Show S00E01').season, 0);
    },
  );
  test(
    'group before paging; an old saved episode resolves the whole show after reorder',
    () {
      final rows = [
        for (var i = 1; i <= 1000; i++)
          ch(i, 'Long Show S01E${i.toString().padLeft(2, '0')}'),
        ch(2000, 'Other S01E01'),
      ];
      final catalog = buildM3uSeriesCatalog(rows.reversed.toList());
      expect(catalog.cards(limit: 2), hasLength(2));
      expect(
        catalog.forChannel(ch(500, 'Old name'))!.episodes,
        hasLength(1000),
      );
      expect(
        catalog
            .groupCards([ch(500, ''), ch(2, ''), ch(2000, '')])
            .map((c) => c.name),
        ['Long Show', 'Other'],
      );
    },
  );
  test(
    'normalization sorts unordered Xtream episodes and rejects malformed IDs',
    () {
      final episodes = sortedSeriesEpisodes({
        'episodes': {
          '2': [
            {'id': '22', 'episode_num': '2'},
            {'id': 21, 'episode_num': 1},
          ],
          '1': [
            {'id': 'junk'},
            {'id': -2},
            {'id': 11, 'episode_num': 1},
            {'id': 11, 'episode_num': 2},
          ],
        },
      });
      expect(episodes.map((e) => e['id']), [11, 21, 22]);
      expect(
        seriesEpisodeUrl(acc('xtream'), {
          ...episodes[0],
          'container_extension': 'mkv',
        }),
        'https://provider.invalid/series/user/password/11.mkv',
      );
      expect(() => seriesEpisodeUrl(acc('m3u'), episodes[0]), throwsStateError);
      expect(
        sortedSeriesEpisodes({
          'episodes': [
            {'id': 10, 'season': 3},
          ],
        }).single['_season'],
        '3',
      );
    },
  );
  test('entries without playback URLs are excluded', () {
    expect(
      buildM3uSeriesCatalog([
        ch(1, 'Show').copyWith(streamUrl: const Value(null)),
      ]).series,
      isEmpty,
    );
  });
}
