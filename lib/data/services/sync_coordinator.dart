import 'dart:async';
import 'sync_budget.dart';

enum SyncKind { full, tiered, categories }

/// One catalogue writer per account, shared by all service/provider instances.
/// A full run satisfies a concurrent refresh. A full refresh requested during
/// a smaller run is queued once and shared by its waiters.
class SyncCoordinator<P> {
  final Duration timeout;
  final _jobs = <int, _Job<P>>{};
  SyncCoordinator({this.timeout = const Duration(minutes: 5)});

  void cancel(int accountId) => _jobs[accountId]?.budget.cancel();

  Future<void> run({
    required int accountId,
    required Object scope,
    required SyncKind kind,
    required Future<void> Function(void Function(P) report) action,
    void Function(P)? onProgress,
  }) {
    final existing = _jobs[accountId];
    if (existing != null) {
      if (identical(existing.scope, scope) &&
          (existing.kind == SyncKind.full || existing.kind == kind)) {
        existing.listen(onProgress);
        return existing.done.future;
      }
      return () async {
        try {
          await existing.done.future;
        } on SyncFailure catch (e) {
          if (e.cancelled) rethrow;
        } catch (_) {
          /* An explicit queued refresh may retry a failed job. */
        }
        await run(
          accountId: accountId,
          scope: scope,
          kind: kind,
          action: action,
          onProgress: onProgress,
        );
      }();
    }
    final job = _Job<P>(scope, kind, SyncBudget(timeout));
    _jobs[accountId] = job;
    job.listen(onProgress);
    // Install the shared future before starting any async work.
    unawaited(() async {
      try {
        await job.budget.execute(() => action(job.report));
        job.done.complete();
      } catch (e, st) {
        job.done.completeError(e, st);
      } finally {
        if (identical(_jobs[accountId], job)) _jobs.remove(accountId);
      }
    }());
    return job.done.future;
  }
}

class _Job<P> {
  final Object scope;
  final SyncKind kind;
  final SyncBudget budget;
  final done = Completer<void>();
  final listeners = <void Function(P)>[];
  P? latest;
  _Job(this.scope, this.kind, this.budget);
  void listen(void Function(P)? listener) {
    if (listener == null) return;
    listeners.add(listener);
    if (latest case final value?) {
      _notify(listener, value);
    }
  }

  void report(P progress) {
    budget.check();
    latest = progress;
    for (final listener in listeners.toList()) {
      _notify(listener, progress);
    }
  }

  void _notify(void Function(P) listener, P value) {
    try {
      listener(value);
    } catch (_) {
      /* A disposed UI cannot fail the sync. */
    }
  }
}
