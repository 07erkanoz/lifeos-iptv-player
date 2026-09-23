import 'dart:async';

/// Keeps drag/D-pad previews separate from native seeks. Native calls are
/// serialized, with pending superseded targets and closed media discarded.
class PlaybackSeekController {
  PlaybackSeekController({
    required this.position,
    required this.duration,
    required this.seek,
    required this.onPreview,
    required this.onError,
  });

  final Duration Function() position;
  final Duration Function() duration;
  final Future<void> Function(Duration) seek;
  final void Function(Duration?) onPreview;
  final void Function() onError;
  Duration? preview;
  Timer? _timer;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false;

  static Duration clamp(Duration target, Duration duration) {
    if (duration <= Duration.zero || target < Duration.zero) {
      return Duration.zero;
    }
    return target > duration ? duration : target;
  }

  void updatePreview(Duration target) {
    if (_disposed || duration() <= Duration.zero) return;
    ++_generation;
    _timer?.cancel();
    preview = clamp(target, duration());
    onPreview(preview);
  }

  void nudge(Duration delta) {
    if (_disposed || duration() <= Duration.zero) return;
    updatePreview((preview ?? position()) + delta);
    _timer = Timer(const Duration(milliseconds: 400), () => commitPreview());
  }

  Future<void> commitPreview() async {
    final target = preview;
    if (target != null) await commit(target);
  }

  Future<void> commit(Duration target) {
    if (_disposed || duration() <= Duration.zero) return Future.value();
    updatePreview(target);
    final generation = _generation;
    final clamped = preview!;
    final result = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await seek(clamped);
      } catch (_) {
        if (!_disposed && generation == _generation) onError();
      } finally {
        if (!_disposed && generation == _generation) {
          preview = null;
          onPreview(null);
        }
      }
    });
    _tail = result;
    return result;
  }

  void cancel() {
    ++_generation;
    _timer?.cancel();
    preview = null;
    if (!_disposed) onPreview(null);
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
