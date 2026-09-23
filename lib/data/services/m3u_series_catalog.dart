import 'dart:isolate';
import 'dart:convert';
import '../datasources/local/database.dart';

/// Keep provider/category boundaries: identical titles can be different shows,
/// language versions or quality variants in different playlist groups.
class M3uEpisodeLabel {
  final String seriesTitle;
  final int season;
  final int number;
  final bool recognized;
  const M3uEpisodeLabel(
    this.seriesTitle,
    this.season,
    this.number,
    this.recognized,
  );
}

final _episodePatterns = [
  RegExp(r'\bS(\d{1,3})[ ._-]*E(\d{1,4})\b', caseSensitive: false),
  RegExp(r'\b(\d{1,3})x(\d{1,4})\b', caseSensitive: false),
  RegExp(
    r'\b(\d{1,3})\s*\.?\s*Sezon\s*[-.: ]*\s*(\d{1,4})\s*\.?\s*B[öo]l[üu]m\b',
    caseSensitive: false,
  ),
];

M3uEpisodeLabel parseM3uEpisodeLabel(String name) {
  for (final pattern in _episodePatterns) {
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final title = name
        .substring(0, match.start)
        .replaceAll(RegExp(r'[\s._|\-–:]+$'), '')
        .trim();
    final number = int.parse(match.group(2)!);
    if (title.isNotEmpty && number > 0) {
      return M3uEpisodeLabel(title, int.parse(match.group(1)!), number, true);
    }
  }
  // Never guess that unrelated unnamed/ambiguous streams are the same show.
  return M3uEpisodeLabel(name, 1, 1, false);
}

class M3uSeries {
  final String key;
  final Channel card;
  final List<Channel> episodes;
  final Map<int, M3uEpisodeLabel> labels;
  const M3uSeries(this.key, this.card, this.episodes, this.labels);

  Map<String, dynamic> toSeriesInfo() {
    final seasons = <String, List<Map<String, dynamic>>>{};
    for (final e in episodes) {
      final label = labels[e.streamId]!;
      seasons.putIfAbsent('${label.season}', () => []).add({
        'id': e.streamId,
        'season': label.season,
        'episode_num': label.number,
        'title': e.name,
        'direct_source': e.streamUrl,
        'container_extension': e.containerExtension ?? '',
        'info': {
          'plot': e.plot ?? '',
          'movie_image': e.streamIcon ?? card.streamIcon ?? '',
        },
      });
    }
    return {
      'info': {
        'name': card.name,
        'plot': card.plot ?? '',
        'genre': card.genre ?? '',
        'cast': card.cast ?? '',
        'director': card.director ?? '',
        'rating': card.rating?.toString() ?? '',
        'cover': card.streamIcon ?? '',
        'youtube_trailer': card.youtubeTrailer ?? '',
        if (card.backdropPath != null) 'backdrop_path': [card.backdropPath],
      },
      'episodes': seasons,
      'seasons': [
        for (final n in seasons.keys) {'season_number': int.parse(n)},
      ],
    };
  }
}

class M3uSeriesCatalog {
  final List<M3uSeries> series;
  final Map<(int, int), M3uSeries> byEpisode;
  const M3uSeriesCatalog(this.series, this.byEpisode);
  M3uSeries? forChannel(Channel channel) =>
      byEpisode[(channel.accountId, channel.streamId)];
  List<Channel> cards({String? categoryId, int? limit}) => series
      .where((s) => categoryId == null || s.card.categoryId == categoryId)
      .take(limit ?? series.length)
      .map((s) => s.card)
      .toList();

  /// Keep the input order (e.g. recently watched) and collapse sibling episodes.
  List<Channel> groupCards(List<Channel> channels) {
    final seen = <String>{};
    return [
      for (final ch in channels)
        if (forChannel(ch) case final M3uSeries s)
          if (seen.add(s.key)) s.card,
    ];
  }
}

Future<M3uSeriesCatalog> buildM3uSeriesCatalogAsync(List<Channel> rows) =>
    Isolate.run(() => buildM3uSeriesCatalog(rows));

M3uSeriesCatalog buildM3uSeriesCatalog(List<Channel> rows) {
  final grouped = <(int, String, String), List<Channel>>{};
  final labels = <(int, int), M3uEpisodeLabel>{};
  for (final row in rows) {
    if (row.type != 'series' || row.streamUrl?.trim().isNotEmpty != true) {
      continue;
    }
    final label = parseM3uEpisodeLabel(row.name);
    labels[(row.accountId, row.streamId)] = label;
    final titleKey = label.recognized
        ? 'show:${label.seriesTitle.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}'
        : 'single:${row.streamId}';
    grouped
        .putIfAbsent((row.accountId, row.categoryId, titleKey), () => [])
        .add(row);
  }
  final series = <M3uSeries>[], byEpisode = <(int, int), M3uSeries>{};
  for (final group in grouped.entries) {
    final episodes = group.value
      ..sort((a, b) {
        final x = labels[(a.accountId, a.streamId)]!,
            y = labels[(b.accountId, b.streamId)]!;
        final season = x.season.compareTo(y.season);
        if (season != 0) return season;
        final number = x.number.compareTo(y.number);
        return number != 0 ? number : a.streamId.compareTo(b.streamId);
      });
    final first = episodes.first;
    final item = M3uSeries(
      jsonEncode([group.key.$1, group.key.$2, group.key.$3]),
      first.copyWith(
        name: labels[(first.accountId, first.streamId)]!.seriesTitle,
      ),
      episodes,
      {
        for (final e in episodes)
          e.streamId: labels[(e.accountId, e.streamId)]!,
      },
    );
    series.add(item);
    for (final e in episodes) {
      byEpisode[(e.accountId, e.streamId)] = item;
    }
  }
  return M3uSeriesCatalog(series, byEpisode);
}
