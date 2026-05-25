import 'package:drift/drift.dart';

/// User personas — Netflix-style "who's watching" model.
///
/// Multiple profiles per account let a household share one IPTV
/// subscription but keep favourites / history / AI taste signals
/// separate. A father's "Sana Özel" rail isn't polluted by a
/// child's afternoon cartoons; the AI sees a clean per-person
/// signal.
///
/// Schema notes:
///   * The DB always has at least one profile — Drift's v18 migration
///     seeds a "Varsayılan" row with id=1 so existing single-user
///     installs upgrade in place without losing data (every existing
///     favourite / progress row gets profile_id=1 by default).
///   * `isKids=true` profiles can be PIN-locked when switching away
///     from them (parents leaving the room). The shared
///     [Accounts.password] / parental PIN setting is reused.
///   * `avatarKey` is a stable identifier into a fixed asset map
///     ('cat' / 'panda' / 'rocket' / etc.) so we never ship per-row
///     image blobs.
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get avatarKey => text().withDefault(const Constant('default'))();
  BoolColumn get isKids => boolean().withDefault(const Constant(false))();
  /// Optional 4-digit PIN gating the switch INTO this profile. Set
  /// only on kids profiles by parents; null elsewhere.
  TextColumn get pin => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

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
  /// Owning profile. Drift v18 migration backfills every existing row
  /// to profileId=1 (the seeded "Varsayılan" profile) so single-user
  /// installs upgrade in place. Added to the primary key so the same
  /// title can independently appear in two profiles' favourites.
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {streamId, streamType, profileId};
}

class PlaybackProgress extends Table {
  IntColumn get streamId => integer()(); // References Channels.streamId
  TextColumn get type => text()(); // 'movie' or 'series'
  IntColumn get position => integer()(); // in milliseconds
  IntColumn get duration => integer()(); // in milliseconds
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  /// Owning profile. See [Favorites.profileId] for rationale.
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {streamId, type, profileId};
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
  /// Owning profile. See [Favorites.profileId].
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {streamId, streamType, profileId};
}

/// Tracks episode counts for watched series to detect new episodes
class SeriesTracking extends Table {
  IntColumn get seriesId => integer()(); // References Channels.streamId
  IntColumn get knownEpisodeCount => integer()(); // Last known total episode count
  IntColumn get newEpisodeCount => integer().withDefault(const Constant(0))(); // New episodes since last check
  BoolColumn get hasNewEpisodes => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastCheckedAt => dateTime().withDefault(currentDateAndTime)();
  /// Owning profile. Different profiles can be at different episode
  /// counts on the same series — kids may finish a season faster
  /// than the parent.
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {seriesId, profileId};
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
/// AI "Similar to this" rail cache.
///
/// The detail page's AiSimilarSection runs a 500-item Gemini prompt
/// every time the user opens a title — 5-10 seconds on Flash 2.5.
/// Most users reopen the same title multiple times in a session, so
/// caching the result is the highest-ROI latency fix.
///
/// One row per (streamId, type) — the AI's grouped recommendations
/// stored as JSON. `sourceHash` covers the inputs that would change
/// the AI's answer (the user's recent favourites for the type) so a
/// new favourite invalidates older rows on the next read.
///
/// TTL is enforced at read time (7 days). The table is small enough
/// that we don't bother with proactive eviction.
class AiSimilarCache extends Table {
  /// `Channel.streamId` of the title the user opened.
  IntColumn get streamId => integer()();

  /// `Channel.type` — movie / series / live. Same id can coexist
  /// across types in some Xtream catalogues, so it's part of the PK.
  TextColumn get type => text()();

  /// JSON-encoded `[{label, items: [{streamId, reason}, ...]}, ...]`
  /// — the SimilarGroup payload, ready to be deserialised straight
  /// into the existing UI.
  TextColumn get payloadJson => text()();

  /// Fingerprint of the inputs that would change the AI's answer:
  /// current title + favourites-snapshot-hash + prompt-version.
  /// Mismatch on read forces a refresh.
  TextColumn get sourceHash => text()();

  DateTimeColumn get generatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {streamId, type};
}

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

/// User feedback on AI-surfaced items.
///
/// Each row is one explicit action — `dislike` or `moreLike` — the
/// user took on a recommendation card across any AI surface (chat,
/// "Sana Özel", mood rail, weekly digest, hero). The same (streamId,
/// type, action) triple can only appear once: toggling a dislike on
/// then off deletes the row rather than inserting a counter-action.
///
/// Read by every AI provider before the Gemini call:
///   * `dislike` rows → streamId excluded from candidate pools and
///     from the prompt entirely. AI never re-surfaces a disliked
///     title.
///   * `moreLike` rows → fed into the prompt as a stronger taste
///     signal ("user marked these as 'more like this'") so the AI
///     leans toward similar items.
///
/// Stays local; never leaves the device. Privacy-sensitive (a
/// dislike list is a preference fingerprint).
class AiFeedback extends Table {
  IntColumn get streamId => integer()();
  TextColumn get type => text()(); // 'movie' / 'series' / 'live'

  /// One of: 'dislike', 'moreLike'.
  ///
  /// `dislike` — never show in any AI surface again. Hard filter.
  /// `moreLike` — boost in AI prompts as a taste anchor. Soft signal.
  ///
  /// "Hide for now" stays in-memory in the rail; not persisted.
  TextColumn get action => text()();

  /// Optional feature tag — useful for analytics ("most disliked
  /// rail = mood"). Nullable because some feedback comes from
  /// generic surfaces. Not used in filtering.
  TextColumn get feature => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  /// Owning profile. Feedback (dislike / moreLike) is per-person —
  /// the father saying "show me less of this" must not affect the
  /// child's rail.
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {streamId, type, action, profileId};
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
/// Recent / trending search queries. Powers the search screen's
/// "Son aramalar" chip row + "Popüler aramalar" suggestions.
///
/// We keep this client-side (no remote sync) so the user's search
/// history never leaves the device. The trending side is computed
/// from the same table with a 7-day rolling window — there is no
/// global "trending across all users" feed; that would require a
/// server and is intentionally out of scope.
///
/// Rows are upserted on every successful search (composite PK on
/// `query` so the same term collapses into one entry whose
/// `lastUsedAt` keeps advancing and `useCount` keeps incrementing).
/// We cap the table at ~200 rows via repository-side cleanup; this
/// is cheap to query for a chip row and short-lived in practice
/// because users repeat queries.
class SearchHistory extends Table {
  /// Normalised search query — lower-cased, trimmed, multi-space
  /// collapsed. Display layer re-cases for the chip label.
  TextColumn get query => text()();

  /// Last time this query was submitted. Drives the "recent" sort.
  DateTimeColumn get lastUsedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// How many times this query has been submitted. Drives the
  /// "trending" sort within the rolling 7-day window.
  IntColumn get useCount => integer().withDefault(const Constant(1))();

  /// Owning profile. Search history is private to each profile — a
  /// kid's chip rail shouldn't show the parent's "korku gerilim"
  /// queries.
  IntColumn get profileId =>
      integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {query, profileId};
}

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
