import 'dart:async';
import 'package:dio/dio.dart';

/// One operation spans every HTTP request and tool await in an AI turn.
/// Zone-local state prevents concurrent features from mixing errors/tokens.
class AiOperation {
  static final Object _zoneKey = Object();
  static AiOperation? get current => Zone.current[_zoneKey] as AiOperation?;
  final CancelToken cancelToken = CancelToken();
  String? errorCode;
  bool get cancelled => cancelToken.isCancelled;
  void cancel([String reason = 'cancelled']) {
    errorCode ??= reason;
    if (!cancelled) cancelToken.cancel(reason);
  }

  void checkActive() {
    if (cancelled) throw const AiRequestException('cancelled');
  }

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  Future<T?> withDeadline<T>(
    Future<T?> Function() action,
    Duration deadline,
  ) async {
    try {
      return await run(action)
          .then<T?>((value) => value)
          .timeout(
            deadline,
            onTimeout: () {
              cancel('timeout');
              return null;
            },
          );
    } finally {
      // Late continuations must never perform tools or commit session state.
      cancel();
    }
  }
}

class AiRequestException implements Exception {
  final String code;
  const AiRequestException(this.code);
  @override
  String toString() => 'AI request failed: $code';
}
