import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/lan_discovery.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';

void main() {
  final from = InternetAddress('192.168.1.34');

  group('discovery packets', () {
    test('round-trip keeps fields and takes the host from the source', () {
      final bytes = encodeDiscoveryPacket(
        type: 'announce',
        id: 'abc',
        name: 'Salon TV',
        port: 48741,
      );
      final p = parseDiscoveryPacket(bytes, from)!;
      expect(p.type, 'announce');
      expect(p.id, 'abc');
      expect(p.name, 'Salon TV');
      expect(p.port, 48741);
      expect(p.host, '192.168.1.34');
    });

    test('ignores an address written inside the packet', () {
      final bytes = utf8.encode(
        jsonEncode({
          'app': 'lifeostv-sync',
          'v': 2,
          'type': 'announce',
          'id': 'x',
          'name': 'n',
          'port': '48741',
          'ip': '10.0.0.99',
          'future': {'k': 1},
        }),
      );
      final p = parseDiscoveryPacket(bytes, from)!;
      expect(p.host, '192.168.1.34');
      expect(p.port, 48741);
    });

    test('rejects foreign, malformed and invalid packets', () {
      List<int> j(Object o) => utf8.encode(jsonEncode(o));
      expect(parseDiscoveryPacket(const [], from), isNull);
      expect(parseDiscoveryPacket(utf8.encode('not json'), from), isNull);
      expect(parseDiscoveryPacket(j([1, 2]), from), isNull);
      // AnyWhere / other apps on the LAN.
      expect(
        parseDiscoveryPacket(j({'id': 'a', 'name': 'b', 'port': 1}), from),
        isNull,
      );
      expect(
        parseDiscoveryPacket(
          j({'app': 'lifeostv-sync', 'type': 'announce', 'id': ''}),
          from,
        ),
        isNull,
      );
      expect(
        parseDiscoveryPacket(
          j({'app': 'lifeostv-sync', 'type': 'announce', 'id': 7}),
          from,
        ),
        isNull,
      );
      expect(
        parseDiscoveryPacket(
          j({
            'app': 'lifeostv-sync',
            'type': 'announce',
            'id': 'a',
            'port': 70000,
          }),
          from,
        ),
        isNull,
      );
    });
  });

  group('discoveryTargets', () {
    test('multicast, broadcast, subnet broadcasts and known peers', () {
      final t = discoveryTargets(
        ['192.168.1.34', '10.0.5.2', '127.0.0.1', '169.254.3.4', 'bogus'],
        ['192.168.1.50', '192.168.1.34', 'fe80::1', 'tv.local'],
      );
      expect(
        t,
        unorderedEquals([
          LanDiscovery.multicastGroup,
          '255.255.255.255',
          '192.168.1.255',
          '10.0.5.255',
          '192.168.1.50',
        ]),
      );
    });

    test('still has multicast and broadcast without interfaces', () {
      expect(
        discoveryTargets(const [], const []),
        unorderedEquals([LanDiscovery.multicastGroup, '255.255.255.255']),
      );
    });
  });

  group('SyncPeer', () {
    test('manual input accepts ip, ip:port and rejects junk', () {
      final a = SyncPeer.fromManualInput(' 192.168.1.20 ')!;
      expect(a.host, '192.168.1.20');
      expect(a.port, LanSyncService.lanSyncPort);
      final b = SyncPeer.fromManualInput('192.168.1.20:5000')!;
      expect(b.port, 5000);
      expect(SyncPeer.fromManualInput(''), isNull);
      expect(SyncPeer.fromManualInput('192.168.1.20:99999'), isNull);
    });

    test('baseUrl brackets IPv6 hosts', () {
      const v6 = SyncPeer(name: 'x', host: 'fd00::12', port: 48741);
      expect(v6.baseUrl, 'http://[fd00::12]:48741');
      expect(Uri.parse('${v6.baseUrl}/manifest').host, 'fd00::12');
      const v4 = SyncPeer(name: 'x', host: '192.168.1.2', port: 48741);
      expect(v4.baseUrl, 'http://192.168.1.2:48741');
      expect(v4.hasIPv4Host, isTrue);
      expect(v6.hasIPv4Host, isFalse);
    });
  });

  // Unicast over loopback so the tests do not depend on the machine's
  // multicast/broadcast setup (VPNs and firewalls often drop those).
  group('over UDP', () {
    test('an advertising device answers a query with an announce', () async {
      final sender = LanDiscovery();
      await sender.advertise(deviceId: 'tx', name: 'Sender', httpPort: 48741);
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final reply = Completer<LanDiscoveryPacket>();
      probe.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = probe.receive();
        if (d == null) return;
        final p = parseDiscoveryPacket(d.data, d.address);
        if (p != null && p.type == 'announce' && !reply.isCompleted) {
          reply.complete(p);
        }
      });
      try {
        probe.send(
          encodeDiscoveryPacket(type: 'query', id: 'rx', name: '', port: 0),
          InternetAddress.loopbackIPv4,
          LanDiscovery.port,
        );
        final p = await reply.future.timeout(const Duration(seconds: 5));
        expect(p.id, 'tx');
        expect(p.name, 'Sender');
        expect(p.port, 48741);
        expect(p.host, '127.0.0.1');
      } finally {
        probe.close();
        await sender.stopAdvertising();
      }
    });

    test('a searching device reports announces and skips its own', () async {
      final receiver = LanDiscovery();
      final seen = <LanDiscoveryPacket>[];
      final got = Completer<void>();
      final stop = await receiver.search((p) {
        seen.add(p);
        if (p.id == 'tx' && !got.isCompleted) got.complete();
      }, ownId: 'rx');
      final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        probe.send(
          utf8.encode('garbage'),
          InternetAddress.loopbackIPv4,
          LanDiscovery.port,
        );
        probe.send(
          encodeDiscoveryPacket(
            type: 'announce',
            id: 'tx',
            name: 'Salon TV',
            port: 48741,
          ),
          InternetAddress.loopbackIPv4,
          LanDiscovery.port,
        );
        await got.future.timeout(const Duration(seconds: 5));
        expect(seen.single.name, 'Salon TV');
        expect(seen.single.host, '127.0.0.1');
      } finally {
        probe.close();
        stop();
      }
    });
  });
}
