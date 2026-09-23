/// Coalesces visible-row EPG requests without permanently caching a failure.
/// Each provider container owns a gate; identities include the account.
class EpgRequestGate {
  EpgRequestGate({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _pending = <(int, int), Future<void>>{};
  final _retryAfter = <(int, int), DateTime>{};

  Future<void> request(
    int accountId,
    int channelId,
    Future<bool> Function() load,
  ) {
    final key = (accountId, channelId);
    final pending = _pending[key];
    if (pending != null) return pending;
    final retry = _retryAfter[key];
    if (retry != null && _now().isBefore(retry)) return Future.value();
    late final Future<void> job;
    job = Future<bool>.sync(load)
        .then<void>(
          (success) {
            _remember(
              key,
              success
                  ? const Duration(minutes: 5)
                  : const Duration(seconds: 30),
            );
          },
          onError: (Object _, StackTrace _) {
            _remember(key, const Duration(seconds: 30));
          },
        )
        .whenComplete(() {
          if (identical(_pending[key], job)) _pending.remove(key);
        });
    _pending[key] = job;
    return job;
  }

  void _remember((int, int) key, Duration duration) {
    _retryAfter.remove(key);
    if (_retryAfter.length >= 4096) _retryAfter.remove(_retryAfter.keys.first);
    _retryAfter[key] = _now().add(duration);
  }
}
