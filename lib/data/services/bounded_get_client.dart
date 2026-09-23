import 'dart:async';
import 'package:dio/dio.dart';
import 'sync_budget.dart';

/// At most two GET attempts within one wall-clock budget. Never recursively
/// calls a Dio error interceptor; cancellation and non-transient errors stop.
class BoundedGetClient {
  final Dio dio;
  final Duration timeout;
  final Duration retryDelay;
  final int? maxBytes;
  BoundedGetClient(
    this.dio, {
    this.timeout = const Duration(seconds: 75),
    this.maxBytes,
    this.retryDelay = const Duration(milliseconds: 400),
  });

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final budget = SyncBudget.current;
    final clock = Stopwatch()..start();
    for (var attempt = 0; ; attempt++) {
      budget?.check();
      var left = timeout - clock.elapsed;
      if (budget != null && budget.remaining < left) left = budget.remaining;
      if (left <= Duration.zero) {
        throw const SyncFailure('Sunucu isteği süre sınırına ulaştı.');
      }
      final token = CancelToken();
      var oversized = false;
      unawaited(
        budget?.cancelToken.whenCancel.then((_) => token.cancel('Sync ended')),
      );
      try {
        final response = await dio
            .get<T>(
              path,
              queryParameters: queryParameters,
              options: options,
              cancelToken: token,
              onReceiveProgress: maxBytes == null
                  ? null
                  : (received, total) {
                      if (received > maxBytes! || total > maxBytes!) {
                        oversized = true;
                        token.cancel('Response size limit');
                      }
                    },
            )
            .timeout(
              left,
              onTimeout: () {
                token.cancel('Request deadline');
                throw const SyncFailure('Sunucu isteği süre sınırına ulaştı.');
              },
            );
        if (oversized) {
          throw const SyncFailure('İndirilen liste boyut sınırını aştı.');
        }
        budget?.check();
        return response;
      } on DioException catch (error) {
        if (oversized) {
          throw const SyncFailure('İndirilen liste boyut sınırını aştı.');
        }
        final status = error.response?.statusCode;
        final transient =
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.connectionError ||
            status == 429 ||
            status == 500 ||
            status == 502 ||
            status == 503 ||
            status == 504;
        if (attempt >= 1 || !transient || token.isCancelled) rethrow;
        budget?.check();
        if (timeout - clock.elapsed <= retryDelay ||
            (budget != null && budget.remaining <= retryDelay)) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
