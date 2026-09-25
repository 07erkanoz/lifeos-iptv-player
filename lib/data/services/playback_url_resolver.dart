import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

/// Resolves old catalogue rows that predate persisted VOD playback URLs too.
class PlaybackUrlResolver {
  PlaybackUrlResolver(this.loadVodInfo);

  final Future<Map<String, dynamic>?> Function(
    String base,
    String user,
    String password,
    int id,
  )
  loadVodInfo;

  /// Live URL construction has no network lookup. Keep it synchronous so
  /// opening a large channel list does not await once per row on the UI thread.
  String resolveLive(
    Account account,
    Channel channel, {
    StreamQuality quality = StreamQuality.auto,
  }) {
    if (channel.type != 'live') throw StateError('Not a live channel');
    if (channel.accountId != 0 && channel.accountId != account.id) {
      throw StateError('Content belongs to another account');
    }
    final stored = channel.streamUrl;
    if (account.type == 'm3u') {
      if (stored == null || stored.trim().isEmpty) {
        throw StateError('Missing playlist media URL');
      }
      return stored;
    }
    return StreamUrlBuilder.build(
      account.url,
      account.username ?? '',
      account.password ?? '',
      channel.streamId,
      channel.type,
      quality: quality,
      directUrl: stored,
      extension: channel.containerExtension,
    );
  }

  /// Xtream servers may expose only HLS or only transport-stream for a
  /// channel. Never invent an alternate URL for a direct M3U source.
  String? liveFallback(
    Account account,
    Channel channel, {
    StreamQuality quality = StreamQuality.auto,
  }) {
    if (account.type != 'xtream' ||
        channel.type != 'live' ||
        channel.streamUrl?.trim().isNotEmpty == true) {
      return null;
    }
    if (channel.accountId != 0 && channel.accountId != account.id) {
      throw StateError('Content belongs to another account');
    }
    return StreamUrlBuilder.live(
      account.url,
      account.username ?? '',
      account.password ?? '',
      channel.streamId,
      quality: quality == StreamQuality.auto
          ? StreamQuality.high
          : StreamQuality.auto,
    );
  }

  Future<String> resolve(
    Account account,
    Channel channel, {
    StreamQuality quality = StreamQuality.auto,
    Map<String, dynamic>? vodInfo,
  }) async {
    if (channel.type == 'live') {
      return resolveLive(account, channel, quality: quality);
    }
    if (channel.accountId != 0 && channel.accountId != account.id) {
      throw StateError('Content belongs to another account');
    }
    final stored = channel.streamUrl;
    if (account.type == 'm3u') {
      if (stored == null || stored.trim().isEmpty) {
        throw StateError('Missing playlist media URL');
      }
      return stored;
    }
    final user = account.username ?? '';
    final password = account.password ?? '';
    if (channel.type == 'movie') {
      String? fromInfo(Map<String, dynamic>? info) {
        if (info == null) return null;
        // Xtream's playback fields live in movie_data, not the display metadata.
        for (final value in [info['movie_data'], info, info['info']]) {
          if (value is Map) {
            final url = StreamUrlBuilder.vodFromMetadata(
              account.url,
              user,
              password,
              channel.streamId,
              value,
            );
            if (url != null) return url;
          }
        }
        return null;
      }

      final provided = fromInfo(vodInfo);
      if (provided != null) return provided;
      if (stored != null && stored.isNotEmpty) return stored;
      if (channel.containerExtension?.trim().isNotEmpty == true) {
        return StreamUrlBuilder.movie(
          account.url,
          user,
          password,
          channel.streamId,
          extension: channel.containerExtension,
        );
      }
      // Newly synced rows already contain playback metadata. Only legacy rows
      // require a detail lookup. Keep the previous fallback if details fail.
      try {
        final info = await loadVodInfo(
          account.url,
          user,
          password,
          channel.streamId,
        ).timeout(const Duration(seconds: 10));
        final resolved = fromInfo(info);
        if (resolved != null) return resolved;
      } catch (_) {}
    }
    return StreamUrlBuilder.build(
      account.url,
      user,
      password,
      channel.streamId,
      channel.type,
      quality: quality,
      directUrl: stored,
      extension: channel.containerExtension,
    );
  }
}

final playbackUrlResolverProvider = Provider(
  (ref) => PlaybackUrlResolver(ref.read(xtreamApiServiceProvider).getVODInfo),
);
