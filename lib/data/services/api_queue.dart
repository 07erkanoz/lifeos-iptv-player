import 'dart:async';
import 'dart:collection';
import 'dart:math' show min;

/// Priority levels for API requests
enum ApiPriority {
  /// User-initiated actions (detail page open, play button)
  high,
  /// Background operations (EPG sync)
  normal,
  /// Prefetch operations (hero detail)
  low,
}

/// A server-friendly API request queue that ensures:
/// - Only 1 concurrent request at a time (avoids dual-connection bans)
/// - Minimum delay between requests (200ms)
/// - Priority-based ordering
/// - Deduplication of identical requests
/// - Daily API call limit (2000)
/// - Exponential backoff on 429/5xx errors
class ApiQueue {
  static final ApiQueue instance = ApiQueue._();
  ApiQueue._();

  final SplayTreeMap<int, _QueueEntry> _queue = SplayTreeMap();
  final Map<String, Completer<dynamic>> _pendingKeys = {};
  bool _isProcessing = false;
  DateTime _lastRequestTime = DateTime(2000);
  int _counter = 0;

  static const _minDelay = Duration(milliseconds: 200);

  // Daily API call limit
  static const _dailyLimit = 2000;
  int _dailyCalls = 0;
  int _dailyResetDay = 0; // Day of year when counter was last reset

  // Exponential backoff state
  int _consecutiveErrors = 0;
  static const _maxBackoffSeconds = 60;

  /// Current daily API call count
  int get dailyCalls => _dailyCalls;

  /// Whether daily limit has been reached
  bool get isLimitReached => _dailyCalls >= _dailyLimit;

  void _checkDailyReset() {
    final today = DateTime.now().day;
    if (today != _dailyResetDay) {
      _dailyCalls = 0;
      _dailyResetDay = today;
      _consecutiveErrors = 0;
    }
  }

  /// Enqueue an API request with deduplication.
  /// If a request with the same [key] is already pending, returns the same future.
  Future<T> enqueue<T>(
    String key,
    Future<T> Function() request, {
    ApiPriority priority = ApiPriority.normal,
  }) {
    // Dedup: if same key is already in queue, return existing future
    if (_pendingKeys.containsKey(key)) {
      return _pendingKeys[key]!.future as Future<T>;
    }

    final completer = Completer<T>();
    _pendingKeys[key] = completer;

    // Priority score: lower = higher priority
    // high=0, normal=1000000, low=2000000, plus counter for FIFO within same priority
    final score = priority.index * 1000000 + _counter++;

    _queue[score] = _QueueEntry(
      key: key,
      request: () async => await request(),
      completer: completer,
    );

    _processQueue();
    return completer.future;
  }

  /// Cancel all pending requests (e.g., when navigating away)
  void cancelAll() {
    for (final entry in _queue.values) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError('Cancelled');
      }
      _pendingKeys.remove(entry.key);
    }
    _queue.clear();
  }

  /// Cancel a specific pending request by key
  void cancel(String key) {
    final toRemove = <int>[];
    for (final entry in _queue.entries) {
      if (entry.value.key == key) {
        if (!entry.value.completer.isCompleted) {
          entry.value.completer.completeError('Cancelled');
        }
        toRemove.add(entry.key);
      }
    }
    for (final k in toRemove) {
      _queue.remove(k);
    }
    _pendingKeys.remove(key);
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      _checkDailyReset();

      // Check daily limit
      if (isLimitReached) {
        // Cancel remaining low-priority requests
        final toCancel = <int>[];
        for (final entry in _queue.entries) {
          if (!entry.value.completer.isCompleted) {
            entry.value.completer.completeError('Daily API limit reached ($_dailyLimit)');
          }
          _pendingKeys.remove(entry.value.key);
          toCancel.add(entry.key);
        }
        for (final k in toCancel) {
          _queue.remove(k);
        }
        break;
      }

      // Enforce minimum delay between requests
      final elapsed = DateTime.now().difference(_lastRequestTime);
      if (elapsed < _minDelay) {
        await Future.delayed(_minDelay - elapsed);
      }

      // Exponential backoff after consecutive errors
      if (_consecutiveErrors > 0) {
        final backoffSeconds = min(1 << _consecutiveErrors, _maxBackoffSeconds);
        await Future.delayed(Duration(seconds: backoffSeconds));
      }

      if (_queue.isEmpty) break;

      final firstKey = _queue.firstKey()!;
      final entry = _queue.remove(firstKey)!;

      _lastRequestTime = DateTime.now();
      _dailyCalls++;

      try {
        final result = await entry.request();
        if (!entry.completer.isCompleted) {
          entry.completer.complete(result);
        }
        _consecutiveErrors = 0; // Reset on success
      } catch (e) {
        // Check if error is a rate limit or server error for backoff
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('429') || errorStr.contains('5') && errorStr.contains('00')) {
          _consecutiveErrors++;
        }
        if (!entry.completer.isCompleted) {
          entry.completer.completeError(e);
        }
      } finally {
        _pendingKeys.remove(entry.key);
      }
    }

    _isProcessing = false;
  }
}

class _QueueEntry {
  final String key;
  final Future<dynamic> Function() request;
  final Completer<dynamic> completer;

  _QueueEntry({
    required this.key,
    required this.request,
    required this.completer,
  });
}
