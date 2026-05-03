import 'package:url_launcher/url_launcher.dart';

import 'package:lifeostv/data/datasources/local/database.dart';

/// Build a "search YouTube" URL for a VOD when no canonical trailer URL is
/// known. Lets every movie/series have a working "Watch Trailer" affordance
/// without an API key, quota, or scraping — YouTube's own search ranks the
/// best match and the user picks the right video themselves.
///
/// Adds the year (when present) and the literal token "trailer" to the
/// query, which dramatically improves first-result accuracy on YouTube.
String youtubeSearchTrailerUrl(String name, {String? year}) {
  final yearPart = (year != null && year.isNotEmpty) ? ' $year' : '';
  final query = Uri.encodeQueryComponent('$name$yearPart trailer');
  return 'https://www.youtube.com/results?search_query=$query';
}

/// Resolve the best trailer URL for a [Channel].
///
/// Order:
/// 1. Channel.youtubeTrailer if it normalizes to a real URL or video id
/// 2. YouTube search-results page for "[name] [year] trailer"
///
/// Live channels return null — trailers don't make sense for live TV.
String? trailerUrlForChannel(Channel channel) {
  if (channel.type == 'live') return null;

  final raw = channel.youtubeTrailer;
  if (raw != null && raw.trim().isNotEmpty) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    if (lower != 'null' && lower != 'n/a' && lower != 'none' && lower != '0') {
      // Bare 11-char video id → expand to a full watch URL.
      if (!trimmed.startsWith('http') &&
          RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(trimmed)) {
        return 'https://www.youtube.com/watch?v=$trimmed';
      }
      if (trimmed.startsWith('http')) return trimmed;
    }
  }

  return youtubeSearchTrailerUrl(channel.name, year: channel.year);
}

/// Convenience: open the trailer for a [Channel] in the system browser.
Future<void> openTrailerForChannel(Channel channel) async {
  final url = trailerUrlForChannel(channel);
  if (url == null) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
