import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/core/media_resource_registry.dart';

void main() {
  test(
    'shutdown waits for active and already disposing media before exit',
    () async {
      final registry = MediaResourceRegistry();
      final active = Completer<void>(), disposing = Completer<void>();
      registry.register(Object(), () => active.future);
      registry.register(Object(), () => disposing.future);
      var exited = false;
      final close = registry.closeAll().then((_) => exited = true);
      await Future<void>.delayed(Duration.zero);
      active.complete();
      await Future<void>.delayed(Duration.zero);
      expect(exited, false);
      disposing.complete();
      await close;
      expect(exited, true);
    },
  );
  test(
    'repeated close coalesces and late player creation is rejected',
    () async {
      final registry = MediaResourceRegistry();
      var count = 0;
      registry.register(Object(), () async => count++);
      final first = registry.closeAll();
      expect(identical(first, registry.closeAll()), true);
      expect(() => registry.register(Object(), () async {}), throwsStateError);
      await first;
      expect(count, 1);
    },
  );
  test('failed cleanup does not authorize engine exit', () async {
    final registry = MediaResourceRegistry();
    registry.register(Object(), () async => throw StateError('native cleanup'));
    await expectLater(registry.closeAll(), throwsStateError);
  });
}
