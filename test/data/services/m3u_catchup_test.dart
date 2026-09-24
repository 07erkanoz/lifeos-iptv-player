import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/m3u_catchup.dart';

void main() {
  final start = DateTime.utc(2026, 9, 24, 10, 5, 6);
  final end = start.add(const Duration(minutes: 45));

  test('full URL template expands UTC time and programme duration', () {
    final catchup = M3uCatchup.fromAttributes({
      'catchup': 'default',
      'catchup-source':
          'https://archive.example.invalid/{Y}/{m}/{d}/{H}/{M}/{S}?start={utc}&end={utcend}&minutes={duration:60}&seconds={duration}',
      'catchup-days': '7',
    })!;
    expect(catchup.days, 7);
    final url = catchup.buildUrl(
      liveUrl: 'https://live.example.invalid/channel.ts',
      start: start,
      end: end,
    )!;
    expect(url.path, '/2026/09/24/10/05/06');
    expect(
      url.queryParameters['start'],
      '${start.millisecondsSinceEpoch ~/ 1000}',
    );
    expect(url.queryParameters['end'], '${end.millisecondsSinceEpoch ~/ 1000}');
    expect(url.queryParameters['minutes'], '45');
    expect(url.queryParameters['seconds'], '2700');
    expect(M3uCatchup.decode(catchup.encode())?.source, catchup.source);
  });

  test('append template preserves provider URL and expands Kodi aliases', () {
    final catchup = M3uCatchup.fromAttributes({
      'catchup': 'append',
      'catchup-source': r'&start=${start}&duration=${duration}',
    })!;
    final url = catchup.buildUrl(
      liveUrl: 'https://live.example.invalid/channel.ts?token=abc',
      start: start,
      end: end,
    )!;
    expect(url.queryParameters['token'], 'abc');
    expect(
      url.queryParameters['start'],
      '${start.millisecondsSinceEpoch ~/ 1000}',
    );
    expect(url.queryParameters['duration'], '2700');
    final withoutQuery = catchup.buildUrl(
      liveUrl: 'https://live.example.invalid/channel.ts',
      start: start,
      end: end,
    )!;
    expect(
      withoutQuery.queryParameters['start'],
      '${start.millisecondsSinceEpoch ~/ 1000}',
    );
  });

  test('unsupported modes and unresolved templates are not played', () {
    expect(M3uCatchup.fromAttributes({'catchup': 'flussonic'}), isNull);
    expect(
      M3uCatchup.fromAttributes({
        'catchup': 'append',
        'catchup-source': '&start={utc}',
        'catchup-days': '0',
      }),
      isNull,
    );
    final unknown = M3uCatchup.fromAttributes({
      'catchup': 'default',
      'catchup-source': 'https://archive.example.invalid/{unknown}',
    });
    expect(unknown, isNull);
    expect(M3uCatchup.decode('{broken'), isNull);
  });
}
