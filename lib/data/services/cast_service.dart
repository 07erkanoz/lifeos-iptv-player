import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
// Import only the parts of `cast` that work with bonsoir v6
// (CastDiscoveryService is broken with bonsoir >=6, so we skip it)
import 'package:cast/device.dart';
import 'package:cast/session.dart';
import 'package:cast/session_manager.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
//  Cast state
// ---------------------------------------------------------------------------

enum CastConnectionState { disconnected, connecting, connected }

class CastState {
  final CastConnectionState connectionState;
  final CastDevice? device;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  const CastState({
    this.connectionState = CastConnectionState.disconnected,
    this.device,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  CastState copyWith({
    CastConnectionState? connectionState,
    CastDevice? device,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool clearDevice = false,
  }) {
    return CastState(
      connectionState: connectionState ?? this.connectionState,
      device: clearDevice ? null : (device ?? this.device),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }

  bool get isConnected => connectionState == CastConnectionState.connected;
  bool get isDisconnected => connectionState == CastConnectionState.disconnected;
}

// ---------------------------------------------------------------------------
//  Stream type for cast LOAD command
// ---------------------------------------------------------------------------

enum CastStreamType { live, buffered }

// ---------------------------------------------------------------------------
//  CastService — Chromecast discovery, connection, media control
//  Global singleton with ValueNotifier for reactive UI updates.
// ---------------------------------------------------------------------------

class CastService {
  CastService._();
  static final CastService instance = CastService._();

  final _sessionManager = CastSessionManager();

  CastSession? _session;
  StreamSubscription? _messageSub;
  StreamSubscription? _stateSub;
  int _mediaRequestId = 1;

  /// Reactive state — use ValueListenableBuilder in widgets.
  final ValueNotifier<CastState> stateNotifier =
      ValueNotifier(const CastState());

  CastState get state => stateNotifier.value;

  void _updateState(CastState newState) {
    stateNotifier.value = newState;
  }

  // ── Discovery (bonsoir v6 API) ─────────────────────────────────────────

  /// Search for Chromecast devices on the local network via mDNS.
  /// Returns list after [timeout] (default 5s).
  Future<List<CastDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Only available on Android & iOS (mDNS)
    if (!(Platform.isAndroid || Platform.isIOS)) return [];

    final results = <CastDevice>{};

    try {
      final discovery = BonsoirDiscovery(type: '_googlecast._tcp');
      await discovery.initialize();

      discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            // Resolve the found service to get host/port
            event.service.resolve(discovery.serviceResolver);
            break;
          case BonsoirDiscoveryServiceResolvedEvent():
            final svc = event.service;
            final host = svc.host;
            final port = svc.port;
            if (host == null || port == 0) break;

            // Build friendly name from mDNS attributes
            String name = [
              svc.attributes['md'],
              svc.attributes['fn'],
            ].whereType<String>().where((s) => s.isNotEmpty).join(' - ');
            if (name.isEmpty) name = svc.name;

            results.add(CastDevice(
              serviceName: svc.name,
              name: name,
              host: host,
              port: port,
              extras: svc.attributes,
            ));
            break;
          default:
            break;
        }
      });

      await discovery.start();
      await Future.delayed(timeout);
      await discovery.stop();
    } catch (e) {
      // Swallow errors — device list may be partial
    }

    return results.toList();
  }

  // ── Connection ─────────────────────────────────────────────────────────

  /// Connect to a Chromecast device and launch Default Media Receiver.
  /// Returns `true` only after the receiver app is fully loaded and
  /// ready to accept LOAD commands (waits for RECEIVER_STATUS → transportId).
  Future<bool> connectToDevice(CastDevice device) async {
    if (state.connectionState == CastConnectionState.connecting) return false;
    _updateState(state.copyWith(
      connectionState: CastConnectionState.connecting,
      device: device,
    ));

    try {
      _session = await _sessionManager.startSession(
        device,
        const Duration(seconds: 10),
      );

      // Completer resolves when receiver app is ready (transportId received)
      final readyCompleter = Completer<bool>();

      _stateSub = _session!.stateStream.listen((sessionState) {
        if (sessionState == CastSessionState.connected) {
          _updateState(state.copyWith(
            connectionState: CastConnectionState.connected,
          ));
          if (!readyCompleter.isCompleted) readyCompleter.complete(true);
        } else if (sessionState == CastSessionState.closed) {
          if (!readyCompleter.isCompleted) readyCompleter.complete(false);
          _cleanup();
        }
      });

      _messageSub = _session!.messageStream.listen(_handleMessage);

      // Launch Default Media Receiver (CC1AD845)
      _session!.sendMessage(CastSession.kNamespaceReceiver, {
        'type': 'LAUNCH',
        'appId': 'CC1AD845',
        'requestId': _nextRequestId(),
      });

      // Wait until receiver app reports ready or timeout after 15s
      final ready = await readyCompleter.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);

      if (!ready) {
        _cleanup();
        return false;
      }

      return true;
    } catch (e) {
      _cleanup();
      return false;
    }
  }

  /// Disconnect from current Chromecast device.
  Future<void> disconnect() async {
    if (_session != null) {
      try {
        // Stop media first
        _sendMediaCommand({'type': 'STOP'});
        await _session!.close();
      } catch (_) {}
    }
    _cleanup();
  }

  void _cleanup() {
    _messageSub?.cancel();
    _messageSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _session = null;
    _updateState(const CastState());
  }

  // ── Media control ──────────────────────────────────────────────────────

  /// Load a media URL on the Chromecast.
  void loadMedia({
    required String url,
    required String title,
    String? imageUrl,
    CastStreamType streamType = CastStreamType.live,
  }) {
    if (_session == null || !state.isConnected) return;

    final metadata = <String, dynamic>{
      'metadataType': 0,
      'title': title,
    };
    if (imageUrl != null && imageUrl.isNotEmpty) {
      metadata['images'] = [
        {'url': imageUrl},
      ];
    }

    // Determine contentType from URL extension
    final contentType = _guessContentType(url);

    _sendMediaCommand({
      'type': 'LOAD',
      'media': {
        'contentId': url,
        'contentType': contentType,
        'streamType': streamType == CastStreamType.live ? 'LIVE' : 'BUFFERED',
        'metadata': metadata,
      },
      'autoplay': true,
    });

    _updateState(state.copyWith(isPlaying: true));
  }

  /// Guess MIME type from URL extension/path.
  /// Chromecast Default Media Receiver needs the correct contentType to play.
  String _guessContentType(String url) {
    // Strip query parameters for extension check
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();

    if (path.endsWith('.m3u8')) return 'application/x-mpegurl';
    if (path.endsWith('.mpd')) return 'application/dash+xml';
    if (path.endsWith('.mp4')) return 'video/mp4';
    if (path.endsWith('.mkv')) return 'video/x-matroska';
    if (path.endsWith('.avi')) return 'video/x-msvideo';
    if (path.endsWith('.ts')) return 'video/mp2t';

    // Xtream API: /live/ paths are typically TS/HLS streams
    if (path.contains('/live/')) return 'video/mp2t';
    // Xtream API: /movie/ and /series/ paths are typically mp4/mkv containers
    if (path.contains('/movie/') || path.contains('/series/')) return 'video/mp4';

    // Default: assume HLS (most IPTV streams)
    return 'application/x-mpegurl';
  }

  /// Play / resume.
  void play() {
    _sendMediaCommand({'type': 'PLAY'});
    _updateState(state.copyWith(isPlaying: true));
  }

  /// Pause.
  void pause() {
    _sendMediaCommand({'type': 'PAUSE'});
    _updateState(state.copyWith(isPlaying: false));
  }

  /// Toggle play/pause.
  void playOrPause() {
    if (state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Seek to position (seconds).
  void seek(Duration position) {
    _sendMediaCommand({
      'type': 'SEEK',
      'currentTime': position.inMilliseconds / 1000.0,
    });
    _updateState(state.copyWith(position: position));
  }

  /// Stop media playback.
  void stop() {
    _sendMediaCommand({'type': 'STOP'});
    _updateState(state.copyWith(isPlaying: false));
  }

  // ── Internal ───────────────────────────────────────────────────────────

  void _sendMediaCommand(Map<String, dynamic> payload) {
    if (_session == null) return;
    payload['requestId'] = _nextRequestId();
    _session!.sendMessage(CastSession.kNamespaceMedia, payload);
  }

  int _nextRequestId() => _mediaRequestId++;

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    if (type == 'MEDIA_STATUS') {
      final statuses = message['status'] as List<dynamic>?;
      if (statuses != null && statuses.isNotEmpty) {
        final status = statuses[0] as Map<String, dynamic>;
        final playerState = status['playerState'] as String?;
        final currentTime = (status['currentTime'] as num?)?.toDouble() ?? 0;

        final media = status['media'] as Map<String, dynamic>?;
        final dur = (media?['duration'] as num?)?.toDouble() ?? 0;

        _updateState(state.copyWith(
          isPlaying: playerState == 'PLAYING' || playerState == 'BUFFERING',
          position: Duration(milliseconds: (currentTime * 1000).toInt()),
          duration: Duration(milliseconds: (dur * 1000).toInt()),
        ));
      }
    } else if (type == 'CLOSE') {
      _cleanup();
    }
  }
}
