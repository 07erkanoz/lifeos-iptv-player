import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

void main() {
  test('two distinct M3U channels collide in production identity function', () {
    final a = stableM3uChannelId(url: 'https://example.invalid/18310.ts', name: 'Channel 18310');
    final b = stableM3uChannelId(url: 'https://example.invalid/33232.ts', name: 'Channel 33232');
    expect(a, 799436981);
    expect(b, a);
  });
  test('quoted attribute comma becomes part of the parsed display name', () {
    final entries = parseM3U('#EXTM3U\n#EXTINF:-1 group-title="News, Sports",Actual Channel\nhttps://example.invalid/1.ts\n');
    expect(entries.single.name, 'Sports",Actual Channel');
  });
  test('M3U VOD identity is different from player URL-derived identity', () {
    final id = stableM3uChannelId(url: 'https://example.invalid/movie.mp4', name: 'Film');
    final playerId = int.tryParse('https://example.invalid/movie.mp4'.split('/').last.split('.').first);
    expect(id, isNonNegative);
    expect(playerId, isNull);
  });
  test('reserved credential characters alter stream URL structure', () {
    final url = Uri.parse(StreamUrlBuilder.movie('https://example.invalid', 'user', 'p#q', 42));
    expect(url.path, '/movie/user/p');
    expect(url.fragment, 'q/42.mkv');
  });
  test('sync mutex is per object, not shared between entry points', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SyncMetadata(prefs);
    final second = SyncMetadata(prefs);
    expect(first.tryAcquireMutex(), isTrue);
    expect(second.tryAcquireMutex(), isTrue);
  });
  test('production Xtream interceptor retries more than once after timeouts', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final container = ProviderContainer();
    var requests = 0;
    server.listen((req) async {
      requests++;
      if (requests >= 3) {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"user_info":{"auth":1}}');
        await req.response.close();
      }
    });
    try {
      final api = container.read(xtreamApiServiceProvider);
      final result = await api.authenticate('http://127.0.0.1:${server.port}', 'audit', 'synthetic');
      expect(requests, 3);
      expect(result['user_info']['auth'], 1);
    } finally {
      container.dispose();
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 95)));
}
