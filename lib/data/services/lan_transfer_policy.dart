import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Explicit, opt-in secrets for manual transfer. Automatic sync never includes
/// these settings, including when talking to an older peer that still sends them.
class LanTransferPolicy {
  static const secretKeys = {
    'geminiApiKey',
    'opensubtitlesApiKey',
    'parentalPin',
    'parentalControlEnabled',
  };
  static Map<String, dynamic> publicSettings(Map<String, dynamic> values) => {
    for (final entry in values.entries)
      if (!secretKeys.contains(entry.key)) entry.key: entry.value,
  };
  static Map<String, dynamic> secrets(Map<String, dynamic> values) => {
    for (final key in secretKeys)
      if ((values[key] is String && (values[key] as String).isNotEmpty) ||
          (key == 'parentalControlEnabled' && values[key] is bool))
        key: values[key],
  };
}

class LanPayloadTooLarge implements Exception {
  const LanPayloadTooLarge();
}

/// Bound the total request duration as well as bytes, including chunked bodies.
/// Cancels the stream on overflow/timeout; credentials are never part of errors.
Future<Map<String, dynamic>> readLanJson(
  Stream<List<int>> stream, {
  int maxBytes = 16 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final iterator = StreamIterator(stream);
  final watch = Stopwatch()..start();
  final bytes = BytesBuilder(copy: false);
  try {
    while (true) {
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero)
        throw TimeoutException('LAN request timed out');
      if (!await iterator.moveNext().timeout(remaining)) break;
      final chunk = iterator.current;
      if (bytes.length + chunk.length > maxBytes)
        throw const LanPayloadTooLarge();
      bytes.add(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map<String, dynamic>)
      throw const FormatException('Invalid LAN payload');
    return decoded;
  } finally {
    await iterator.cancel();
  }
}
