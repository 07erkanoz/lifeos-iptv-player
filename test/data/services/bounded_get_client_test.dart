import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/bounded_get_client.dart';
import 'package:lifeostv/data/services/sync_budget.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';

void main() {
  test('oversize chunked response cancels without retry', () async {
    final adapter = _Adapter(
      (_, _, _) async =>
          ResponseBody(Stream.fromIterable([Uint8List(8), Uint8List(8)]), 200),
    );
    final client = BoundedGetClient(
      Dio()..httpClientAdapter = adapter,
      maxBytes: 10,
    );
    await expectLater(
      client.get<List<int>>(
        'https://synthetic.invalid',
        options: Options(responseType: ResponseType.bytes),
      ),
      throwsA(isA<SyncFailure>()),
    );
    expect(adapter.calls, 1);
  });

  test('persistent timeout makes exactly two attempts', () async {
    final adapter = _Adapter(
      (options, _, _) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = BoundedGetClient(dio, retryDelay: Duration.zero);
    await expectLater(
      client.get('https://synthetic.invalid'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 2);
  });

  test('a successful second attempt returns its response', () async {
    var count = 0;
    final adapter = _Adapter((options, _, _) async {
      if (++count == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      return ResponseBody.fromString('ok', 200);
    });
    final client = BoundedGetClient(
      Dio()..httpClientAdapter = adapter,
      retryDelay: Duration.zero,
    );
    expect((await client.get('https://synthetic.invalid')).data, 'ok');
    expect(adapter.calls, 2);
  });

  test('authentication failure is never retried', () async {
    final adapter = _Adapter(
      (_, _, _) async => ResponseBody.fromString('denied', 401),
    );
    final client = BoundedGetClient(
      Dio()..httpClientAdapter = adapter,
      retryDelay: Duration.zero,
    );
    await expectLater(
      client.get('https://synthetic.invalid'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 1);
  });

  test(
    'deadline cancels stalled transport and never starts a second attempt',
    () async {
      final cancelled = Completer<void>();
      final adapter = _Adapter((options, _, cancel) async {
        await cancel;
        cancelled.complete();
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      });
      final client = BoundedGetClient(
        Dio()..httpClientAdapter = adapter,
        timeout: const Duration(milliseconds: 80),
        retryDelay: Duration.zero,
      );
      await expectLater(
        client.get('https://synthetic.invalid'),
        throwsA(isA<SyncFailure>()),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(adapter.calls, 1);
    },
  );

  test('sync cancellation reaches an active transport', () async {
    final started = Completer<void>(), cancelled = Completer<void>();
    final adapter = _Adapter((options, _, cancel) async {
      started.complete();
      await cancel;
      cancelled.complete();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    });
    final budget = SyncBudget(const Duration(seconds: 1));
    final client = BoundedGetClient(Dio()..httpClientAdapter = adapter);
    final rejected = expectLater(
      budget.execute(() => client.get('https://synthetic.invalid')),
      throwsA(
        isA<SyncFailure>().having((e) => e.cancelled, 'cancelled', isTrue),
      ),
    );
    await started.future;
    budget.cancel();
    await rejected;
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect(adapter.calls, 1);
  });

  test(
    'expired queue entry does not start HTTP when an earlier request finishes',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final adapter = _Adapter((_, _, _) async {
        if (!started.isCompleted) started.complete();
        await release.future;
        return ResponseBody.fromString(
          '[{"stream_id":1}]',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        );
      });
      final api = XtreamApiService(Dio()..httpClientAdapter = adapter);
      final first = api.getStreams(
        'https://queue-first.invalid',
        'test',
        'secret',
        'get_live_streams',
      );
      await started.future;
      final budget = SyncBudget(const Duration(milliseconds: 60));
      await expectLater(
        budget.execute(
          () => api.getStreams(
            'https://queue-second.invalid',
            'test',
            'secret',
            'get_live_streams',
          ),
        ),
        throwsA(isA<SyncFailure>()),
      );
      release.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(adapter.calls, 1);
    },
  );

  test(
    'malformed catalogue object is an error, not an empty successful list',
    () async {
      final adapter = _Adapter(
        (_, _, _) async => ResponseBody.fromString(
          '{"error":"denied"}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      final api = XtreamApiService(Dio()..httpClientAdapter = adapter);
      await expectLater(
        api.getStreams(
          'https://malformed.invalid',
          'test',
          'secret',
          'get_vod_streams',
        ),
        throwsFormatException,
      );
      expect(adapter.calls, 1);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(
    RequestOptions,
    Stream<Uint8List>?,
    Future<void>?,
  )
  action;
  int calls = 0;
  _Adapter(this.action);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) {
    calls++;
    return action(options, stream, cancel);
  }

  @override
  void close({bool force = false}) {}
}
