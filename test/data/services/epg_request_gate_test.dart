import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/epg_request_gate.dart';

void main() {
  test('coalesces account/channel, isolates accounts, retries failed loads', () async {
    var now = DateTime(2026);
    final gate = EpgRequestGate(now: () => now);
    final complete = Completer<bool>();
    var calls = 0;
    final first = gate.request(1, 7, () { calls++; return complete.future; });
    final second = gate.request(1, 7, () async { calls++; return true; });
    expect(identical(first, second), true);
    await gate.request(2, 7, () async { calls++; return true; });
    expect(calls, 2);
    complete.complete(false);
    await first;
    await gate.request(1, 7, () async { calls++; return true; });
    expect(calls, 2);
    now = now.add(const Duration(seconds: 31));
    await gate.request(1, 7, () async { calls++; return true; });
    expect(calls, 3);
    now = now.add(const Duration(minutes: 6));
    await gate.request(1, 7, () async { calls++; throw StateError('offline'); });
    expect(calls, 4);
    now = now.add(const Duration(seconds: 31));
    await gate.request(1, 7, () async { calls++; return true; });
    expect(calls, 5);
  });
}
