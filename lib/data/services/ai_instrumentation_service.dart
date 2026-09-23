import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_instrumentation_service.g.dart';

/// Telemetry wrapper for AI calls.
///
/// Every Gemini invocation is wrapped through [record] so we capture
/// latency, success, payload sizes, and error code into [AiCallLogs].
/// Prompts and responses are NEVER stored — only metrics. The data
/// stays local; surfaced in the Settings → Debug panel.
///
/// Ring buffer: the table is trimmed to the most recent 1000 entries
/// after every write. Bounded growth, no maintenance needed.
class AiInstrumentationService {
  final AppDatabase _db;

  AiInstrumentationService(this._db);

  static const int _maxRows = 1000;

  /// Wrap an AI call with timing + outcome capture.
  ///
  /// [feature] identifies the Gemini method ('recommendForYou',
  /// 'parseSearchQuery', 'chat', etc).
  /// [model] is the Gemini model string used.
  /// [run] is the actual AI call; if it returns null we record that
  /// as a soft failure (success=false, errorCode='empty_response').
  /// [candidateCount] is how many input items the AI saw.
  /// [outputCountOf] extracts how many items the AI returned (for
  /// list-shaped results — `(picks) => picks.length`).
  Future<T?> record<T>({
    required String feature,
    required String model,
    required Future<T?> Function() run,
    int candidateCount = 0,
    int Function(T value)? outputCountOf,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    T? result;
    String? errorCode;
    var success = false;
    var timedOut = false;

    try {
      if (timeout != null) {
        result = await run().timeout(timeout, onTimeout: () {
          timedOut = true;
          errorCode = 'timeout';
          return null;
        });
      } else {
        result = await run();
      }
      if (result == null) {
        errorCode ??= 'empty_response';
      } else {
        success = true;
      }
    } catch (e) {
      errorCode = _classifyError(e);
    }

    stopwatch.stop();
    final latencyMs =
        stopwatch.elapsedMilliseconds.clamp(0, 60 * 1000);
    final outputCount = (result != null && outputCountOf != null)
        ? outputCountOf(result).clamp(0, 1 << 20)
        : 0;

    // Fire-and-forget the write — telemetry must never block the
    // user-facing call returning.
    unawaited(_persist(
      feature: feature,
      model: model,
      latencyMs: latencyMs,
      success: success,
      timedOut: timedOut,
      candidateCount: candidateCount,
      outputCount: outputCount,
      errorCode: errorCode,
    ));

    return result;
  }

  Future<void> _persist({
    required String feature,
    required String model,
    required int latencyMs,
    required bool success,
    required bool timedOut,
    required int candidateCount,
    required int outputCount,
    required String? errorCode,
  }) async {
    try {
      await _db.into(_db.aiCallLogs).insert(
            AiCallLogsCompanion.insert(
              feature: feature,
              model: model,
              latencyMs: latencyMs,
              success: success,
              timedOut: Value(timedOut),
              candidateCount: Value(candidateCount),
              outputCount: Value(outputCount),
              errorCode: Value(errorCode),
            ),
          );
      // Ring-buffer trim — bounded growth.
      await _trimToMaxRows();
    } catch (_) {
      // Telemetry write failed; don't surface to the user.
    }
  }

  Future<void> _trimToMaxRows() async {
    // Cheap path: count first, only trim when we crossed the
    // ceiling, so we don't run a delete every single call.
    final count = _db.aiCallLogs.id.count();
    final row = await (_db.selectOnly(_db.aiCallLogs)..addColumns([count])).getSingle();
    if ((row.read(count) ?? 0) <= _maxRows) return;
    final cutoff = await (_db.select(_db.aiCallLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(1, offset: _maxRows)).getSingleOrNull();
    if (cutoff == null) return;
    await (_db.delete(_db.aiCallLogs)..where((t) => t.id.isSmallerOrEqualValue(cutoff.id))).go();
  }

  String _classifyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) return 'timeout';
    if (s.contains('socketexception') || s.contains('connection')) {
      return 'network';
    }
    if (s.contains('formatexception') || s.contains('json')) {
      return 'parse_fail';
    }
    if (s.contains('status: 4')) return 'http_4xx';
    if (s.contains('status: 5')) return 'http_5xx';
    return 'unknown';
  }

  /// Watch the most recent [limit] log entries — used by the debug
  /// panel. Live stream so the panel updates as new calls land.
  Stream<List<AiCallLog>> watchRecent({int limit = 100}) {
    return (_db.select(_db.aiCallLogs)
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  /// Aggregate stats per feature for the debug panel summary.
  Future<List<AiFeatureStats>> featureStats({
    Duration window = const Duration(hours: 24),
  }) async {
    final since = DateTime.now().subtract(window);
    final rows = await (_db.select(_db.aiCallLogs)
          ..where((t) => t.createdAt.isBiggerThanValue(since)))
        .get();
    final byFeature = <String, List<AiCallLog>>{};
    for (final r in rows) {
      byFeature.putIfAbsent(r.feature, () => []).add(r);
    }
    return byFeature.entries.map((e) {
      final list = e.value;
      final total = list.length;
      final successes = list.where((r) => r.success).length;
      final timeouts = list.where((r) => r.timedOut).length;
      final latencies = list.map((r) => r.latencyMs).toList()..sort();
      final p50 = latencies.isEmpty
          ? 0
          : latencies[latencies.length ~/ 2];
      final p95 = latencies.isEmpty
          ? 0
          : latencies[
              (latencies.length * 0.95).floor().clamp(0, latencies.length - 1)];
      return AiFeatureStats(
        feature: e.key,
        totalCalls: total,
        successCount: successes,
        timeoutCount: timeouts,
        latencyP50Ms: p50,
        latencyP95Ms: p95,
      );
    }).toList()
      ..sort((a, b) => b.totalCalls.compareTo(a.totalCalls));
  }
}

class AiFeatureStats {
  final String feature;
  final int totalCalls;
  final int successCount;
  final int timeoutCount;
  final int latencyP50Ms;
  final int latencyP95Ms;

  const AiFeatureStats({
    required this.feature,
    required this.totalCalls,
    required this.successCount,
    required this.timeoutCount,
    required this.latencyP50Ms,
    required this.latencyP95Ms,
  });

  double get successRate => totalCalls == 0 ? 0 : successCount / totalCalls;
}

@Riverpod(keepAlive: true)
AiInstrumentationService aiInstrumentation(Ref ref) {
  return AiInstrumentationService(ref.watch(appDatabaseProvider));
}
