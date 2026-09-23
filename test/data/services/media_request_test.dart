import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/media_request.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';

void main() {
  test('VLC and Kodi headers belong only to their own playlist entry', () {
    final rows = parseM3U('''#EXTM3U
#EXTINF:-1,First
#EXTVLCOPT:http-user-agent=ProviderPlayer
#EXTVLCOPT:http-referrer=https://example.invalid/watch
#KODIPROP:inputstream.adaptive.stream_headers=Cookie=session%3Dabc&Origin=https%3A%2F%2Fexample.invalid
https://example.invalid/live.ts
#EXTINF:-1,Second
https://example.invalid/second.ts
''');
    expect(rows.first.httpHeaders, {'User-Agent': 'ProviderPlayer', 'Referer': 'https://example.invalid/watch', 'Cookie': 'session=abc', 'Origin': 'https://example.invalid'});
    expect(rows.last.httpHeaders, isEmpty);
  });
  test('inline headers override defaults without changing the stored source', () {
    const source = 'https://example.invalid/a.mp4?token=exact|User-Agent=Provider&Cookie=x%3Dy';
    final request = MediaRequest.parse(source, nativeTv: true, headers: {'Referer': 'https://example.invalid'});
    expect(request.url, 'https://example.invalid/a.mp4?token=exact');
    expect(request.headers, {'User-Agent': 'Provider', 'Cookie': 'x=y', 'Referer': 'https://example.invalid'});
    expect(classifyStreamType(url: source), 'movie');
    expect(MediaRequest.parse('https://example.invalid/a.ts%7CUser-Agent=VLC').url, 'https://example.invalid/a.ts');
  });
  test('invalid header metadata cannot inject extra HTTP lines', () {
    expect(MediaRequest.sanitize({'Cookie': 'a=b\r\nAuthorization: leaked', 'Bad Name': 'x', 'Host': 'other', 'Content-Length': '42', 'Accept': 'video/*'}), {'Accept': 'video/*'});
    expect(MediaRequest.decode('broken'), isEmpty);
    expect(MediaRequest.parse('https://example.invalid/a%7Cb.mp4').url, 'https://example.invalid/a%7Cb.mp4');
  });
}
