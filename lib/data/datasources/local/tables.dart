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

/// Dashboard "Sana Özel" AI pick cache.
///
/// One singleton row keyed by id=0. Holds the most recent AI-curated
/// personalized recommendation list as JSON, plus a fingerprint of
/// the user-state we asked Gemini about (watch history + favourites
/// snapshot + prompt version). The dashboard reads this on every
/// render and rebuilds only when stale.
///
/// "Stale" means either:
///   * `generatedAt` is older than the TTL the provider enforces
///     (default 12 h), or
///   * `sourceHash` no longer matches the current user-state.
class PersonalizedPicksCache extends Table {
  /// Singleton row — always 0. Avoids accidental multi-row state.
  IntColumn get id => integer()();

  /// JSON-encoded `[{streamId: int, reason: string}, ...]` —
  /// preserves order so the rail renders best-first as Gemini
  /// ranked it.
  TextColumn get picksJson => text()();

  /// FNV-1a fingerprint of (history-ids + favourite-ids + prompt
  /// version). Mismatch on read invalidates the row.
  TextColumn get sourceHash => text()();

  DateTimeColumn get generatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI-enriched plot text cache.
///
/// One row per (streamId, mode, language) combination. The detail
/// page reads from this table before hitting Gemini, so repeated
/// visits to the same title's "Detaylı bilgi" / translate / summarize
/// link return instantly from disk rather than burning quota.
///
/// `sourceHash` is a fingerprint of the metadata + plot text we sent
/// to the model when this row was generated. If the underlying
/// Channel row updates (sync refreshes plot/cast/year/etc.) the hash
/// won't match and the cache miss triggers a fresh fetch, so stale
/// content can't outlive its source.
class PlotAiCache extends Table {
  /// `Channel.streamId` of the title this enrichment was generated for.
  IntColumn get streamId => integer()();

  /// One of the [PlotEnrichMode] enum names — kept as a string so the
  /// table doesn't break when modes are added/renamed.
  TextColumn get mode => text()();

  /// ISO-639-1 code (e.g. "tr", "en") of the response language. Cached
  /// separately per language because translate(tr) and translate(en)
  /// of the same plot are different outputs.
  TextColumn get targetLanguage => text()();

  /// The AI-produced text. Whatever `enrichPlot` returned.
  TextColumn get content => text()();

  /// Cheap fingerprint of the metadata we fed Gemini (title, year,
  /// genre, director, cast, rating, originalPlot). Changing any of
  /// those changes the hash, invalidating the row on next read.
  TextColumn get sourceHash => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, mode, targetLanguage};
}

/// Append-only ring buffer of AI call telemetry — every Gemini
/// invocation captures latency, success, payload sizes, and any
/// error code. Surfaced in Settings → Debug → AI Çağrı Geçmişi so
/// we can answer "is the AI actually working?" with measurements
/// instead of vibes.
///
/// Privacy: stays local, never leaves the device. Prompts and
/// responses are NOT stored — only timings + counts + error codes.
class AiCallLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get feature => text()();
  TextColumn get model => text()();
  IntColumn get latencyMs => integer()();
  BoolColumn get success => boolean()();
  BoolColumn get timedOut => boolean().withDefault(const Constant(false))();
  IntColumn get candidateCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get outputCount => integer().withDefault(const Constant(0))();
  TextColumn get errorCode => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
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
