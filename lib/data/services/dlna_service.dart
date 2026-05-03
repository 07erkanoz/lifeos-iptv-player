import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

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
  bool get isDisconnected => connectionState == DlnaConnectionState.disconnected;

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
  static final DlnaService instance = DlnaService._();

  /// Reactive state for the UI (mirror of CastService.stateNotifier).
  final ValueNotifier<DlnaState> stateNotifier = ValueNotifier(const DlnaState());

  DlnaState get state => stateNotifier.value;
  void _updateState(DlnaState s) => stateNotifier.value = s;

  // ─── Discovery (SSDP M-SEARCH on UDP 1900) ───────────────────────────

  /// Multicast group + port used by SSDP. Same on every UPnP device.
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;

  /// MediaRenderer is the UPnP "thing that plays video / audio". Smart
  /// TVs advertise themselves under this device type.
  static const _renderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// Search the LAN for MediaRenderer devices. Returns whatever responded
  /// within [timeout] (default 5s). Safe to call repeatedly — no state.
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (Platform.isAndroid || Platform.isIOS ||
        Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      // OK — these platforms expose UDP sockets.
    } else {
      return const [];
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
        reuseAddress: true);
    try {
      socket.broadcastEnabled = true;

      // Build M-SEARCH request — exact format mandated by UPnP spec.
      final request = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_ssdpAddress:$_ssdpPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $_renderer\r\n\r\n',
      );
      socket.send(request, InternetAddress(_ssdpAddress), _ssdpPort);

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
  }

  Uri? _extractLocationHeader(String body) => extractSsdpLocationHeader(body);

  /// Fetch the SCPD device description, parse out friendlyName +
  /// AVTransport controlURL.
  Future<DlnaDevice?> _fetchDevice(Uri location) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        responseType: ResponseType.plain,
      ));
      final response = await dio.getUri<String>(location);
      final body = response.data;
      if (body == null || body.isEmpty) return null;

      final doc = XmlDocument.parse(body);
      final root = doc.rootElement;

      final device = root.findAllElements('device').firstOrNull;
      if (device == null) return null;

      final name = device.findElements('friendlyName').firstOrNull?.innerText.trim() ?? '';
      final manufacturer = device.findElements('manufacturer').firstOrNull?.innerText.trim();
      final modelName = device.findElements('modelName').firstOrNull?.innerText.trim();

      // Find AVTransport service among <service> entries.
      String? controlPath;
      String? serviceType;
      for (final svc in device.findAllElements('service')) {
        final type = svc.findElements('serviceType').firstOrNull?.innerText.trim() ?? '';
        if (type.contains('AVTransport')) {
          controlPath = svc.findElements('controlURL').firstOrNull?.innerText.trim();
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
    _updateState(DlnaState(
      connectionState: DlnaConnectionState.connected,
      device: device,
    ));
  }

  Future<void> disconnect() async {
    if (state.device != null) {
      await _safeSoap('Stop', state.device!, {'InstanceID': '0'});
    }
    _updateState(const DlnaState());
  }

  /// Push a media URL to the renderer and start playing.
  ///
  /// `mimeType` matters for some TVs — they reject playback if the
  /// DIDL-Lite metadata advertises the wrong protocolInfo. We pick a
  /// sensible default per file extension; caller can override.
  Future<void> loadMedia({
    required String url,
    required String title,
    String? mimeType,
  }) async {
    final device = state.device;
    if (device == null) return;

    final mime = mimeType ?? _guessMime(url);
    final didl = _buildDidlMetadata(url: url, title: title, mime: mime);

    await _safeSoap('SetAVTransportURI', device, {
      'InstanceID': '0',
      'CurrentURI': url,
      'CurrentURIMetaData': didl,
    });
    await _safeSoap('Play', device, {
      'InstanceID': '0',
      'Speed': '1',
    });
    _updateState(state.copyWith(isPlaying: true));
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
  }) =>
      buildDidlMetadata(url: url, title: title, mime: mime);
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
    final body = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
      ..write('<s:Body>')
      ..write('<u:$action xmlns:u="${device.serviceType}">');
    args.forEach((k, v) {
      body.write('<$k>${_xmlEscape(v)}</$k>');
    });
    body
      ..write('</u:$action>')
      ..write('</s:Body>')
      ..write('</s:Envelope>');

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      responseType: ResponseType.plain,
      headers: {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPAction': '"${device.serviceType}#$action"',
      },
    ));
    await dio.postUri<String>(device.controlUrl, data: body.toString());
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
  if (lower.contains('/movie/') || lower.contains('/series/')) return 'video/mp4';
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
String buildDidlMetadata({
  required String url,
  required String title,
  required String mime,
}) {
  final escapedTitle = xmlEscape(title);
  final escapedUrl = xmlEscape(url);
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<item id="0" parentID="0" restricted="1">'
      '<dc:title>$escapedTitle</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:$mime:*">$escapedUrl</res>'
      '</item>'
      '</DIDL-Lite>';
}
