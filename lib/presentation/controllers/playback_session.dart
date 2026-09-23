/// Owns asynchronous setup/open/dispose ordering for a single native player.
/// Pending opens are coalesced; closing invalidates setup and queued opens
/// before native resources are released exactly once.
class PlaybackSession {
  PlaybackSession({
    required this.initialize,
    required this.openMedia,
    required this.disposePlayer,
  });

  final Future<void> Function() initialize;
  final Future<void> Function(String url) openMedia;
  final Future<void> Function() disposePlayer;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _initialized = false;
  bool isClosed = false;
  int _generation = 0;

  Future<bool> open(String url) {
    final generation = ++_generation;
    final result = _tail.then((_) async {
      if (isClosed || generation != _generation) return false;
      if (!_initialized) {
        await initialize();
        _initialized = true;
      }
      if (isClosed || generation != _generation) return false;
      await openMedia(url);
      return !isClosed && generation == _generation;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> close() {
    isClosed = true;
    ++_generation;
    return _closing ??= _tail.then((_) => disposePlayer());
  }
}
