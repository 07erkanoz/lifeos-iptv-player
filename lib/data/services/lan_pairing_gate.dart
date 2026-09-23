import 'dart:convert';
import 'dart:math';

/// Local pairing credentials have a short lifetime and a bounded guess budget.
/// This does not encrypt transport; TLS/pairing-channel verification is separate.
class LanPairingGate {
  LanPairingGate({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  String? _pin;
  DateTime? _expires;
  int _remaining = 0;
  String? get pin {
    if (_remaining <= 0 || _expires == null || !_clock().isBefore(_expires!))
      return null;
    return _pin;
  }

  String start() {
    _pin = (100000 + _random.nextInt(900000)).toString();
    _expires = _clock().add(const Duration(minutes: 5));
    _remaining = 10;
    return _pin!;
  }

  void stop() {
    _pin = null;
    _expires = null;
    _remaining = 0;
  }

  bool verify(String? candidate) {
    final active = pin;
    if (active == null || candidate == null) return false;
    if (candidate == active) return true;
    _remaining--;
    return false;
  }

  static String newToken() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
  }
}
