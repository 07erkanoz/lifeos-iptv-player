import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';

/// Snapshot of "what does the AI need to know about this user?" used
/// by the `recommendForTonight` Gemini call.
///
/// Kept deliberately small and primitive:
///   * The whole snapshot serialises to a few kilobytes of JSON.
///   * No streams or change-notifiers — captured once when the chat
///     sheet opens, re-fetched each time the user opens it again.
///   * No mutation — once a chat session is in flight, the context
///     stays stable so follow-up questions reference the same set
///     of items.
class TonightContext {
  /// Items with non-zero playback progress that aren't finished —
  /// what the user has been actively watching. Up to 10, newest
  /// first. We send these so the AI can reason about taste from
  /// recent behaviour and avoid recommending titles already in
  /// progress.
  final List<Channel> recentlyWatched;

  /// User's bookmarks across movies + series + live. Up to 10. Lets
  /// Gemini lean into stated preferences ("kullanıcı Korean drama
  /// favorilemiş, bu yöne kayalım").
  final List<Channel> favorites;

  /// Stratified high-rated cross-section of the catalogue. AI picks
  /// recommendations *from this list* — the prompt explicitly tells
  /// it to only return ids it actually sees. This bounds Gemini's
  /// output to titles the user can actually play.
  final List<Channel> librarySample;

  /// Freshest VOD by the Xtream `added` timestamp, newest first. Sent
  /// as its own labelled pool so the AI can answer "what's new?" /
  /// "yeni filmler" — those titles are usually unrated and never make
  /// it into the rating-sorted [librarySample].
  final List<Channel> recentAdditions;

  const TonightContext({
    required this.recentlyWatched,
    required this.favorites,
    required this.librarySample,
    required this.recentAdditions,
  });
}

/// One-shot future. The chat sheet `ref.watch`es this when it opens;
/// closing the sheet doesn't auto-invalidate (so multi-turn follow-
/// ups reuse the same snapshot), but reopening triggers a fresh
/// fetch.
final tonightContextProvider = FutureProvider<TonightContext>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final repo = ref.watch(contentRepositoryProvider);

  // Recently watched — direct DB read instead of going through the
  // stream-based `watchContinueWatching` because we want a single
  // synchronous snapshot, not a subscription.
  final recentRows = await (db.select(db.channels).join([
    db.accountInnerJoin(
      db.playbackProgress,
      db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
          db.playbackProgress.type.equalsExp(db.channels.type),
    ),
  ])
        ..where(db.playbackProgress.position.isBiggerThanValue(0))
        ..orderBy([
          OrderingTerm(
              expression: db.playbackProgress.updatedAt,
              mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final recentlyWatched =
      recentRows.map((row) => row.readTable(db.channels)).toList();

  // Favourites — same shape, joined against the favorites table.
  final favRows = await (db.select(db.channels).join([
    db.accountInnerJoin(
      db.favorites,
      db.favorites.streamId.equalsExp(db.channels.streamId) &
          db.favorites.streamType.equalsExp(db.channels.type),
    ),
  ])
        ..orderBy([
          OrderingTerm(
              expression: db.favorites.addedAt, mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final favorites = favRows.map((row) => row.readTable(db.channels)).toList();

  // Library cross-section. Bumped from the 30/30 default so the chat
  // reasons over a wider slice of the catalogue — a too-small sample
  // is a big part of why the assistant felt "dumb" / kept suggesting
  // the same handful of titles.
  final librarySample = await repo.sampleLibraryForAi(
    moviesPerType: 60,
    seriesPerType: 60,
    livePerType: 20,
  );

  // Dedicated recency pool so "yeni film var mı?" works — these are
  // usually unrated and absent from the rating-sorted librarySample.
  final recentAdditions = await repo.recentAdditionsForAi(limit: 40);

  return TonightContext(
    recentlyWatched: recentlyWatched,
    favorites: favorites,
    librarySample: librarySample,
    recentAdditions: recentAdditions,
  );
});
