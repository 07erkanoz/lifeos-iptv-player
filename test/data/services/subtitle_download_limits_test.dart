import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/opensubtitles_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final ResponseBody Function(RequestOptions) body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? request,
    Future<void>? cancel,
  ) async => body(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  Dio api() => Dio()
    ..httpClientAdapter = _Adapter(
      (_) => ResponseBody.fromString(
        '{"link":"https://downloads.invalid/sub.srt","file_name":"sub.srt"}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  test(
    'subtitle file uses a separate bounded client without API credentials',
    () async {
      final download = Dio()
        ..httpClientAdapter = _Adapter((options) {
          expect(options.headers.containsKey('Api-Key'), false);
          return ResponseBody.fromString(
            '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
            200,
          );
        });
      final service = OpenSubtitlesService(
        'synthetic',
        apiClient: api(),
        downloadClient: download,
      );
      final result = await service.download(1);
      expect(result!.content, startsWith('WEBVTT'));
      expect(result.content, contains('Hello'));
    },
  );
  test('oversized chunked subtitles are rejected', () async {
    final download = Dio()
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody(
          Stream.fromIterable([
            Uint8List(1024 * 1024),
            Uint8List(1024 * 1024 + 1),
          ]),
          200,
        ),
      );
    expect(
      await OpenSubtitlesService(
        'synthetic',
        apiClient: api(),
        downloadClient: download,
      ).download(1),
      isNull,
    );
  });
}
