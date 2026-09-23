import 'dart:isolate';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/utils/search_normalizer.dart';

typedef SearchCandidate = ({Channel channel, String category});
typedef SearchMatch = ({Channel channel, int score});

/// The closure captures only sendable rows and query values, never a repository,
/// database connection or widget state. Each invocation bounds CPU to one page.
Future<List<SearchMatch>> rankSearchPage(
  List<SearchCandidate> rows,
  List<String> tokens,
  String query, {
  required bool fuzzy,
}) => Isolate.run(() {
  final matches = <SearchMatch>[];
  for (final row in rows) {
    final ch = row.channel;
    final haystack =
        ch.searchText ??
        SearchNormalizer.buildHaystack(
          name: ch.name,
          categoryName: row.category,
          cast: ch.cast,
          director: ch.director,
          genre: ch.genre,
          year: ch.year,
          plot: ch.plot,
        );
    final exact = SearchNormalizer.matches(haystack, tokens);
    if (!exact &&
        (!fuzzy || !SearchNormalizer.matchesFuzzy(haystack, tokens))) {
      continue;
    }
    final title = SearchNormalizer.normalise(ch.name);
    final score = !exact
        ? 0
        : title == query
        ? 4
        : title.startsWith(query)
        ? 3
        : SearchNormalizer.matches(title, tokens)
        ? 2
        : 1;
    matches.add((channel: ch, score: score));
  }
  return matches;
});

int compareSearchMatches(SearchMatch a, SearchMatch b) {
  var order = b.score.compareTo(a.score);
  if (order != 0) return order;
  final ar = a.channel.rating;
  final br = b.channel.rating;
  order = (br != null && br.isFinite ? br : -1).compareTo(
    ar != null && ar.isFinite ? ar : -1,
  );
  if (order != 0) return order;
  order = a.channel.name.compareTo(b.channel.name);
  if (order != 0) return order;
  order = a.channel.accountId.compareTo(b.channel.accountId);
  return order != 0 ? order : a.channel.streamId.compareTo(b.channel.streamId);
}

/// Build index strings without capturing a repository's database/native handle.
Future<List<String>> buildSearchIndexPage(List<SearchCandidate> rows) =>
    Isolate.run(
      () => [
        for (final row in rows)
          SearchNormalizer.buildHaystack(
            name: row.channel.name,
            categoryName: row.category,
            cast: row.channel.cast,
            director: row.channel.director,
            genre: row.channel.genre,
            year: row.channel.year,
            plot: row.channel.plot,
          ),
      ],
    );
