import 'tv_playback_config.dart';

/// Engine-local native session handle, resolved only when the URI is unique.
/// No dependence on video_player's testing-only playerId API.
class TvSubtitleController {
  const TvSubtitleController(this.playerId);
  final int playerId;
  static Future<TvSubtitleController?> resolve(String uri) async {
    final id = await TvPlaybackConfig.channel
        .invokeMethod<int>('resolveSubtitlePlayer', {'uri': uri})
        .timeout(const Duration(seconds: 3));
    return id == null ? null : TvSubtitleController(id);
  }

  Future<List<Map<String, dynamic>>> tracks() async {
    final rows = await TvPlaybackConfig.channel
        .invokeListMethod<dynamic>('getSubtitleTracks', {'playerId': playerId})
        .timeout(const Duration(seconds: 5));
    return [
      for (final row in rows ?? [])
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  Future<void> select(Map<String, dynamic>? track) => TvPlaybackConfig.channel
      .invokeMethod<void>('selectSubtitleTrack', {
        if (track != null) ...track,
        'playerId': playerId,
        if (track == null) 'off': true,
      })
      .timeout(const Duration(seconds: 5));
}
