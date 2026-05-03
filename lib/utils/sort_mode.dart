import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/data/datasources/local/database.dart';

/// User-pickable ordering for VOD grids (movies + series).
///
/// `recent` matches the existing default — content sorted by `added` desc as
/// it comes out of the repository — so users who never touch the dropdown
/// see the exact same view they did before this feature shipped.
enum SortMode {
  recent,
  rating,
  name;

  /// l10n keys to render this option in a dropdown / picker.
  String get l10nKey {
    switch (this) {
      case SortMode.recent:
        return 'sortByRecent';
      case SortMode.rating:
        return 'sortByRating';
      case SortMode.name:
        return 'sortByName';
    }
  }
}

/// Apply the picked ordering to a channel list.
///
/// Always returns a NEW list — never mutates the input — so providers /
/// stream snapshots stay safe to share across widgets.
///
/// `recent` is a no-op (DB already returns this order) so the common path
/// allocates one list and stops, no comparator work.
List<Channel> sortChannels(List<Channel> channels, SortMode mode) {
  switch (mode) {
    case SortMode.recent:
      return List<Channel>.from(channels);
    case SortMode.rating:
      final out = List<Channel>.from(channels);
      out.sort((a, b) {
        // Null / missing ratings sink to the bottom regardless of direction.
        final ar = a.rating ?? -1;
        final br = b.rating ?? -1;
        return br.compareTo(ar);
      });
      return out;
    case SortMode.name:
      final out = List<Channel>.from(channels);
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
  }
}

/// Notifier holding the current SortMode. Riverpod 3 dropped `StateProvider`,
/// so we use a tiny Notifier instead. Two separate providers (movie / series)
/// so users can sort movies one way and series another.
class _SortModeNotifier extends Notifier<SortMode> {
  @override
  SortMode build() => SortMode.recent;

  // ignore: use_setters_to_change_properties
  void set(SortMode mode) => state = mode;
}

final movieSortModeProvider =
    NotifierProvider<_SortModeNotifier, SortMode>(_SortModeNotifier.new);

final seriesSortModeProvider =
    NotifierProvider<_SortModeNotifier, SortMode>(_SortModeNotifier.new);
