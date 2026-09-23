import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/utils/sort_mode.dart';

/// Build a Channel row by hand. Drift's data classes are immutable so we go
/// through the constructor; the fields we care about for sort tests are
/// `name`, `rating` and `added` — everything else is filler.
Channel _ch({required int id, required String name, double? rating}) {
  return Channel(accountId: 0,
    streamId: id,
    name: name,
    type: 'movie',
    categoryId: 'cat',
    streamIcon: null,
    rating: rating,
    year: null,
    added: null,
    backdropPath: null,
    youtubeTrailer: null,
    genre: null,
    plot: null,
    director: null,
    cast: null,
    streamUrl: null,
    epgChannelId: null,
  );
}

void main() {
  group('sortChannels', () {
    final input = [
      _ch(id: 1, name: 'Charlie', rating: 7.5),
      _ch(id: 2, name: 'alpha', rating: null),
      _ch(id: 3, name: 'Bravo', rating: 9.1),
      _ch(id: 4, name: 'delta', rating: 0),
    ];

    test('recent is a no-op (returns input order, fresh list)', () {
      final out = sortChannels(input, SortMode.recent);
      expect(out.map((c) => c.streamId).toList(), [1, 2, 3, 4]);
      // Must not be the same reference — callers expect to mutate freely.
      expect(identical(out, input), isFalse);
    });

    test('rating sorts descending; null rating sinks to bottom', () {
      final out = sortChannels(input, SortMode.rating);
      expect(out.map((c) => c.streamId).toList(), [3, 1, 4, 2]);
    });

    test('name sorts case-insensitively (Turkish letters not normalized)', () {
      final out = sortChannels(input, SortMode.name);
      // alpha < Bravo < Charlie < delta — toLowerCase() puts them all in [a..z]
      // so the order is purely alphabetic regardless of original case.
      expect(out.map((c) => c.name).toList(), ['alpha', 'Bravo', 'Charlie', 'delta']);
    });

    test('empty list stays empty for every mode', () {
      for (final m in SortMode.values) {
        expect(sortChannels(<Channel>[], m), isEmpty);
      }
    });
  });
}
