import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/widgets/content/vod_hero_metadata.dart';

void main() {
  const channel = Channel(
    accountId: 1,
    streamId: 42,
    name: 'Film',
    type: 'movie',
    categoryId: 'movies',
    streamIcon: 'https://example.test/old-poster.jpg',
    backdropPath: 'https://example.test/old-poster.jpg',
    plot: 'Catalogue summary',
  );

  test(
    'portrait artwork stays a poster and clears a cached false backdrop',
    () {
      final result = enrichVodHero(channel, {
        'info': {
          'movie_image': 'https://example.test/new-poster.jpg',
          'plot': 'Complete synopsis',
          'genre': 'Drama',
          'rating': '8.2',
          'release_date': '2024-02-01',
        },
      });

      expect(result.streamIcon, 'https://example.test/new-poster.jpg');
      expect(result.backdropPath, isNull);
      expect(result.plot, 'Complete synopsis');
      expect(result.genre, 'Drama');
      expect(result.rating, 8.2);
      expect(result.year, '2024');
    },
  );

  test('real backdrop and cover remain separate for series', () {
    final result = enrichVodHero(channel.copyWith(type: 'series'), {
      'info': {
        'backdrop_path': ['', 'https://example.test/wide.jpg'],
        'cover': 'https://example.test/portrait.jpg',
      },
    });

    expect(result.backdropPath, 'https://example.test/wide.jpg');
    expect(result.streamIcon, 'https://example.test/portrait.jpg');
    expect(result.plot, 'Catalogue summary');
  });
}
