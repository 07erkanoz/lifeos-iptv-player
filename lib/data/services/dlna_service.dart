import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xml/xml.dart';

/// Thrown by [DlnaService.loadMedia] when the renderer accepted the
/// SetAVTransportURI + Play SOAP commands but never transitioned to a
/// PLAYING transport state inside our verification window. UI surfaces
/// it as a "TV got the request but didn't play — open DMR/Smart View on
/// the TV and try again" hint.
class DlnaPlaybackVerificationException implements Exception {
  final String message;
  final String? lastState;
  DlnaPlaybackVerificationException(this.message, {this.lastState});
  @override
  String toString() =>
      'DlnaPlaybackVerificationException($message, lastState=$lastState)';
}

/// Shared MethodChannel to the Android native side. Used here to
/// acquire / release a Wi-Fi multicast lock around SSDP discovery —
/// Android drops incoming multicast UDP after a short idle without
/// the lock, which makes SSDP M-SEARCH return zero devices even
/// though the TV is reachable.
const _platformChannel = MethodChannel('com.lifeostv.lifeostv/platform');

/// DLNA / UPnP MediaRenderer.
///
/// Casting target on most LG / Samsung / Sony Smart TVs that don't ship
/// Chromecast. Discovery is plain SSDP M-SEARCH on the LAN; control is
/// SOAP over HTTP to the device's AVTransport service.
class DlnaDevice {
  /// Friendly name as advertised by the device, e.g. "LG webOS TV".
  final String name;

  /// Manufacturer / model — useful as a tie-breaker label in the UI when
  /// two devices share the same friendlyName.
  final String? manufacturer;
  final String? modelName;

  /// SOAP control endpoint for AVTransport. Already absolute.
  final Uri controlUrl;

  /// AVTransport service type — usually `urn:schemas-upnp-org:service:AVTransport:1`.
  final String serviceType;

  const DlnaDevice({
    required this.name,
    this.manufacturer,
    this.modelName,
    required this.controlUrl,
    required this.serviceType,
  });

  String get displayName {
    if (modelName != null && modelName!.isNotEmpty && name != modelName) {
      return '$name ($modelName)';
    }
    return name;
  }

  /// Used as a uniqueness key when merging discovery responses (the same
  /// device often answers multiple M-SEARCHes).
  String get fingerprint => controlUrl.toString();

  @override
  bool operator ==(Object other) =>
      other is DlnaDevice && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}

/// Loosely mirrors CastConnectionState so the UI can reuse one mental model.
enum DlnaConnectionState { disconnected, connecting, connected }

class DlnaState {
  final DlnaConnectionState connectionState;
  final DlnaDevice? device;
  final bool isPlaying;

  const DlnaState({
    this.connectionState = DlnaConnectionState.disconnected,
    this.device,
    this.isPlaying = false,
  });

  bool get isConnected => connectionState == DlnaConnectionState.connected;
  bool get isDisconnected =>
      connectionState == DlnaConnectionState.disconnected;

  DlnaState copyWith({
    DlnaConnectionState? connectionState,
    DlnaDevice? device,
    bool? isPlaying,
    bool clearDevice = false,
  }) {
    return DlnaState(
      connectionState: connectionState ?? this.connectionState,
      device: clearDevice ? null : (device ?? this.device),
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

/// Singleton DLNA control + discovery service.
class DlnaService {
  DlnaService._();

  @visibleForTesting
  DlnaService.forTesting();
  static final DlnaService instance = DlnaService._();

  /// Reactive state for the UI (mirror of CastService.stateNotifier).
  final ValueNotifier<DlnaState> stateNotifier = ValueNotifier(
    const DlnaState(),
  );

  DlnaState get state => stateNotifier.value;
  void _updateState(DlnaState s) => stateNotifier.value = s;

  Timer? _positionTimer;
  int _session = 0;
  bool _pollingPosition = false;
  Duration? _lastPosition;
  Duration? get lastPosition => _lastPosition;

  // ─── Discovery (SSDP M-SEARCH on UDP 1900) ───────────────────────────

  /// Multicast group + port used by SSDP. Same on every UPnP device.
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;

  /// MediaRenderer is the UPnP "thing that plays video / audio". Smart
  /// TVs advertise themselves under this device type.
  static const _renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// Search the LAN for MediaRenderer devices. Returns whatever responded
  /// within [timeout] (default 10s — was 5s but several home setups need
  /// the longer window because of multicast retransmission delays).
  /// Safe to call repeatedly — no state.
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isWindows) {
      // OK — these platforms expose UDP sockets.
    } else {
      return const [];
    }

    // Android 13+ requires NEARBY_WIFI_DEVICES runtime permission for any
    // LAN discovery that doesn't already imply ACCESS_FINE_LOCATION
    // (which we don't want to ask for — it's overkill for casting). The
    // permission_handler request is a no-op on Android <13 and other
    // platforms.
    if (Platform.isAndroid) {
      try {
        final status = await Permission.nearbyWifiDevices.status;
        if (!status.isGranted) {
          final result = await Permission.nearbyWifiDevices.request();
          // If user denies we still try discovery — on Android 12 and
          // earlier the permission isn't required, the request just
          // resolves "denied" without effect.
          if (kDebugMode) debugPrint('[Dlna] nearbyWifiDevices: $result');
        }
      } catch (_) {
        // permission_handler can throw on devices without the API; SSDP
        // still works via legacy paths in that case.
      }
    }

    // Hold a Wi-Fi multicast lock for the duration of discovery so
    // Android doesn't drop the SSDP response datagrams. No-op outside
    // Android.
    await _acquireMulticastLock();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      try {
        socket.broadcastEnabled = true;
        // Loopback off: we don't want to see our own M-SEARCH back.
        try {
          socket.multicastLoopback = false;
        } catch (_) {}

        // Build M-SEARCH request — exact format mandated by UPnP spec.
        // MX bumped 3→5 so TVs that wait the full window before
        // responding actually get heard.
        final request = utf8.encode(
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_ssdpAddress:$_ssdpPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 5\r\n'
          'ST: $_renderer\r\n\r\n',
        );
        // Send twice with a small gap — multicast UDP is unreliable and
        // some Samsung Tizen firmwares miss the first packet.
        socket.send(request, InternetAddress(_ssdpAddress), _ssdpPort);
        Future.delayed(const Duration(milliseconds: 500), () {
          try {
            socket.send(request, InternetAddress(_ssdpAddress), _ssdpPort);
          } catch (_) {}
        });

        final locations = <Uri>{};
        final completer = Completer<void>();
        late StreamSubscription<RawSocketEvent> sub;
        sub = socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final dg = socket.receive();
          if (dg == null) return;
          final body = utf8.decode(dg.data, allowMalformed: true);
          final loc = _extractLocationHeader(body);
          if (loc != null) locations.add(loc);
        });

        Timer(timeout, () {
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future;
        await sub.cancel();

        // Fan out: fetch + parse each device description XML in parallel.
        final futures = locations.map(_fetchDevice).toList();
        final results = await Future.wait(futures, eagerError: false);
        return results.whereType<DlnaDevice>().toSet().toList();
      } finally {
        socket.close();
      }
    } finally {
      await _releaseMulticastLock();
    }
  }

  Future<void> _acquireMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod('acquireMulticastLock');
    } catch (_) {}
  }

  Future<void> _releaseMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod('releaseMulticastLock');
    } catch (_) {}
  }

  Uri? _extractLocationHeader(String body) => extractSsdpLocationHeader(body);

  /// Fetch the SCPD device description, parse out friendlyName +
  /// AVTransport controlURL.
  Future<DlnaDevice?> _fetchDevice(Uri location) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          responseType: ResponseType.plain,
        ),
      );
      final response = await dio.getUri<String>(location);
      final body = response.data;
      if (body == null || body.isEmpty) return null;

      final doc = XmlDocument.parse(body);
      final root = doc.rootElement;

      final device = root.findAllElements('device').firstOrNull;
      if (device == null) return null;

      final name =
          device.findElements('friendlyName').firstOrNull?.innerText.trim() ??
          '';
      final manufacturer = device
          .findElements('manufacturer')
          .firstOrNull
          ?.innerText
          .trim();
      final modelName = device
          .findElements('modelName')
          .firstOrNull
          ?.innerText
          .trim();

      // Find AVTransport service among <service> entries.
      String? controlPath;
      String? serviceType;
      for (final svc in device.findAllElements('service')) {
        final type =
            svc.findElements('serviceType').firstOrNull?.innerText.trim() ?? '';
        if (type.contains('AVTransport')) {
          controlPath = svc
              .findElements('controlURL')
              .firstOrNull
              ?.innerText
              .trim();
          serviceType = type;
          break;
        }
      }
      if (controlPath == null || serviceType == null) return null;

      // controlURL is often relative — resolve against the device location.
      final controlUrl = location.resolve(controlPath);

      return DlnaDevice(
        name: name.isEmpty ? (modelName ?? 'DLNA device') : name,
        manufacturer: manufacturer,
        modelName: modelName,
        controlUrl: controlUrl,
        serviceType: serviceType,
      );
    } catch (e) {
      debugPrint('[Dlna] failed to read $location: $e');
      return null;
    }
  }

  // ─── Connection + media control (SOAP over HTTP) ─────────────────────

  void connectTo(DlnaDevice device) {
    ++_session;
    _positionTimer?.cancel();
    _lastPosition = null;
    _updateState(
      DlnaState(connectionState: DlnaConnectionState.connected, device: device),
    );
  }

  Future<void> disconnect() async {
    _positionTimer?.cancel();
    final session = ++_session;
    final device = state.device;
    if (device != null) {
      await refreshPosition();
      await _safeSoap('Stop', device, {'InstanceID': '0'});
    }
    if (session != _session) return;
    ++_session;
    _updateState(const DlnaState());
  }

  Future<void> refreshPosition() async {
    final device = state.device;
    final session = _session;
    if (device == null || _pollingPosition) return;
    _pollingPosition = true;
    try {
      final response = await _soapActionRaw('GetPositionInfo', device, {
        'InstanceID': '0',
      });
      final position = parseDlnaTime(_extractElementText(response, 'RelTime'));
      if (session == _session && position != null) _lastPosition = position;
    } catch (_) {
      // Some renderers return NOT_IMPLEMENTED or reject position requests.
      // Keep the last confirmed position, never replace it with zero.
    } finally {
      _pollingPosition = false;
    }
  }

  Future<void> seek(Duration position) async {
    final device = state.device;
    final session = _session;
    if (device == null) return;
    final target = position < Duration.zero ? Duration.zero : position;
    await _soapAction('Seek', device, {
      'InstanceID': '0',
      'Unit': 'REL_TIME',
      'Target': formatDlnaTime(target),
    });
    if (session == _session) _lastPosition = target;
  }

  /// Push a media URL to the renderer and start playing.
  ///
  /// `mimeType` matters for some TVs — they reject playback if the
  /// DIDL-Lite metadata advertises the wrong protocolInfo. We pick a
  /// sensible default per file extension; caller can override.
  ///
  /// Throws [DlnaPlaybackVerificationException] if the renderer accepted
  /// the SOAP calls but never moved to a PLAYING transport state inside
  /// our verification window. Other failures (transport / SOAP fault)
  /// propagate the underlying [DioException].
  Future<void> loadMedia({
    required String url,
    required String title,
    String? mimeType,
    Duration startPosition = Duration.zero,
  }) async {
    final device = state.device;
    if (device == null) return;
    final session = ++_session;
    _positionTimer?.cancel();
    _lastPosition = null;

    final mime = mimeType ?? _guessMime(url);
    final didl = _buildDidlMetadata(url: url, title: title, mime: mime);

    // Use raw _soapAction so failures propagate (previously _safeSoap
    // swallowed them and the user would see "connected" with a black
    // screen on the TV).
    await _soapAction('SetAVTransportURI', device, {
      'InstanceID': '0',
      'CurrentURI': url,
      'CurrentURIMetaData': didl,
    });
    if (session != _session) return;
    await _soapAction('Play', device, {'InstanceID': '0', 'Speed': '1'});
    if (session != _session) return;
    _updateState(state.copyWith(isPlaying: true));

    // Verify the renderer actually entered PLAYING within ~5 seconds.
    // GetTransportInfo is part of the AVTransport spec — every
    // compliant renderer must respond. We poll every 500ms; success
    // requires PLAYING, not merely TRANSITIONING. PAUSED_PLAYBACK,
    // STOPPED, NO_MEDIA_PRESENT after the grace window are failures.
    try {
      final ok = await _verifyPlaying(device);
      if (!ok.success) {
        throw DlnaPlaybackVerificationException(
          'TV oynatma onayı vermedi (durum: ${ok.lastState ?? "bilinmiyor"}).',
          lastState: ok.lastState,
        );
      }
    } on DlnaPlaybackVerificationException {
      if (session == _session) _updateState(state.copyWith(isPlaying: false));
      rethrow;
    } catch (_) {
      // Renderer didn't implement GetTransportInfo cleanly — fall back
      // to optimistic assumption (we already sent Play; if it really
      // didn't work the user will see no video and try again).
    }
    if (session != _session) return;
    if (startPosition > Duration.zero) await seek(startPosition);
    if (session != _session) return;
    _positionTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refreshPosition());
    });
  }

  /// Poll GetTransportInfo until the renderer reports PLAYING or the
  /// grace window expires. Returns the last observed state for diagnostics.
  Future<({bool success, String? lastState})> _verifyPlaying(
    DlnaDevice device, {
    Duration window = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final deadline = DateTime.now().add(window);
    String? last;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await _soapActionRaw('GetTransportInfo', device, {
          'InstanceID': '0',
        });
        final transportState = _extractElementText(
          response,
          'CurrentTransportState',
        );
        if (transportState != null) {
          last = transportState;
          if (transportState == 'PLAYING') {
            return (success: true, lastState: transportState);
          }
        }
      } catch (_) {
        // Single poll error — keep trying inside the window.
      }
      await Future.delayed(interval);
    }
    return (success: false, lastState: last);
  }

  String? _extractElementText(String soapResponse, String localName) {
    try {
      final doc = XmlDocument.parse(soapResponse);
      final el = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == localName)
          .firstOrNull;
      return el?.innerText.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> pause() async {
    final device = state.device;
    if (device == null) return;
    await _safeSoap('Pause', device, {'InstanceID': '0'});
    _updateState(state.copyWith(isPlaying: false));
  }

  Future<void> resume() async {
    final device = state.device;
    if (device == null) return;
    await _safeSoap('Play', device, {'InstanceID': '0', 'Speed': '1'});
    _updateState(state.copyWith(isPlaying: true));
  }

  Future<void> stop() async {
    final device = state.device;
    if (device == null) return;
    await _safeSoap('Stop', device, {'InstanceID': '0'});
    _updateState(state.copyWith(isPlaying: false));
  }

  String _guessMime(String url) => dlnaMimeForUrl(url);
  String _buildDidlMetadata({
    required String url,
    required String title,
    required String mime,
  }) => buildDidlMetadata(url: url, title: title, mime: mime);
  String _xmlEscape(String s) => xmlEscape(s);

  Future<void> _safeSoap(
    String action,
    DlnaDevice device,
    Map<String, String> args,
  ) async {
    try {
      await _soapAction(action, device, args);
    } catch (e) {
      debugPrint('[Dlna] $action on ${device.displayName} failed: $e');
    }
  }

  Future<void> _soapAction(
    String action,
    DlnaDevice device,
    Map<String, String> args,
  ) async {
    await _soapActionRaw(action, device, args);
  }

  /// Like [_soapAction] but returns the SOAP envelope body so callers
  /// (e.g. GetTransportInfo verification) can parse it.
  Future<String> _soapActionRaw(
    String action,
    DlnaDevice device,
    Map<String, String> args,
  ) async {
    final body = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
      )
      ..write('<s:Body>')
      ..write('<u:$action xmlns:u="${device.serviceType}">');
    args.forEach((k, v) {
      body.write('<$k>${_xmlEscape(v)}</$k>');
    });
    body
      ..write('</u:$action>')
      ..write('</s:Body>')
      ..write('</s:Envelope>');

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPAction': '"${device.serviceType}#$action"',
        },
      ),
    );
    try {
      final res = await dio.postUri<String>(
        device.controlUrl,
        data: body.toString(),
      );
      return res.data ?? '';
    } finally {
      dio.close(force: true);
    }
  }
}

// ─── Pure helpers (top-level so unit tests can import them directly) ────

/// Pull the LOCATION header out of an SSDP M-SEARCH response. SSDP uses
/// HTTP-shaped headers separated by CRLF; the value is an absolute URL
/// pointing at the device description XML.
Uri? extractSsdpLocationHeader(String body) {
  for (final line in body.split('\r\n')) {
    final lower = line.toLowerCase();
    if (lower.startsWith('location:')) {
      final value = line.substring(9).trim();
      return Uri.tryParse(value);
    }
  }
  return null;
}

/// Best-guess MIME type for a stream URL, used when building DIDL-Lite
/// metadata. TVs vary in how strict they are; if we get this wrong some
/// of them simply refuse the stream.
String dlnaMimeForUrl(String url) {
  final lower = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  if (lower.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
  if (lower.endsWith('.mpd')) return 'application/dash+xml';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mkv')) return 'video/x-matroska';
  if (lower.endsWith('.ts')) return 'video/mp2t';
  if (lower.endsWith('.avi')) return 'video/x-msvideo';
  // Xtream live channels — usually MPEG-TS.
  if (lower.contains('/live/')) return 'video/mp2t';
  if (lower.contains('/movie/') || lower.contains('/series/'))
    return 'video/mp4';
  return 'video/mp4';
}

/// XML attribute / text escape — used inside the DIDL-Lite payload and
/// inside SOAP action arguments.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// DIDL-Lite metadata payload — minimal but most TVs require it (an
/// empty CurrentURIMetaData is rejected by, among others, several LG
/// webOS firmware versions).
///
/// The protocolInfo's 4th field carries DLNA flags. Samsung Tizen and
/// recent LG webOS firmwares reject the stream entirely if these are
/// missing — they treat the absent profile as "unsupported source".
/// We emit:
///   DLNA.ORG_OP=01    → server supports byte-range seek (most IPTV
///                       providers do; if not the TV just won't seek)
///   DLNA.ORG_CI=0     → not transcoded (we're passing through the
///                       provider's bytes as-is)
///   DLNA.ORG_FLAGS=01700000000000000000000000000000
///                     → senderPaced=0, lopNpt=1, lopBytes=1,
///                       playContainer=1, s0Increase=1, sNIncrease=1,
///                       rtspPause=1, streamingTransferMode=1,
///                       interactiveTransferMode=1,
///                       backgroundTransferMode=1, connectionStall=1,
///                       dlnaV15=1 — the catch-all combo Samsung's
///                       Tizen reference renderer expects for VOD.
String buildDidlMetadata({
  required String url,
  required String title,
  required String mime,
}) {
  final escapedTitle = xmlEscape(title);
  final escapedUrl = xmlEscape(url);
  const dlnaFlags =
      'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<item id="0" parentID="0" restricted="1">'
      '<dc:title>$escapedTitle</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:$mime:$dlnaFlags">$escapedUrl</res>'
      '</item>'
      '</DIDL-Lite>';
}

/// UPnP relative time; unsupported/invalid values are unknown, not zero.
Duration? parseDlnaTime(String? value) {
  final match = RegExp(
    r'^(\d+):([0-5]\d):([0-5]\d)(?:\.(\d{1,3}))?$',
  ).firstMatch(value?.trim() ?? '');
  if (match == null) return null;
  final hours = int.tryParse(match[1]!);
  if (hours == null || hours > 999999) return null;
  return Duration(
    hours: hours,
    minutes: int.parse(match[2]!),
    seconds: int.parse(match[3]!),
    milliseconds: int.parse((match[4] ?? '0').padRight(3, '0')),
  );
}

String formatDlnaTime(Duration value) {
  final seconds = value.inSeconds < 0 ? 0 : value.inSeconds;
  return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
      '${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}
