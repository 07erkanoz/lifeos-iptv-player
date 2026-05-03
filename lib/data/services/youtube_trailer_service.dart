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
