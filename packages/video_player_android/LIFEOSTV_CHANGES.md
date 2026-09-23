# LifeOsTV Android playback fork

Base: Flutter video_player_android 2.9.5 (BSD-3-Clause; LICENSE and AUTHORS retained).
Only engine-local playback configuration, shared by texture and platform-view
creation, is added. The channel `com.lifeostv.lifeostv/playback_config` configures
the next player. There is no global/static state and no reflection.

Changes: MediaCodec fallback on decoder initialization failure; software-only
MediaCodec selection when hardware acceleration is disabled; bounded live/VOD
load control; adaptive track bitrate limits. Software-only cannot supply codecs
absent from Android. Quality caps only affect streams offering alternate tracks.

On upstream upgrades reapply LifeOsPlaybackConfig and the three integration sites
(VideoPlayerPlugin, TextureVideoPlayer, PlatformViewVideoPlayer), then run Android
compilation and native player tests. Upstream test factories with the old create
signature must pass a LifeOsPlaybackConfig. Native sources and upstream test
sources are kept for review; Dart/Pigeon APIs are unchanged.
