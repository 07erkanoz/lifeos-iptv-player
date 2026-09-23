import '../datasources/local/database.dart';
import '../../utils/stream_url_builder.dart';

/// Provider-independent order used by display, resume and next/previous.
List<Map<String, dynamic>> sortedSeriesEpisodes(Map<String, dynamic>? payload) {
  final raw = payload?['episodes'];
  final seasons = raw is Map
      ? raw
      : raw is List
      ? {'1': raw}
      : const {};
  final result = <Map<String, dynamic>>[];
  final seen = <int>{};
  for (final entry in seasons.entries) {
    if (entry.value is! List) continue;
    for (final item in entry.value as List) {
      if (item is! Map) continue;
      final id = int.tryParse('${item['id']}');
      if (id == null || id < 0 || !seen.add(id)) continue;
      final season =
          int.tryParse('${item['season']}') ??
          int.tryParse('${entry.key}') ??
          1;
      final number = int.tryParse('${item['episode_num']}') ?? 0;
      result.add({
        ...item.map((key, value) => MapEntry(key.toString(), value)),
        'id': id,
        '_season': '${season < 0 ? 1 : season}',
        'episode_num': number,
      });
    }
  }
  result.sort((a, b) {
    final s = int.parse(a['_season']).compareTo(int.parse(b['_season']));
    if (s != 0) return s;
    final n = (a['episode_num'] as int).compareTo(b['episode_num'] as int);
    return n != 0 ? n : (a['id'] as int).compareTo(b['id'] as int);
  });
  return result;
}

String seriesEpisodeUrl(Account account, Map<String, dynamic> episode) {
  final direct = episode['direct_source']?.toString().trim();
  if (account.type == 'm3u') {
    if (direct == null || direct.isEmpty) {
      throw StateError('Missing playlist episode URL');
    }
    return direct;
  }
  return StreamUrlBuilder.series(
    account.url,
    account.username ?? '',
    account.password ?? '',
    episode['id'] as int,
    extension: episode['container_extension']?.toString(),
    directUrl: direct,
  );
}
