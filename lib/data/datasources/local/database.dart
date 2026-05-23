import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Accounts, Profiles, Categories, Channels, Programs, PlaybackProgress, Favorites, Watchlist, SeriesTracking, IntroMarkers, PlotAiCache, PersonalizedPicksCache, AiCallLogs, AiFeedback, SearchHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
       await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
       if (from < 2) {
         await m.createTable(categories);
         await m.createTable(channels);
       }
       if (from < 3) {
         await m.createTable(programs);
       }
       if (from < 4) {
         await m.createTable(playbackProgress);
       }
       if (from < 5) {
         await m.addColumn(categories, categories.isHidden);
       }
       if (from < 6) {
         await m.createTable(favorites);
         await m.addColumn(channels, channels.backdropPath);
         await m.addColumn(channels, channels.youtubeTrailer);
       }
       if (from < 7) {
         await m.addColumn(channels, channels.genre);
         await m.addColumn(channels, channels.plot);
         await m.addColumn(channels, channels.director);
         await m.addColumn(channels, channels.cast);
       }
       if (from < 8) {
         await m.addColumn(channels, channels.streamUrl);
       }
       if (from < 9) {
         await m.addColumn(channels, channels.epgChannelId);
       }
       if (from < 10) {
         await m.createTable(seriesTracking);
       }
       if (from < 11) {
         await m.createTable(watchlist);
       }
       if (from < 12) {
         // Skip-Intro feature: per-series intro position markers.
         await m.createTable(introMarkers);
       }
       if (from < 13) {
         // AI plot enrichment cache (translate / summarize /
         // fillIn / detailedInfo).
         await m.createTable(plotAiCache);
       }
       if (from < 14) {
         // Dashboard "Sana Özel" personalised picks cache.
         await m.createTable(personalizedPicksCache);
       }
       if (from < 15) {
         // AI call telemetry ring buffer (Settings → Debug panel).
         await m.createTable(aiCallLogs);
       }
       if (from < 16) {
         // Per-title AI feedback ("Sevmedim" / "Bunun gibi daha").
         await m.createTable(aiFeedback);
       }
       if (from < 17) {
         // Recent / trending search queries. Client-side only —
         // never synced to a remote, so the user's search history
         // stays private to the device.
         await m.createTable(searchHistory);
       }
       if (from < 18) {
         // ───── Multiple Profiles foundation ─────
         //
         // Netflix-style per-person personas. Six existing
         // user-specific tables grow a `profileId` column; we seed
         // a "Varsayılan" profile (id=1) and every pre-existing row
         // backfills to it. Single-user installs see no behavioural
         // change — they just get one implicit profile.
         await m.createTable(profiles);
         await m.addColumn(favorites, favorites.profileId);
         await m.addColumn(playbackProgress, playbackProgress.profileId);
         await m.addColumn(watchlist, watchlist.profileId);
         await m.addColumn(seriesTracking, seriesTracking.profileId);
         await m.addColumn(aiFeedback, aiFeedback.profileId);
         await m.addColumn(searchHistory, searchHistory.profileId);

         // Seed the default profile so the FK has something to
         // point at. Idempotent: subsequent boots see id=1 already
         // present and skip via the OR IGNORE conflict resolution.
         await customStatement(
           "INSERT OR IGNORE INTO profiles (id, name, avatar_key, "
           "is_kids, created_at) VALUES (1, 'Varsayılan', 'default', "
           "0, ${DateTime.now().millisecondsSinceEpoch ~/ 1000})",
         );
       }
    },
    beforeOpen: (details) async {
      // Belt-and-braces seed: if the user nuked their DB or this is
      // a fresh install on v18+, ensure profile 1 exists before any
      // FK-bound query fires. INSERT OR IGNORE — no-op when present.
      await customStatement(
        "INSERT OR IGNORE INTO profiles (id, name, avatar_key, "
        "is_kids, created_at) VALUES (1, 'Varsayılan', 'default', "
        "0, ${DateTime.now().millisecondsSinceEpoch ~/ 1000})",
      );
    },
  );
}

QueryExecutor _openConnection() {
  return driftDatabase(name: 'lifeostv');
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  return AppDatabase();
}
