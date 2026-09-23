import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/lan_pairing_gate.dart';

void main() {
  test('pairing expires after five minutes and cannot survive stop', () {
    var now = DateTime.utc(2026, 1, 1);
    final gate = LanPairingGate(clock: () => now);
    final pin = gate.start();
    expect(pin, matches(RegExp(r'^\d{6}$')));
    expect(gate.verify(pin), true);
    now = now.add(const Duration(minutes: 5));
    expect(gate.verify(pin), false);
    expect(gate.pin, isNull);
    final next = gate.start();
    gate.stop();
    expect(gate.verify(next), false);
  });
  test('ten wrong guesses invalidate pairing; absent credentials do not', () {
    final gate = LanPairingGate();
    final pin = gate.start();
    for (var i = 0; i < 20; i++) {
      expect(gate.verify(null), false);
    }
    expect(gate.verify(pin), true);
    for (var i = 0; i < 10; i++) {
      expect(gate.verify('wrong'), false);
    }
    expect(gate.verify(pin), false);
  });
  test('trust tokens contain 256 random bits', () {
    final tokens = List.generate(100, (_) => LanPairingGate.newToken());
    expect(tokens.toSet(), hasLength(100));
    expect(tokens.every((t) => base64Url.decode(t).length == 32), true);
  });
}
