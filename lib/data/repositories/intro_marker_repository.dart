import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'intro_marker_repository.g.dart';

/// Skip-Intro markers, keyed by parent series id.
///
/// A series almost always reuses the same intro across every episode,
/// so we keep exactly one row per series. The player picks the row up
/// using `widget.parentStreamId` (the series-level channel id), and the
/// same `(start, end)` range applies to every episode the user opens
/// from that series.
class IntroMarkerRepository {
  final AppDatabase _db;

  IntroMarkerRepository(this._db);

  /// Return the marker for [seriesId], or `null` if the user hasn't
  /// flagged this series' intro yet.
  Future<IntroMarker?> getMarker(int seriesId) async {
    return (_db.select(_db.introMarkers)
          ..where((tbl) => tbl.seriesId.equals(seriesId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Watch the marker for [seriesId]. Emits `null` when no row exists,
  /// then the new value once the user marks or updates one. The player
  /// listens to this so the "Skip Intro" button appears the instant
  /// the user finishes marking, without a reload.
  Stream<IntroMarker?> watchMarker(int seriesId) {
    return (_db.select(_db.introMarkers)
          ..where((tbl) => tbl.seriesId.equals(seriesId))
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Upsert a `(start, end)` range for [seriesId].
  ///
  /// Both timestamps are episode-timeline milliseconds. We assume the
  /// caller has already validated that `end > start` and that neither
  /// is negative — the UI does that before saving.
  Future<void> setMarker(
    int seriesId, {
    required int introStartMs,
    required int introEndMs,
  }) async {
    await _db.into(_db.introMarkers).insert(
          IntroMarkersCompanion.insert(
            seriesId: seriesId,
            introStartMs: introStartMs,
            introEndMs: introEndMs,
            updatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Remove the marker for [seriesId] entirely. Used when the user
  /// taps "Bu intro yanlış işaretlenmiş" so the next episode starts
  /// clean.
  Future<void> clearMarker(int seriesId) async {
    await (_db.delete(_db.introMarkers)
          ..where((tbl) => tbl.seriesId.equals(seriesId)))
        .go();
  }
}

@riverpod
IntroMarkerRepository introMarkerRepository(Ref ref) {
  return IntroMarkerRepository(ref.watch(appDatabaseProvider));
}

/// Reactive marker for a given series.
///
/// Hand-rolled `StreamProvider.family` instead of `@riverpod` codegen
/// because riverpod_generator (4.x) throws `InvalidTypeException` when
/// the stream's element type comes from a `part`-imported drift
/// generated class — it can't resolve `IntroMarker?` during analysis.
/// Manual provider sidesteps that and gives us the same surface
/// (`ref.watch(introMarkerProvider(seriesId))`).
final introMarkerProvider =
    StreamProvider.family<IntroMarker?, int>((ref, seriesId) {
  final repo = ref.watch(introMarkerRepositoryProvider);
  return repo.watchMarker(seriesId);
});
