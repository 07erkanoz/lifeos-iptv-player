/// Native callbacks must be detached while the Flutter isolate is still alive.
/// Also tracks disposals already started by a route or preview disappearing.
class MediaResourceRegistry {
  final Map<Object, Future<void> Function()> _resources = {};
  Future<void>? _shutdown;
  bool get isClosing => _shutdown != null;

  void register(Object resource, Future<void> Function() close) {
    if (isClosing) throw StateError('Media shutdown is in progress');
    _resources[resource] = close;
  }

  void unregister(Object resource) => _resources.remove(resource);

  Future<void> closeAll() => _shutdown ??= Future<void>(() async {
    await Future.wait(_resources.values.toList().map((close) => close()));
  });
}

final mediaResourceRegistry = MediaResourceRegistry();
