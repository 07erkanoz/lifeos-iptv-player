import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves a YouTube watch URL or bare video id into a direct stream URL
/// that media_kit / mpv can open directly — no WebView, no YouTube
/// branding, plays through the same pipeline as our IPTV streams.
///
/// Used by hero billboard / hover preview to autoplay muted trailers
/// without launching an external browser.
class YouTubeTrailerService {
  YouTubeTrailerService._();
  static final YouTubeTrailerService instance = YouTubeTrailerService._();

  final YoutubeExplode _yt = YoutubeExplode();

  // 1h cache. The signed URLs YouTube returns are valid for ~6h, so an
  // hour is well within their lifetime and prevents re-extraction
  // thrash when the user keeps coming back to the same hero item.
  static const Duration _ttl = Duration(hours: 1);
  final Map<String, _CachedUrl> _cache = {};

  // Search query → resolved video id, cached for the session. Search is
  // expensive (full HTML page from YouTube + parse) and the result for
  // a given title doesn't change minute to minute. Negative results
  // also cached so missing trailers don't get retried every slide.
  static const Duration _searchTtl = Duration(hours: 6);
  final Map<String, _CachedSearch> _searchCache = {};

  // Global single-flight gate. Even when many widgets schedule
  // extractions in parallel (rapid hover across cards, hero auto-
  // rotate firing while detail page is opening, etc.) we run only
  // ONE network round-trip at a time. Cuts CPU + bandwidth spikes
  // and keeps libmpv from queuing up several concurrent decode
  // pipelines on weaker devices. Cached lookups skip the gate.
  Future<void>? _inflight;

  /// Returns a direct stream URL for [videoIdOrUrl], or null if the
  /// video can't be extracted (region lock, embed disabled, deleted,
  /// network error). Negative results are also cached so we don't
  /// hammer YouTube for known-bad ids.
  ///
  /// Prefers muxed audio+video at ≤720p — preview quality is plenty
  /// for a hero billboard and keeps bandwidth low.
  Future<String?> extractStreamUrl(String videoIdOrUrl) async {
    final id = _normalizeId(videoIdOrUrl);
    if (id == null) return null;

    final cached = _cache[id];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _ttl) {
      return cached.url;
    }

    // Serialize through the single-flight gate so we never spawn two
    // YouTube round-trips at once.
    return _serialize(() => _extractStreamUrlImpl(id));
  }

  Future<String?> _extractStreamUrlImpl(String id) async {
    // Re-check cache inside the gate — another waiter might have
    // populated it while we were queued.
    final cachedAgain = _cache[id];
    if (cachedAgain != null &&
        DateTime.now().difference(cachedAgain.fetchedAt) < _ttl) {
      return cachedAgain.url;
    }

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(id);

      // Muxed = audio+video in one stream → ideal for media_kit, no
      // demux gymnastics. Newer videos may not have muxed at all
      // (YouTube only ships muxed up to 360p these days), so we fall
      // back to video-only after.
      String? url;

      final muxedSorted = manifest.muxed.sortByVideoQuality();
      if (muxedSorted.isNotEmpty) {
        // Pick the highest muxed (typically 360p) — preview is small,
        // doesn't need 4k.
        url = muxedSorted.first.url.toString();
      } else {
        // Video-only at the lowest quality that's still presentable
        // (~480p). Audio doesn't matter — the preview is muted.
        final videoOnly = manifest.videoOnly.sortByVideoQuality();
        if (videoOnly.isNotEmpty) {
          // Lowest first since we sorted descending — pick last for low.
          url = videoOnly.last.url.toString();
        }
      }

      _cache[id] = _CachedUrl(url: url, fetchedAt: DateTime.now());
      return url;
    } catch (_) {
      _cache[id] = _CachedUrl(url: null, fetchedAt: DateTime.now());
      return null;
    }
  }

  /// Chain [task] onto the single-flight queue. Subsequent callers
  /// wait for the previous task to complete before their own runs.
  /// Failures in one task never block the queue.
  Future<T> _serialize<T>(Future<T> Function() task) async {
    final previous = _inflight;
    final completer = Completer<void>();
    _inflight = completer.future;
    try {
      if (previous != null) {
        try { await previous; } catch (_) {}
      }
      return await task();
    } finally {
      completer.complete();
      // Clear only if we're still the head — a later task may have
      // already chained on while we ran.
      if (identical(_inflight, completer.future)) {
        _inflight = null;
      }
    }
  }

  /// Resolve a stream URL by searching YouTube for [title] (+ optional
  /// [year]) + the literal "trailer" — used as a fallback when the
  /// IPTV provider doesn't ship a youtube_trailer field for the VOD.
  /// Most providers don't, so this is the path that actually lights
  /// the hero billboard up for the average library.
  ///
  /// Picks the FIRST search result (YouTube's relevance ranking is
  /// already good enough for "<movie> trailer") and runs it through
  /// the normal extractStreamUrl path.
  Future<String?> extractStreamUrlForQuery(String title, {String? year}) async {
    final yearPart = (year != null && year.isNotEmpty) ? ' $year' : '';
    final query = '$title$yearPart trailer'.trim();

    final cached = _searchCache[query];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _searchTtl) {
      if (cached.videoId == null) return null;
      return extractStreamUrl(cached.videoId!);
    }

    // Serialize search → extract through the single-flight gate.
    return _serialize(() => _extractStreamUrlForQueryImpl(query));
  }

  Future<String?> _extractStreamUrlForQueryImpl(String query) async {
    // Re-check cache inside the gate — another waiter might have
    // populated it while we were queued.
    final cachedAgain = _searchCache[query];
    if (cachedAgain != null &&
        DateTime.now().difference(cachedAgain.fetchedAt) < _searchTtl) {
      if (cachedAgain.videoId == null) return null;
      return _extractStreamUrlImpl(cachedAgain.videoId!);
    }

    try {
      final results = await _yt.search.search(query);
      // Find the first result that's actually a Video (search can
      // return playlists / channels too — those don't have an id we
      // can stream).
      String? videoId;
      for (final r in results) {
        final id = r.id.value;
        if (id.isNotEmpty) {
          videoId = id;
          break;
        }
      }
      _searchCache[query] = _CachedSearch(
        videoId: videoId,
        fetchedAt: DateTime.now(),
      );
      if (videoId == null) return null;
      return _extractStreamUrlImpl(videoId);
    } catch (_) {
      _searchCache[query] = _CachedSearch(
        videoId: null,
        fetchedAt: DateTime.now(),
      );
      return null;
    }
  }

  /// Normalize input into a canonical 11-char video id.
  /// Accepts: bare id, watch URL, youtu.be short URL, embed URL.
  /// Returns null for search URLs and other non-video inputs.
  String? _normalizeId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Bare 11-char id
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trimmed)) return trimmed;

    // Search results page can't be played
    if (trimmed.contains('/results?')) return null;

    try {
      return VideoId.parseVideoId(trimmed);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}

class _CachedUrl {
  final String? url;
  final DateTime fetchedAt;
  _CachedUrl({required this.url, required this.fetchedAt});
}

class _CachedSearch {
  final String? videoId;
  final DateTime fetchedAt;
  _CachedSearch({required this.videoId, required this.fetchedAt});
}
