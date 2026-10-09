import 'package:lifeostv/data/services/media_request.dart';

class EpisodeSource {
  const EpisodeSource({
    required this.streamId,
    required this.url,
    required this.title,
    this.headers = const {},
    this.season = 1,
    this.episode = 0,
    this.plot,
    this.genre,
    this.year,
    this.rating,
  });
  final int streamId;
  final String url;
  final String title;
  final Map<String, String> headers;
  final int season;
  final int episode;
  final String? plot, genre, year;
  final double? rating;

  factory EpisodeSource.fromProvider(
    Map<String, dynamic> row, {
    required String url,
    required String seriesTitle,
    String? plot,
    String? genre,
    String? year,
    double? rating,
  }) {
    final season = int.tryParse('${row['_season']}') ?? 1;
    final episode = int.tryParse('${row['episode_num']}') ?? 0;
    final name = row['title']?.toString().trim() ?? '';
    final info = row['info'] is Map ? row['info'] as Map : const {};
    return EpisodeSource(
      streamId: row['id'] as int,
      url: url,
      title: [
        seriesTitle,
        'S${season}E$episode',
        if (name.isNotEmpty && name != seriesTitle) name,
      ].where((s) => s.isNotEmpty).join(' • '),
      headers: MediaRequest.sanitize(row['http_headers']),
      season: season,
      episode: episode,
      plot: info['plot']?.toString() ?? plot,
      genre: genre,
      year: year,
      rating: rating,
    );
  }
}

class EpisodePlaylist {
  EpisodePlaylist(Iterable<EpisodeSource> sources, this.initialIndex)
    : sources = List.unmodifiable(sources) {
    if (initialIndex < 0 || initialIndex >= this.sources.length) {
      throw RangeError.index(initialIndex, this.sources);
    }
  }
  final List<EpisodeSource> sources;
  final int initialIndex;
}

/// A route keeps its backend and focus nodes while its media source changes.
/// Saves always complete under the old identity before the index changes.
class EpisodeNavigator {
  EpisodeNavigator(this.playlist) : index = playlist.initialIndex;
  final EpisodePlaylist playlist;
  int index;
  bool switching = false;
  bool closed = false;
  EpisodeSource get current => playlist.sources[index];
  EpisodeSource? get next =>
      index + 1 < playlist.sources.length ? playlist.sources[index + 1] : null;
  EpisodeSource? get previous => index > 0 ? playlist.sources[index - 1] : null;
  void close() => closed = true;

  Future<bool> move(
    int delta, {
    required Future<void> Function() save,
    required Future<void> Function(EpisodeSource) open,
  }) async {
    final target = index + delta;
    if (closed || switching || target < 0 || target >= playlist.sources.length)
      return false;
    switching = true;
    try {
      await save();
      if (closed) return false;
      index = target;
      await open(current);
      return !closed;
    } finally {
      switching = false;
    }
  }
}
