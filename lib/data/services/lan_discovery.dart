import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// UDP discovery for device-to-device sync, used next to mDNS.
///
/// mDNS alone proved unreliable for LifeOS TV: Linux (Avahi) often resolves
/// a peer to an IPv6 link-local address, Windows resolves it to a
/// `HOST.local` name that Android cannot look up, and some routers drop
/// mDNS altogether. This layer works the way LifeOS AnyWhere's discovery
/// does: one socket on [port], joined to [multicastGroup] on every
/// interface, sending to the multicast group, the global broadcast, every
/// subnet broadcast and every known host. A peer's address is always the
/// datagram's source IP, never something written in the packet.
///
/// Wire format (JSON, one object per datagram, unknown keys ignored):
/// ```json
/// {"app":"lifeostv-sync","v":1,"type":"query",
///  "id":"DEVICE_ID","name":"Living room TV","port":48741}
/// ```
/// `type` is `query` (a receiver searching) or `announce` (a sender).
/// A device offering its data answers every `query` with a unicast
/// `announce` and also announces itself every few seconds.
class LanDiscovery {
  static const int port = 48742;
  static const String multicastGroup = '224.0.0.168';
  static const String appTag = 'lifeostv-sync';
  static const int version = 1;

  static const _platform = MethodChannel('com.lifeostv.lifeostv/platform');

  RawDatagramSocket? _socket;
  Future<RawDatagramSocket?>? _opening;
  Timer? _announceTimer;
  Timer? _queryTimer;

  // Advertising state (server side).
  String? _advId;
  String? _advName;
  int? _advPort;

  // Discovering state (receiver side). Several listeners may search at once.
  final _listeners = <void Function(LanDiscoveryPacket)>{};
  final _extraHosts = <String>{};

  bool get isAdvertising => _advPort != null;

  // ── Advertising ─────────────────────────────────────────────────────────

  Future<void> advertise({
    required String deviceId,
    required String name,
    required int httpPort,
  }) async {
    _advId = deviceId;
    _advName = name;
    _advPort = httpPort;
    final s = await _open();
    if (s == null) return;
    _announce();
    _announceTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _announce(),
    );
  }

  Future<void> stopAdvertising() async {
    _advId = null;
    _advName = null;
    _advPort = null;
    _announceTimer?.cancel();
    _announceTimer = null;
    _closeIfIdle();
  }

  void _announce() {
    final id = _advId, name = _advName, p = _advPort;
    if (id == null || name == null || p == null) return;
    _sendToAll(
      encodeDiscoveryPacket(type: 'announce', id: id, name: name, port: p),
    );
  }

  // ── Discovering ─────────────────────────────────────────────────────────

  /// Search for advertising devices until the returned function is called.
  /// [extraHosts] (e.g. IPs seen before) receive the query by unicast too.
  Future<void Function()> search(
    void Function(LanDiscoveryPacket) onPeer, {
    required String ownId,
    Iterable<String> extraHosts = const [],
  }) async {
    _listeners.add(onPeer);
    _extraHosts.addAll(extraHosts);
    final s = await _open();
    if (s != null) {
      void query() => _sendToAll(
        encodeDiscoveryPacket(type: 'query', id: ownId, name: '', port: 0),
      );
      query();
      _queryTimer ??= Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => query(),
      );
    }
    return () {
      _listeners.remove(onPeer);
      if (_listeners.isEmpty) {
        _queryTimer?.cancel();
        _queryTimer = null;
        _extraHosts.clear();
        _closeIfIdle();
      }
    };
  }

  // ── Socket ──────────────────────────────────────────────────────────────

  Future<RawDatagramSocket?> _open() {
    if (_socket != null) return Future.value(_socket);
    return _opening ??= _bind().whenComplete(() => _opening = null);
  }

  Future<RawDatagramSocket?> _bind() async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } catch (e) {
      // The port is taken (another copy of the app?). An ephemeral port can
      // still query and receive the unicast answers.
      if (kDebugMode) debugPrint('[LanDiscovery] bind $port failed: $e');
      try {
        s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (e) {
        if (kDebugMode) debugPrint('[LanDiscovery] bind failed: $e');
        return null;
      }
    }
    s.broadcastEnabled = true;
    s.multicastLoopback = true;
    await _joinMulticast(s);
    await _setMulticastLock(true);
    s.listen((event) {
      if (event == RawSocketEvent.read) _drain(s!);
    }, onError: (_) {});
    _socket = s;
    return s;
  }

  Future<void> _joinMulticast(RawDatagramSocket s) async {
    final group = InternetAddress(multicastGroup);
    try {
      s.joinMulticast(group);
    } catch (_) {}
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        try {
          s.joinMulticast(group, iface);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _closeIfIdle() {
    if (isAdvertising || _listeners.isNotEmpty) return;
    final s = _socket;
    _socket = null;
    if (s != null) {
      s.close();
      _setMulticastLock(false);
    }
  }

  /// Android drops multicast (and on some chipsets broadcast) frames unless
  /// a Wi-Fi multicast lock is held. The lock lives in MainActivity and is
  /// shared with DLNA discovery.
  Future<void> _setMulticastLock(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod(
        on ? 'acquireMulticastLock' : 'releaseMulticastLock',
      );
    } catch (_) {}
  }

  void _drain(RawDatagramSocket s) {
    while (true) {
      final d = s.receive();
      if (d == null) break;
      final packet = parseDiscoveryPacket(d.data, d.address);
      if (packet == null) continue;
      if (packet.type == 'query') {
        final id = _advId, name = _advName, p = _advPort;
        if (id != null && name != null && p != null && packet.id != id) {
          try {
            s.send(
              encodeDiscoveryPacket(
                type: 'announce',
                id: id,
                name: name,
                port: p,
              ),
              d.address,
              d.port,
            );
          } catch (_) {}
        }
      } else if (packet.type == 'announce' && packet.port > 0) {
        if (packet.id == _advId) continue; // our own echo
        _extraHosts.add(packet.host);
        for (final l in _listeners.toList()) {
          l(packet);
        }
      }
    }
  }

  Future<void> _sendToAll(List<int> data) async {
    final s = _socket;
    if (s == null) return;
    List<String> local = const [];
    try {
      local = [
        for (final iface in await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        ))
          for (final a in iface.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {}
    for (final target in discoveryTargets(local, _extraHosts)) {
      try {
        s.send(data, InternetAddress(target), port);
      } catch (_) {}
    }
  }
}

/// A decoded discovery datagram. [host] is the datagram's source address.
class LanDiscoveryPacket {
  final String type;
  final String id;
  final String name;
  final int port;
  final String host;
  const LanDiscoveryPacket({
    required this.type,
    required this.id,
    required this.name,
    required this.port,
    required this.host,
  });
}

List<int> encodeDiscoveryPacket({
  required String type,
  required String id,
  required String name,
  required int port,
}) => utf8.encode(
  jsonEncode({
    'app': LanDiscovery.appTag,
    'v': LanDiscovery.version,
    'type': type,
    'id': id,
    'name': name,
    'port': port,
  }),
);

/// Parse a datagram leniently: anything that is not one of our packets
/// returns null instead of throwing.
LanDiscoveryPacket? parseDiscoveryPacket(List<int> data, InternetAddress from) {
  if (data.isEmpty || data.length > 4096) return null;
  try {
    final m = jsonDecode(utf8.decode(data, allowMalformed: true));
    if (m is! Map || m['app'] != LanDiscovery.appTag) return null;
    final type = m['type'];
    final id = m['id'];
    if (type is! String || id is! String || id.isEmpty) return null;
    final rawPort = m['port'];
    final port = rawPort is int
        ? rawPort
        : rawPort is String
        ? int.tryParse(rawPort) ?? 0
        : 0;
    if (port < 0 || port > 65535) return null;
    final name = m['name'];
    return LanDiscoveryPacket(
      type: type,
      id: id,
      name: name is String ? name : '',
      port: port,
      host: from.address,
    );
  } catch (_) {
    return null;
  }
}

/// Where to send a discovery datagram: the multicast group, the global
/// broadcast, the /24 broadcast of every local IPv4 address (some routers
/// drop 255.255.255.255 but forward directed broadcasts) and every known
/// peer by unicast (Wi-Fi power save often drops broadcast frames).
List<String> discoveryTargets(
  Iterable<String> localIPv4,
  Iterable<String> knownHosts,
) {
  final out = <String>{LanDiscovery.multicastGroup, '255.255.255.255'};
  final locals = <String>{};
  for (final ip in localIPv4) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      continue;
    }
    if (parts[0] == '127' || (parts[0] == '169' && parts[1] == '254')) {
      continue;
    }
    locals.add(ip);
    out.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }
  for (final h in knownHosts) {
    if (InternetAddress.tryParse(h)?.type == InternetAddressType.IPv4 &&
        !locals.contains(h)) {
      out.add(h);
    }
  }
  return out.toList();
}
