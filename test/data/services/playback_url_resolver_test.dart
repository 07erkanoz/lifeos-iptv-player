import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/playback_url_resolver.dart';

void main() {
  final xtream = Account(
    id: 1,
    name: 'test',
    type: 'xtream',
    url: 'https://provider.invalid',
    username: 'user',
    password: 'p#q',
    isActive: true,
    createdAt: DateTime(2026),
  );
  Channel movie({String? url}) => Channel(
    streamId: 42,
    name: 'Film',
    type: 'movie',
    categoryId: '1',
    streamUrl: url,
  );
  var calls = 0;
  late PlaybackUrlResolver resolver;
  setUp(() {
    calls = 0;
    resolver = PlaybackUrlResolver((base, user, password, id) async {
      calls++;
      expect(id, 42);
      return {
        'movie_data': {'container_extension': 'mp4'},
      };
    });
  });

  test('legacy catalogue resolves container from movie_data', () async {
    expect(
      await resolver.resolve(xtream, movie()),
      'https://provider.invalid/movie/user/p%23q/42.mp4',
    );
    expect(calls, 1);
  });

  test('synced catalogue URL avoids another detail request', () async {
    const url = 'https://cdn.invalid/file.m4v?token=signed';
    expect(await resolver.resolve(xtream, movie(url: url)), url);
    expect(calls, 0);
  });

  test(
    'stored container uses current credentials without a detail request',
    () async {
      final channel = movie().copyWith(containerExtension: const Value('mp4'));
      final updated = xtream.copyWith(password: const Value('new#secret'));
      expect(
        await resolver.resolve(updated, channel),
        'https://provider.invalid/movie/user/new%23secret/42.mp4',
      );
      expect(calls, 0);
    },
  );

  test('fresh details direct_source wins over an older stored URL', () async {
    const direct = 'https://cdn.invalid/new?token=a%2Fb';
    expect(
      await resolver.resolve(
        xtream,
        movie(url: 'https://cdn.invalid/old'),
        vodInfo: {
          'movie_data': {'container_extension': 'mp4', 'direct_source': direct},
        },
      ),
      direct,
    );
    expect(calls, 0);
  });

  test(
    'cached display-only details still resolve a legacy playback URL',
    () async {
      final url = await resolver.resolve(
        xtream,
        movie(),
        vodInfo: {
          'info': {'genre': 'Drama', 'name': 'Film'},
        },
      );
      expect(url.endsWith('/42.mp4'), isTrue);
      expect(calls, 1);
    },
  );

  test(
    'M3U direct URL is returned unchanged without Xtream requests',
    () async {
      final m3u = xtream.copyWith(type: 'm3u');
      const url = 'https://cdn.invalid/nonnumeric-name?auth=a%2Fb';
      expect(await resolver.resolve(m3u, movie(url: url)), url);
      expect(calls, 0);
    },
  );

  test('missing M3U URL fails instead of inventing an Xtream URL', () async {
    await expectLater(
      resolver.resolve(xtream.copyWith(type: 'm3u'), movie()),
      throwsStateError,
    );
    expect(calls, 0);
  });

  test(
    'unavailable metadata retains the legacy fallback with escaped credentials',
    () async {
      resolver = PlaybackUrlResolver(
        (_, _, _, _) async => throw StateError('offline'),
      );
      expect(
        await resolver.resolve(xtream, movie()),
        'https://provider.invalid/movie/user/p%23q/42.mkv',
      );
    },
  );
}
