import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/sync_budget.dart';
import 'package:lifeostv/data/services/sync_coordinator.dart';

void main() {
  test(
    'full refresh queued during smaller job runs once for all callers',
    () async {
      final coordinator = SyncCoordinator<int>();
      final scope = Object();
      final release = Completer<void>();
      var fullRuns = 0, active = 0, peak = 0;
      final partial = coordinator.run(
        accountId: 1,
        scope: scope,
        kind: SyncKind.tiered,
        action: (_) async {
          active++;
          peak = active;
          await release.future;
          active--;
        },
      );
      Future<void> full(void Function(int) _) async {
        fullRuns++;
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
      }

      final a = coordinator.run(
        accountId: 1,
        scope: scope,
        kind: SyncKind.full,
        action: full,
      );
      final b = coordinator.run(
        accountId: 1,
        scope: scope,
        kind: SyncKind.full,
        action: full,
      );
      release.complete();
      await Future.wait([partial, a, b]);
      expect(fullRuns, 1);
      expect(peak, 1);
    },
  );

  test('separate accounts can run without joining each other', () async {
    final coordinator = SyncCoordinator<int>();
    final release = Completer<void>();
    var started = 0;
    Future<void> action(void Function(int) _) async {
      started++;
      await release.future;
    }

    final a = coordinator.run(
      accountId: 1,
      scope: Object(),
      kind: SyncKind.full,
      action: action,
    );
    final b = coordinator.run(
      accountId: 2,
      scope: Object(),
      kind: SyncKind.full,
      action: action,
    );
    expect(started, 2);
    release.complete();
    await Future.wait([a, b]);
  });

  test(
    'cancel also rejects queued full refresh instead of silently restarting',
    () async {
      final coordinator = SyncCoordinator<int>();
      final scope = Object(), release = Completer<void>();
      var fullRuns = 0;
      final partial = expectLater(
        coordinator.run(
          accountId: 1,
          scope: scope,
          kind: SyncKind.tiered,
          action: (_) => release.future,
        ),
        throwsA(isA<SyncFailure>()),
      );
      final full = expectLater(
        coordinator.run(
          accountId: 1,
          scope: scope,
          kind: SyncKind.full,
          action: (_) async {
            fullRuns++;
          },
        ),
        throwsA(isA<SyncFailure>()),
      );
      coordinator.cancel(1);
      await Future.wait([partial, full]);
      release.complete();
      expect(fullRuns, 0);
    },
  );

  test('a disposed progress listener cannot fail a shared job', () async {
    final coordinator = SyncCoordinator<int>();
    await coordinator.run(
      accountId: 1,
      scope: Object(),
      kind: SyncKind.full,
      onProgress: (_) => throw StateError('UI disposed'),
      action: (report) async {
        report(1);
      },
    );
  });
}
