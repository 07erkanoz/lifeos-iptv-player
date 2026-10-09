/// Resume only the source that was playing before a system interruption.
/// Backgrounding, explicit user input and unplugging headphones revoke it.
class AudioInterruptionPolicy {
  int? _resumeSource;
  bool _interrupted = false;
  void begin({
    required bool playing,
    required int source,
    required bool foreground,
  }) {
    if (_interrupted) return;
    _interrupted = true;
    _resumeSource = playing && foreground ? source : null;
  }

  void revokeResume() => _resumeSource = null;
  bool end({
    required bool shouldResume,
    required int source,
    required bool foreground,
  }) {
    final resume =
        _interrupted && shouldResume && foreground && _resumeSource == source;
    _interrupted = false;
    _resumeSource = null;
    return resume;
  }
}
