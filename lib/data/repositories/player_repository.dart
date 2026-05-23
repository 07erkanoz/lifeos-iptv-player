import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_repository.g.dart';

class PlayerRepository {
  final AppDatabase _db;

  PlayerRepository(this._db);

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
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<PlaybackProgressData?> getProgress(int streamId, String type) async {
    return await (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId))
      ..where((tbl) => tbl.type.equals(type))
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
      ..where((tbl) => tbl.streamId.isIn(episodeIds) & tbl.type.equals('series'))
      ..where((tbl) => tbl.position.isBiggerThanValue(0))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.updatedAt, mode: OrderingMode.desc)])
      ..limit(1)
    ).getSingleOrNull();
  }

  /// Remove a single item from history
  Future<void> deleteProgress(int streamId, String type) async {
    await (_db.delete(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).go();
  }

  /// Clear all history for a given type (movie/series/live)
  Future<void> clearAllProgress(String type) async {
    await (_db.delete(_db.playbackProgress)
      ..where((tbl) => tbl.type.equals(type))
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
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Inverse of [markEpisodesAsWatched] — clear progress rows for a
  /// season the user wants to re-watch from scratch. Same composite
  /// where-clause as the per-episode delete.
  Future<void> unmarkEpisodes(List<int> streamIds) async {
    if (streamIds.isEmpty) return;
    await (_db.delete(_db.playbackProgress)
          ..where(
              (tbl) => tbl.streamId.isIn(streamIds) & tbl.type.equals('series')))
        .go();
  }

  /// Count how many of the given episode ids are flagged as finished.
  /// Used by the "Mark season as watched" toggle to decide whether
  /// to show "Sezonu izlendi işaretle" or "İşareti kaldır" — if every
  /// episode is finished, the button flips to undo mode.
  Future<int> finishedCount(List<int> streamIds) async {
    if (streamIds.isEmpty) return 0;
    final rows = await (_db.select(_db.playbackProgress)
          ..where((tbl) =>
              tbl.streamId.isIn(streamIds) &
              tbl.type.equals('series') &
              tbl.isFinished.equals(true)))
        .get();
    return rows.length;
  }
}

@riverpod
PlayerRepository playerRepository(Ref ref) {
  return PlayerRepository(ref.watch(appDatabaseProvider));
}
