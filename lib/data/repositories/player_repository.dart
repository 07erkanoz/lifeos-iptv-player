import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_repository.g.dart';

class PlayerRepository {
  final AppDatabase _db;
  final int Function() _getActiveProfileId;

  PlayerRepository(this._db, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  Future<void> saveProgress(int streamId, String type, int position, int duration) async {
    final isFinished = (position / duration) > 0.95; // Mark as finished if > 95% watched

    await _db.into(_db.playbackProgress).insert(
      PlaybackProgressCompanion.insert(
        streamId: streamId,
        type: type,
        position: position,
        duration: duration,
        isFinished: Value(isFinished),
        updatedAt: Value(DateTime.now()),
        profileId: Value(_pid),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<PlaybackProgressData?> getProgress(int streamId, String type) async {
    return await (_db.select(_db.playbackProgress)
      ..where((tbl) =>
          tbl.streamId.equals(streamId) &
          tbl.type.equals(type) &
          tbl.profileId.equals(_pid))
    ).getSingleOrNull();
  }

  /// Get the most recently watched episode from a list of episode IDs,
  /// regardless of whether it was finished or not.
  ///
  /// The previous implementation filtered to `isFinished == false`, which
  /// gave wrong "Continue Watching" suggestions when a user had a stale
  /// partially-watched episode followed by several fully-watched ones:
  /// the partial would surface even though the user had since finished
  /// later episodes. Callers can inspect `isFinished` on the returned
  /// row and decide whether to resume mid-episode or advance to the
  /// next one.
  Future<PlaybackProgressData?> getLatestSeriesProgress(List<int> episodeIds) async {
    if (episodeIds.isEmpty) return null;
    return await (_db.select(_db.playbackProgress)
      ..where((tbl) =>
          tbl.streamId.isIn(episodeIds) &
          tbl.type.equals('series') &
          tbl.profileId.equals(_pid))
      ..where((tbl) => tbl.position.isBiggerThanValue(0))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.updatedAt, mode: OrderingMode.desc)])
      ..limit(1)
    ).getSingleOrNull();
  }

  /// Remove a single item from history
  Future<void> deleteProgress(int streamId, String type) async {
    await (_db.delete(_db.playbackProgress)
      ..where((tbl) =>
          tbl.streamId.equals(streamId) &
          tbl.type.equals(type) &
          tbl.profileId.equals(_pid))
    ).go();
  }

  /// Clear all history for a given type (movie/series/live) on the
  /// active profile only. The "clear history" UI never crosses
  /// profile boundaries.
  Future<void> clearAllProgress(String type) async {
    await (_db.delete(_db.playbackProgress)
      ..where((tbl) =>
          tbl.type.equals(type) & tbl.profileId.equals(_pid))
    ).go();
  }

  /// Bulk-mark a batch of episodes as watched (isFinished = true).
  /// Used by the "Mark season as watched" action — the user selects
  /// a whole season tab and one tap marks every episode in it. We
  /// use upsert semantics (insertOrReplace on the composite
  /// (streamId, type) PK) so this works whether or not the user had
  /// any prior partial progress on those episodes.
  ///
  /// `position`/`duration` are set to a sentinel "watched-to-end"
  /// value (1 / 1) so the existing >95% finished check stays
  /// consistent, and the row sorts to the bottom of "Continue
  /// Watching" rather than re-appearing as a half-watched item.
  Future<void> markEpisodesAsWatched(List<int> streamIds) async {
    if (streamIds.isEmpty) return;
    final now = DateTime.now();
    final pid = _pid;
    await _db.batch((batch) {
      for (final id in streamIds) {
        batch.insert(
          _db.playbackProgress,
          PlaybackProgressCompanion.insert(
            streamId: id,
            type: 'series',
            position: 1,
            duration: 1,
            isFinished: const Value(true),
            updatedAt: Value(now),
            profileId: Value(pid),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Inverse of [markEpisodesAsWatched] — clear progress rows for a
  /// season the user wants to re-watch from scratch. Scoped to the
  /// active profile.
  Future<void> unmarkEpisodes(List<int> streamIds) async {
    if (streamIds.isEmpty) return;
    await (_db.delete(_db.playbackProgress)
          ..where((tbl) =>
              tbl.streamId.isIn(streamIds) &
              tbl.type.equals('series') &
              tbl.profileId.equals(_pid)))
        .go();
  }

  /// Count how many of the given episode ids are flagged as finished
  /// for the active profile.
  Future<int> finishedCount(List<int> streamIds) async {
    if (streamIds.isEmpty) return 0;
    final rows = await (_db.select(_db.playbackProgress)
          ..where((tbl) =>
              tbl.streamId.isIn(streamIds) &
              tbl.type.equals('series') &
              tbl.isFinished.equals(true) &
              tbl.profileId.equals(_pid)))
        .get();
    return rows.length;
  }
}

@riverpod
PlayerRepository playerRepository(Ref ref) {
  ref.watch(activeProfileIdProvider);
  return PlayerRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(activeProfileIdProvider).value ?? 1,
  );
}
