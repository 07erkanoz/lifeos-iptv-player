import 'package:drift/drift.dart';

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'xtream', 'm3u'
  TextColumn get url => text()();
  TextColumn get username => text().nullable()();
  TextColumn get password => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Categories extends Table {
  TextColumn get id => text()(); // category_id from API
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'movie', 'series', 'live'
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id, type};
}

class Channels extends Table {
  IntColumn get streamId => integer()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'movie', 'series', 'live'
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get streamIcon => text().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get year => text().nullable()();
  TextColumn get added => text().nullable()(); // timestamp from API
  TextColumn get backdropPath => text().nullable()(); // landscape image from detail API
  TextColumn get youtubeTrailer => text().nullable()(); // YouTube trailer URL/ID
  TextColumn get genre => text().nullable()(); // comma-separated genres
  TextColumn get plot => text().nullable()(); // synopsis/description
  TextColumn get director => text().nullable()();
  TextColumn get cast => text().nullable()(); // comma-separated cast
  TextColumn get streamUrl => text().nullable()(); // Direct stream URL (M3U accounts only)
  TextColumn get epgChannelId => text().nullable()(); // EPG channel ID for XMLTV matching (tvg-id from M3U, epg_channel_id from Xtream)

  @override
  Set<Column> get primaryKey => {streamId, type};
}

class Programs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get channelId => integer().references(Channels, #streamId)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get stop => dateTime()();
  
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (channel_id) REFERENCES channels (stream_id)'
  ];
}

class Favorites extends Table {
  IntColumn get streamId => integer()();
  TextColumn get streamType => text()(); // 'movie', 'series', 'live'
  TextColumn get name => text()();
  TextColumn get thumbnail => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, streamType};
}

class PlaybackProgress extends Table {
  IntColumn get streamId => integer()(); // References Channels.streamId
  TextColumn get type => text()(); // 'movie' or 'series'
  IntColumn get position => integer()(); // in milliseconds
  IntColumn get duration => integer()(); // in milliseconds
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {streamId, type};
}

/// "Save for later" list — distinct from Favorites which is "things I love
/// and want quick access to". Watchlist is "things I plan to watch but
/// haven't yet". Mirrors Favorites' shape so the UI can reuse PosterCard.
class Watchlist extends Table {
  IntColumn get streamId => integer()();
  TextColumn get streamType => text()(); // 'movie' or 'series' (live makes no sense here)
  TextColumn get name => text()();
  TextColumn get thumbnail => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, streamType};
}

/// Tracks episode counts for watched series to detect new episodes
class SeriesTracking extends Table {
  IntColumn get seriesId => integer()(); // References Channels.streamId
  IntColumn get knownEpisodeCount => integer()(); // Last known total episode count
  IntColumn get newEpisodeCount => integer().withDefault(const Constant(0))(); // New episodes since last check
  BoolColumn get hasNewEpisodes => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastCheckedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {seriesId};
}

/// Per-series intro position markers used to drive the "Skip Intro"
/// affordance in the player. A series usually has a fixed-length intro
/// reused across every episode, so we store *one* marker per series and
/// apply it to every episode of that series.
///
/// `introStartMs` / `introEndMs` are positions in milliseconds within
/// the episode timeline. We deliberately keep this table small and
/// independent of [PlaybackProgress] so the marker isn't lost when the
/// user clears watch history.
class IntroMarkers extends Table {
  /// References [Channels.streamId] for the *parent series*, not an
  /// individual episode. Comes from `widget.parentStreamId` in the
  /// player route.
  IntColumn get seriesId => integer()();
  IntColumn get introStartMs => integer()();
  IntColumn get introEndMs => integer()();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {seriesId};
}
