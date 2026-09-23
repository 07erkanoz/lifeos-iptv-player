import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

class _Api extends XtreamApiService {
  _Api(this.works) : super(Dio());
  final bool works;
  int calls = 0;
  String? seenUrl;
  @override
  Future<Map<String, dynamic>> authenticate(
    String url,
    String username,
    String password,
  ) async {
    calls++;
    seenUrl = url;
    if (!works) throw Exception('No Xtream API');
    return {
      'user_info': {'auth': 1, 'status': 'Active'},
    };
  }
}

void main() {
  test(
    'panel subdirectory and IPv6 survive endpoint normalization and playback',
    () {
      final base = XtreamApiService.normalizeUrl(
        'https://[::1]:8443/panel/player_api.php?username=u&password=p',
      );
      expect(base, 'https://[::1]:8443/panel');
      expect(
        XtreamApiService.normalizeUrl('server.invalid/panel/'),
        'http://server.invalid/panel',
      );
      expect(
        XtreamApiService.normalizeUrl(
          'https://server.invalid/panel/live/u/p/1.ts',
        ),
        'https://server.invalid/panel',
      );
      final stream = Uri.parse(StreamUrlBuilder.movie(base, 'a/#', 'b?@', 3));
      expect(stream.pathSegments, ['panel', 'movie', 'a/#', 'b?@', '3.mkv']);
    },
  );
  for (final works in [false, true]) {
    test('M3U conversion requires verified Xtream capability: $works', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _Api(works);
      final repo = AuthRepositoryImpl(db, api);
      const source =
          'https://server.invalid/panel/get.php?username=u&password=p&output=ts';
      await repo.loadM3U(source);
      final account = (await repo.getCurrentAccount())!;
      expect(account.type, works ? 'xtream' : 'm3u');
      expect(account.url, works ? 'https://server.invalid/panel' : source);
      expect(api.seenUrl, 'https://server.invalid/panel');
    });
  }
  test(
    'arbitrary playlist credentials do not trigger Xtream conversion',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _Api(true);
      final repo = AuthRepositoryImpl(db, api);
      await repo.loadM3U(
        'https://server.invalid/playlist.m3u?username=u&password=p',
      );
      expect(api.calls, 0);
      expect((await repo.getCurrentAccount())!.type, 'm3u');
    },
  );
}
