import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_feedback_repository.g.dart';

/// The two persisted feedback actions a user can take on an AI
/// recommendation card. Kept as a sealed enum-ish string set so the
/// table doesn't break when we add a third action later.
class AiFeedbackAction {
  static const String dislike = 'dislike';
  static const String moreLike = 'moreLike';
}

/// Repository for the per-title feedback table.
///
/// AI providers read [dislikedStreamIds] before composing a prompt to
/// strip disliked items from candidate pools, and read
/// [moreLikeStreamIds] to fold "user wants more of these" into the
/// taste signal. Writes happen from the rail card menus
/// ("Sevmedim" / "Bunun gibi daha").
class AiFeedbackRepository {
  final AppDatabase _db;
  final int Function() _getActiveProfileId;

  AiFeedbackRepository(this._db, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  /// Toggle a feedback action on the given title. Returns true when
  /// the row was added, false when it was removed (caller can show a
  /// snackbar accordingly).
  ///
  /// Toggling "dislike" automatically removes any "moreLike" on the
  /// same title and vice versa — the two are conceptually exclusive,
  /// keeping the table from accumulating contradictory signals.
  Future<bool> toggle({
    required int streamId,
    required String type,
    required String action,
    String? feature,
  }) async {
    final existing = await (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.streamId.equals(streamId) &
              t.type.equals(type) &
              t.action.equals(action) &
              t.profileId.equals(_pid))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.delete(_db.aiFeedback)
            ..where((t) =>
                t.streamId.equals(streamId) &
                t.type.equals(type) &
                t.action.equals(action)))
          .go();
      return false;
    }
    // Strip the opposite action to keep dislike/moreLike exclusive.
    final opposite = action == AiFeedbackAction.dislike
        ? AiFeedbackAction.moreLike
        : AiFeedbackAction.dislike;
    await (_db.delete(_db.aiFeedback)
          ..where((t) =>
              t.streamId.equals(streamId) &
              t.type.equals(type) &
              t.action.equals(opposite) &
              t.profileId.equals(_pid)))
        .go();
    await _db.into(_db.aiFeedback).insert(
          AiFeedbackCompanion.insert(
            streamId: streamId,
            type: type,
            action: action,
            feature: Value(feature),
            profileId: Value(_pid),
          ),
        );
    return true;
  }

  /// Stream of streamIds the user has disliked. AI providers
  /// subscribe to this and filter before sending candidates to
  /// Gemini.
  Stream<Set<int>> watchDislikedStreamIds() {
    return (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.action.equals(AiFeedbackAction.dislike) &
              t.profileId.equals(_pid)))
        .watch()
        .map((rows) => rows.map((r) => r.streamId).toSet());
  }

  /// One-shot read of disliked stream IDs.
  Future<Set<int>> getDislikedStreamIds() async {
    final rows = await (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.action.equals(AiFeedbackAction.dislike) &
              t.profileId.equals(_pid)))
        .get();
    return rows.map((r) => r.streamId).toSet();
  }

  /// One-shot read of "more like this" stream IDs — fed to AI prompts
  /// as a stronger taste anchor.
  Future<Set<int>> getMoreLikeStreamIds() async {
    final rows = await (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.action.equals(AiFeedbackAction.moreLike) &
              t.profileId.equals(_pid)))
        .get();
    return rows.map((r) => r.streamId).toSet();
  }

  /// True when the user has flagged this exact title with this
  /// exact action. Used by the rail menus to show "✓ Sevmedim" vs
  /// "Sevmedim" toggle state.
  Future<bool> hasFlag({
    required int streamId,
    required String type,
    required String action,
  }) async {
    final row = await (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.streamId.equals(streamId) &
              t.type.equals(type) &
              t.action.equals(action) &
              t.profileId.equals(_pid))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Watch the flag state for a given title. Used so the menu UI
  /// instantly reflects the new state after a toggle without an
  /// explicit refetch.
  Stream<({bool disliked, bool moreLike})> watchFlags({
    required int streamId,
    required String type,
  }) {
    return (_db.select(_db.aiFeedback)
          ..where((t) =>
              t.streamId.equals(streamId) &
              t.type.equals(type) &
              t.profileId.equals(_pid)))
        .watch()
        .map((rows) {
      var disliked = false;
      var moreLike = false;
      for (final r in rows) {
        if (r.action == AiFeedbackAction.dislike) disliked = true;
        if (r.action == AiFeedbackAction.moreLike) moreLike = true;
      }
      return (disliked: disliked, moreLike: moreLike);
    });
  }

  /// Clear ALL feedback rows for the active profile. Hook for a
  /// future "reset feedback" settings option. Scoped to the active
  /// profile so one user's "reset" doesn't nuke another's data.
  Future<void> clearAll() async {
    await (_db.delete(_db.aiFeedback)
          ..where((t) => t.profileId.equals(_pid)))
        .go();
  }
}

@Riverpod(keepAlive: true)
AiFeedbackRepository aiFeedbackRepository(Ref ref) {
  final profileId = ref.watch(activeProfileIdProvider).value ?? 1;
  return AiFeedbackRepository(
    ref.watch(appDatabaseProvider),
    () => profileId,
  );
}

/// Live-watched set of disliked stream IDs. AI rail providers
/// `ref.watch` this to filter candidates without a per-call query.
@Riverpod(keepAlive: true)
Stream<Set<int>> dislikedStreamIds(Ref ref) {
  return ref.watch(aiFeedbackRepositoryProvider).watchDislikedStreamIds();
}
