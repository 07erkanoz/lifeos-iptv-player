import 'dart:async';
import 'package:dio/dio.dart';

/// Public errors deliberately contain no provider URL or account credentials.
class SyncFailure implements Exception {
  final String message;
  final bool cancelled;
  const SyncFailure(this.message, {this.cancelled = false});
  @override
  String toString() => message;
}

/// Covers queue wait, network retries and applying results, not just socket I/O.
/// A timed-out future can keep executing; every write also checks this budget.
class SyncBudget {
  static final _zoneKey = Object();
  static SyncBudget? get current => Zone.current[_zoneKey] as SyncBudget?;
  final Duration limit;
  final cancelToken = CancelToken();
  final _clock = Stopwatch();
  final _cancelled = Completer<void>();
  bool _active = true;
  SyncBudget(this.limit);

  Duration get remaining => limit - _clock.elapsed;
  void check() {
    if (!_active || _cancelled.isCompleted) {
      throw const SyncFailure('Senkronizasyon iptal edildi.', cancelled: true);
    }
    if (remaining <= Duration.zero) {
      throw const SyncFailure(
        'Senkronizasyon süre sınırına ulaştı. Yeniden deneyebilirsiniz.',
      );
    }
  }

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    cancelToken.cancel('Sync cancelled');
  }

  Future<T> execute<T>(Future<T> Function() action) async {
    _clock.start();
    try {
      return await Future.any<T>([
        runZoned(action, zoneValues: {_zoneKey: this}),
        _cancelled.future.then<T>(
          (_) => throw const SyncFailure(
            'Senkronizasyon iptal edildi.',
            cancelled: true,
          ),
        ),
      ]).timeout(
        limit,
        onTimeout: () {
          throw const SyncFailure(
            'Senkronizasyon süre sınırına ulaştı. Yeniden deneyebilirsiniz.',
          );
        },
      );
    } finally {
      _active = false;
      cancelToken.cancel('Sync finished');
      _clock.stop();
    }
  }
}
