import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/dlna_service.dart';

void main() {
  late HttpServer server;
  late DlnaService service;
  late DlnaDevice device;
  late List<(String, String)> requests;
  String position = '00:12:34.500';
  String transport = 'PLAYING';
  bool positionFault = false;
  Completer<void>? positionHold;
  setUp(() async {
    requests = [];
    position = '00:12:34.500';
    transport = 'PLAYING';
    positionFault = false;
    positionHold = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final action = req.headers
          .value('SOAPAction')!
          .split('#')
          .last
          .replaceAll('"', '');
      final body = await utf8.decoder.bind(req).join();
      requests.add((action, body));
      if (action == 'GetPositionInfo' && positionHold != null)
        await positionHold!.future;
      if (action == 'GetPositionInfo' && positionFault) {
        req.response.statusCode = 500;
      } else {
        req.response.headers.contentType = ContentType('text', 'xml');
        req.response.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
          '<u:${action}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
          '${action == 'GetPositionInfo' ? '<u:RelTime>$position</u:RelTime>' : ''}'
          '${action == 'GetTransportInfo' ? '<CurrentTransportState>$transport</CurrentTransportState>' : ''}'
          '</u:${action}Response></s:Body></s:Envelope>',
        );
      }
      await req.response.close();
    });
    service = DlnaService.forTesting();
    device = DlnaDevice(
      name: 'Test renderer',
      controlUrl: Uri.parse('http://127.0.0.1:${server.port}/control'),
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
    );
    service.connectTo(device);
  });
  tearDown(() async {
    if (positionHold != null && !positionHold!.isCompleted)
      positionHold!.complete();
    await service.disconnect();
    service.stateNotifier.dispose();
    await server.close(force: true);
  });
  test(
    'buffered handoff sends REL_TIME and return retains final receiver position',
    () async {
      await service.loadMedia(
        url: 'https://example.invalid/movie.mp4',
        title: 'Film',
        startPosition: const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      final seek = requests.firstWhere((r) => r.$1 == 'Seek').$2;
      expect(seek, contains('<Unit>REL_TIME</Unit>'));
      expect(seek, contains('<Target>01:02:03</Target>'));
      expect(
        service.lastPosition,
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      await service.disconnect();
      expect(
        service.lastPosition,
        const Duration(minutes: 12, seconds: 34, milliseconds: 500),
      );
      expect(service.state.isDisconnected, true);
    },
  );
  test(
    'unknown and failed position responses preserve last valid value',
    () async {
      await service.refreshPosition();
      final known = service.lastPosition;
      position = 'NOT_IMPLEMENTED';
      await service.refreshPosition();
      expect(service.lastPosition, known);
      positionFault = true;
      await service.refreshPosition();
      expect(service.lastPosition, known);
    },
  );
  test('late receiver response cannot contaminate a new session', () async {
    positionHold = Completer<void>();
    final old = service.refreshPosition();
    while (!requests.any((r) => r.$1 == 'GetPositionInfo')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    service.connectTo(device);
    positionHold!.complete();
    await old;
    expect(service.lastPosition, isNull);
  });
  test('live handoff does not send a seek command', () async {
    await service.loadMedia(
      url: 'https://example.invalid/live.ts',
      title: 'Live',
    );
    expect(requests.any((r) => r.$1 == 'Seek'), false);
  });
  test('time parser rejects malformed and unsupported values', () {
    for (final value in [
      null,
      '',
      'NOT_IMPLEMENTED',
      '-1:00:00',
      '00:60:00',
      '00:00:60',
    ]) {
      expect(parseDlnaTime(value), isNull);
    }
    expect(
      parseDlnaTime('27:01:02.5'),
      const Duration(hours: 27, minutes: 1, seconds: 2, milliseconds: 500),
    );
    expect(formatDlnaTime(const Duration(hours: 27, minutes: 1)), '27:01:00');
  });
}
