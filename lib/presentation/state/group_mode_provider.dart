import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Active set of profile ids participating in "Group" mode for AI
/// recommendations.
///
/// Semantics:
///   * Empty set → group mode disabled. AI providers fall through
///     to single-active-profile TasteProfile (the default).
///   * Non-empty set → group mode active. The TasteProfile build()
///     call aggregates these profiles' favourites / history /
///     feedback so the recommendation reflects the union of
///     everyone-currently-in-the-room.
///
/// The state is in-memory only — group mode is a "right now" choice,
/// not a persisted setting. Restarting the app or switching the
/// underlying active profile clears the group.
///
/// UX entry point: the mood selector exposes a "Grup modu" chip
/// that opens a multi-select sheet over the household's profile
/// list. Toggling the chip off clears the set.
class _GroupModeNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// Replace the entire group. Pass an empty set to disable group
  /// mode.
  void set(Set<int> ids) {
    state = Set.unmodifiable(ids);
  }

  /// Toggle a single profile id in/out of the group. Convenience
  /// for multi-select UIs where each checkbox call only knows
  /// about one id at a time.
  void toggle(int profileId) {
    final next = Set<int>.from(state);
    if (next.contains(profileId)) {
      next.remove(profileId);
    } else {
      next.add(profileId);
    }
    state = Set.unmodifiable(next);
  }

  void clear() => state = const {};
}

final groupModeProfileIdsProvider =
    NotifierProvider<_GroupModeNotifier, Set<int>>(
  _GroupModeNotifier.new,
);

/// Convenience boolean — true when group mode has 2+ profiles set
/// (a single-profile "group" is just regular mode under a different
/// name, so we treat that as off too).
final groupModeActiveProvider = Provider<bool>((ref) {
  return ref.watch(groupModeProfileIdsProvider).length >= 2;
});
