import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/lan_transfer_policy.dart';

void main() {
  test('public settings exclude credentials and parental unlock state', () {
    final values = {
      'geminiApiKey': 'key',
      'parentalPin': 'pin',
      'opensubtitlesApiKey': 'other',
      'parentalControlEnabled': true,
      'language': 1,
    };
    expect(LanTransferPolicy.publicSettings(values), {'language': 1});
    expect(
      LanTransferPolicy.secrets(values).keys,
      unorderedEquals([
        'geminiApiKey',
        'parentalPin',
        'opensubtitlesApiKey',
        'parentalControlEnabled',
      ]),
    );
    expect(values, contains('geminiApiKey'));
  });
  test('bounded reader preserves UTF-8 split across network chunks', () async {
    final body = utf8.encode('{"name":"Türkçe"}');
    final result = await readLanJson(
      Stream.fromIterable([
        for (final byte in body) [byte],
      ]),
    );
    expect(result['name'], 'Türkçe');
  });
  test('chunked overflow cancels request without reading the rest', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final result = readLanJson(stream.stream, maxBytes: 4);
    final check = expectLater(result, throwsA(isA<LanPayloadTooLarge>()));
    stream.add([1, 2, 3]);
    stream.add([4, 5]);
    await check;
    expect(cancelled, true);
    await stream.close();
  });
  test('total deadline also limits a continuously trickling body', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => stream.add([32]),
    );
    await expectLater(
      readLanJson(stream.stream, timeout: const Duration(milliseconds: 35)),
      throwsA(isA<TimeoutException>()),
    );
    timer.cancel();
    expect(cancelled, true);
    await stream.close();
  });
  test('non-object payload cannot reach import', () async {
    await expectLater(
      readLanJson(Stream.value(utf8.encode('[]'))),
      throwsFormatException,
    );
  });
}
