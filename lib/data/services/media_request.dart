import 'dart:convert';

/// Playback-only headers. They are never copied to artwork, EPG or AI requests.
class MediaRequest {
  const MediaRequest(this.url, this.headers);
  final String url;
  final Map<String, String> headers;

  static Map<String, String> sanitize(Object? input) {
    if (input is! Map) return const {};
    final result = <String, String>{};
    final names = <String, String>{};
    var size = 2;
    for (final entry in input.entries) {
      final name = entry.key.toString().trim();
      final value = entry.value?.toString().trim() ?? '';
      final lower = name.toLowerCase();
      if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
          value.isEmpty ||
          value.length > 8192 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
          const {
            'host',
            'content-length',
            'transfer-encoding',
            'connection',
          }.contains(lower))
        continue;
      final old = names[lower];
      final previousSize = old == null
          ? 0
          : jsonEncode({old: result[old]}).length;
      final nextSize = size - previousSize + jsonEncode({name: value}).length;
      if (nextSize > 32700) continue;
      size = nextSize;
      if (old != null) result.remove(old);
      names[lower] = name;
      result[name] = value;
      if (result.length >= 32) break;
    }
    return result;
  }

  static Map<String, String> decode(String? json) {
    if (json == null || json.length > 32768) return const {};
    try {
      return sanitize(jsonDecode(json));
    } catch (_) {
      return const {};
    }
  }

  /// VLC/Kodi suffixes are removed only when they contain header pairs.
  /// The original catalogue URL remains untouched to preserve playlist IDs.
  factory MediaRequest.parse(
    String source, {
    Map<String, String> headers = const {},
    bool nativeTv = false,
  }) {
    var url = source;
    final inline = <String, String>{};
    var separator = source.indexOf('|');
    var width = 1;
    if (separator < 0) {
      separator = source.toLowerCase().indexOf('%7c');
      width = 3;
    }
    if (separator >= 0) {
      try {
        final suffix = source.substring(separator + width);
        if (suffix.contains('=')) {
          inline.addAll(Uri.splitQueryString(suffix));
          if (sanitize(inline).isNotEmpty) url = source.substring(0, separator);
        }
      } on FormatException {
        /* Keep an unrelated literal URL intact. */
      }
    }
    return MediaRequest(
      url,
      sanitize({
        if (nativeTv) 'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
        ...headers,
        ...inline,
      }),
    );
  }
}
