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

  /// Get the most recently watched (unfinished) episode from a list of episode IDs.
  /// Used to show "Continue watching" button in series detail view.
  Future<PlaybackProgressData?> getLatestSeriesProgress(List<int> episodeIds) async {
    if (episodeIds.isEmpty) return null;
    return await (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.isIn(episodeIds) & tbl.type.equals('series'))
      ..where((tbl) => tbl.isFinished.equals(false))
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
}

@riverpod
PlayerRepository playerRepository(Ref ref) {
  return PlayerRepository(ref.watch(appDatabaseProvider));
}
