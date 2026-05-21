import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Accounts, Categories, Channels, Programs, PlaybackProgress, Favorites, Watchlist, SeriesTracking, IntroMarkers, PlotAiCache])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 13;

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
