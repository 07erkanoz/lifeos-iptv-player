import 'dart:convert';

/// The two playlist-defined catch-up modes that provide an explicit URL
/// template. Provider-specific implicit modes need separate URL rules.
class M3uCatchup {
  final String mode;
  final String source;
  final int days;

  const M3uCatchup({
    required this.mode,
    required this.source,
    required this.days,
  });

  static M3uCatchup? fromAttributes(Map<String, String> attributes) {
    final source = attributes['catchup-source']?.trim();
    if (source == null || source.isEmpty) return null;
    final mode = (attributes['catchup'] ?? 'default').toLowerCase();
    if (mode != 'default' && mode != 'append') return null;
    if (mode == 'append' && !source.startsWith('&') && !source.startsWith('?'))
      return null;
    if (mode == 'default' &&
        !source.startsWith('http://') &&
        !source.startsWith('https://'))
      return null;
    const tokens = {
      r'${start}',
      '{utc}',
      r'${end}',
      '{utcend}',
      r'${duration}',
      '{duration}',
      '{Y}',
      '{m}',
      '{d}',
      '{H}',
      '{M}',
      '{S}',
    };
    for (final match in RegExp(r'\$?\{[^}]+\}').allMatches(source)) {
      final token = match.group(0)!;
      if (tokens.contains(token)) continue;
      final divisor = RegExp(r'^\{duration:(\d+)\}$').firstMatch(token);
      if (divisor == null || (int.tryParse(divisor.group(1)!) ?? 0) < 1) {
        return null;
      }
    }
    final rawDays = attributes['catchup-days'];
    final days = rawDays == null ? 5 : int.tryParse(rawDays);
    if (days == null || days < 1) return null;
    return M3uCatchup(mode: mode, source: source, days: days.clamp(1, 30));
  }

  String encode() => jsonEncode({'mode': mode, 'source': source, 'days': days});

  static M3uCatchup? decode(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return null;
      final mode = decoded['mode'];
      final source = decoded['source'];
      final days = decoded['days'];
      if ((mode != 'default' && mode != 'append') ||
          source is! String ||
          source.isEmpty ||
          days is! int ||
          days < 1 ||
          days > 30) {
        return null;
      }
      return fromAttributes({
        'catchup': mode,
        'catchup-source': source,
        'catchup-days': '$days',
      });
    } catch (_) {
      return null;
    }
  }

  /// Returns null for unknown tokens or unsupported URL schemes instead of
  /// issuing an accidental live request when a provider template differs.
  Uri? buildUrl({
    required String liveUrl,
    required DateTime start,
    required DateTime end,
  }) {
    final utc = start.toUtc();
    final duration = end.difference(start).inSeconds;
    if (duration <= 0) return null;
    final values = <String, String>{
      r'${start}': '${utc.millisecondsSinceEpoch ~/ 1000}',
      '{utc}': '${utc.millisecondsSinceEpoch ~/ 1000}',
      r'${end}': '${end.toUtc().millisecondsSinceEpoch ~/ 1000}',
      '{utcend}': '${end.toUtc().millisecondsSinceEpoch ~/ 1000}',
      r'${duration}': '$duration',
      '{duration}': '$duration',
      '{Y}': utc.year.toString().padLeft(4, '0'),
      '{m}': utc.month.toString().padLeft(2, '0'),
      '{d}': utc.day.toString().padLeft(2, '0'),
      '{H}': utc.hour.toString().padLeft(2, '0'),
      '{M}': utc.minute.toString().padLeft(2, '0'),
      '{S}': utc.second.toString().padLeft(2, '0'),
    };
    var expanded = source.replaceAllMapped(RegExp(r'\{duration:(\d+)\}'), (
      match,
    ) {
      final divisor = int.tryParse(match.group(1)!);
      return divisor == null || divisor < 1
          ? match.group(0)!
          : '${duration ~/ divisor}';
    });
    for (final entry in values.entries) {
      expanded = expanded.replaceAll(entry.key, entry.value);
    }
    if (RegExp(r'\$?\{[^}]+\}').hasMatch(expanded)) return null;
    String url;
    if (mode == 'append') {
      final live = Uri.tryParse(liveUrl);
      if (live == null ||
          !live.hasAuthority ||
          (live.scheme != 'http' && live.scheme != 'https'))
        return null;
      final extraQuery = expanded.substring(1);
      url = live
          .replace(
            query: live.query.isEmpty
                ? extraQuery
                : '${live.query}&$extraQuery',
          )
          .toString();
    } else {
      url = expanded;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority) {
      return null;
    }
    return uri;
  }
}
