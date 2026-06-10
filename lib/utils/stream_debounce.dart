import 'dart:async';

extension CoalesceStream<T> on Stream<T> {
  /// Emits the FIRST event immediately (no added first-paint latency),
  /// then coalesces any burst that follows: while new events keep
  /// arriving within [window], only the latest is emitted, once the
  /// burst goes quiet for [window].
  ///
  /// Drift `.watch()` re-fires on every write to a table the query
  /// reads. An Xtream/M3U catalogue refresh writes `channels` in
  /// hundreds of batches, so an un-coalesced grid/dashboard watch would
  /// re-run (re-transfer thousands of rows across the DB isolate +
  /// re-merge + rebuild) hundreds of times during a sync. Coalescing
  /// turns that storm into one initial paint plus one trailing update.
  Stream<T> coalesce(Duration window) {
    Timer? timer;
    T? latest;
    var hasLatest = false;
    var emittedOnce = false;
    StreamSubscription<T>? sub;
    late StreamController<T> controller;

    void flush() {
      if (hasLatest) {
        hasLatest = false;
        controller.add(latest as T);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = listen(
          (v) {
            if (!emittedOnce) {
              emittedOnce = true;
              controller.add(v); // first value straight through
              return;
            }
            latest = v;
            hasLatest = true;
            timer?.cancel();
            timer = Timer(window, flush);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            flush();
            controller.close();
          },
        );
      },
      onCancel: () {
        timer?.cancel();
        return sub?.cancel();
      },
    );
    return controller.stream;
  }
}
