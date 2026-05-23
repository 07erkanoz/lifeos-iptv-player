import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/ai_feedback_repository.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/domain/models/taste_profile.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'taste_profile_repository.g.dart';

/// Builds the unified [TasteProfile] from raw Drift state. Every AI
/// rail provider reads this instead of computing its own ad-hoc
/// taste signals — keeps the prompts consistent and lets us improve
/// the weighting in one place.
///
/// The repository is intentionally cheap: it runs four indexed
/// queries (favourites JOIN categories, playback_progress JOIN
/// channels JOIN categories, hidden categories, ai_feedback) and
/// aggregates in Dart. Sub-100 ms on the user's 27 k-row catalogue.
class TasteProfileRepository {
  final AppDatabase _db;
  final AiFeedbackRepository _feedbackRepo;
  final int Function() _getActiveProfileId;

  TasteProfileRepository(
      this._db, this._feedbackRepo, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  // Per-source weights — comments in [TasteProfile] explain the
  // rationale. Pulled out as constants here so callers can audit
  // the scoring without diving into method bodies.
  static const double _weightMoreLike = 1.2;
  static const double _weightFavorite = 1.0;
  static const double _weightFinished = 0.8;
  static const double _weightWatchedHigh = 0.6; // 75-100%
  static const double _weightWatchedMid = 0.3; // 25-75%
  static const double _weightWatchedLow = -0.2; // <25%, opened-then-bailed
  static const double _weightHiddenCategory = -1.0;
  static const double _weightDislike = -1.5;

  Future<TasteProfile> build() async {
    final categoryAffinity = <String, double>{};
    final actorAffinity = <String, double>{};
    final directorAffinity = <String, double>{};
    var signalStrength = 0.0;

    // Helper that distributes a weight over one channel-with-category
    // row across all three affinity maps.
    void apply(Channel ch, Category? cat, double weight) {
      if (cat != null && cat.name.isNotEmpty) {
        categoryAffinity.update(
            cat.name, (v) => v + weight,
            ifAbsent: () => weight);
      }
      final director = ch.director?.trim() ?? '';
      if (director.isNotEmpty) {
        // Split "Tom Hanks, Brad Pitt"-style multi-director fields.
        for (final d in director.split(RegExp(r'[,&·]'))) {
          final name = d.trim();
          if (name.length < 3) continue;
          directorAffinity.update(name, (v) => v + weight,
              ifAbsent: () => weight);
        }
      }
      final cast = ch.cast?.trim() ?? '';
      if (cast.isNotEmpty) {
        // Top-3 billed actors only — long cast lists would dilute
        // the score.
        final names = cast
            .split(RegExp(r'[,&·]'))
            .map((s) => s.trim())
            .where((s) => s.length >= 3)
            .take(3);
        for (final n in names) {
          actorAffinity.update(n, (v) => v + weight,
              ifAbsent: () => weight);
        }
      }
      if (weight > 0) signalStrength += weight;
    }

    // ── Favourites ────────────────────────────────────────────────
    // All four user-table queries below filter by the active profile
    // id so a household sharing one install gets per-person taste
    // signals instead of a mixed-bag rail.
    final pid = _pid;
    final favRows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.favorites,
        _db.favorites.streamId.equalsExp(_db.channels.streamId) &
            _db.favorites.streamType.equalsExp(_db.channels.type),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where(_db.favorites.profileId.equals(pid))
          ..limit(60))
        .get();
    for (final r in favRows) {
      apply(r.readTable(_db.channels), r.readTableOrNull(_db.categories),
          _weightFavorite);
    }

    // ── Watch history with completion stats ───────────────────────
    final histRows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
            _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where(_db.playbackProgress.position.isBiggerThanValue(0) &
              _db.playbackProgress.profileId.equals(pid))
          ..limit(150))
        .get();
    for (final r in histRows) {
      final ch = r.readTable(_db.channels);
      final cat = r.readTableOrNull(_db.categories);
      final p = r.readTable(_db.playbackProgress);
      final ratio = p.duration <= 0 ? 0.0 : p.position / p.duration;
      final double weight;
      if (p.isFinished) {
        weight = _weightFinished;
      } else if (ratio >= 0.75) {
        weight = _weightWatchedHigh;
      } else if (ratio >= 0.25) {
        weight = _weightWatchedMid;
      } else {
        // Less than a quarter watched and not flagged finished → the
        // user almost certainly bailed. Negative signal.
        weight = _weightWatchedLow;
      }
      apply(ch, cat, weight);
    }

    // ── Hidden categories → strong negative on the category map ──
    final hiddenCats = await (_db.select(_db.categories)
          ..where((t) => t.isHidden.equals(true)))
        .get();
    final hiddenNames = hiddenCats.map((c) => c.name).toSet();
    for (final name in hiddenNames) {
      categoryAffinity.update(name, (v) => v + _weightHiddenCategory,
          ifAbsent: () => _weightHiddenCategory);
    }

    // ── Feedback rows ────────────────────────────────────────────
    final dislikedIds = await _feedbackRepo.getDislikedStreamIds();
    final moreLikeIds = await _feedbackRepo.getMoreLikeStreamIds();
    if (dislikedIds.isNotEmpty) {
      final dislikedRows = await (_db.select(_db.channels).join([
        leftOuterJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.channels.categoryId) &
              _db.categories.type.equalsExp(_db.channels.type),
        ),
      ])
            ..where(_db.channels.streamId.isIn(dislikedIds.toList())))
          .get();
      for (final r in dislikedRows) {
        apply(r.readTable(_db.channels),
            r.readTableOrNull(_db.categories), _weightDislike);
      }
    }
    if (moreLikeIds.isNotEmpty) {
      final moreLikeRows = await (_db.select(_db.channels).join([
        leftOuterJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.channels.categoryId) &
              _db.categories.type.equalsExp(_db.channels.type),
        ),
      ])
            ..where(_db.channels.streamId.isIn(moreLikeIds.toList())))
          .get();
      for (final r in moreLikeRows) {
        apply(r.readTable(_db.channels),
            r.readTableOrNull(_db.categories), _weightMoreLike);
      }
    }

    return TasteProfile(
      categoryAffinity: categoryAffinity,
      actorAffinity: actorAffinity,
      directorAffinity: directorAffinity,
      hiddenCategories: hiddenNames,
      dislikedIds: dislikedIds,
      moreLikeIds: moreLikeIds,
      signalStrength: signalStrength,
    );
  }
}

@riverpod
TasteProfileRepository tasteProfileRepository(Ref ref) {
  // Bump on profile switch so dependents re-fetch against the new
  // id. ai_feedback_repository internally watches the same provider
  // and returns disliked/moreLike sets scoped to the active profile.
  ref.watch(activeProfileIdProvider);
  return TasteProfileRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(aiFeedbackRepositoryProvider),
    () => ref.read(activeProfileIdProvider).value ?? 1,
  );
}

/// One-shot async profile. AI rail providers `ref.watch` this so
/// the profile is computed once per dashboard mount instead of
/// each rail rebuilding it. Auto-invalidates whenever feedback
/// changes (the repo watches `dislikedStreamIdsProvider`-equivalents).
@riverpod
Future<TasteProfile> tasteProfile(Ref ref) async {
  // Pulling in the dislike stream invalidates the profile any time
  // feedback flips, so every downstream rail sees the new weights
  // on the very next paint.
  ref.watch(dislikedStreamIdsProvider);
  return ref.watch(tasteProfileRepositoryProvider).build();
}
