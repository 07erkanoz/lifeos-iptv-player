import 'package:riverpod/riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

// ═══════════════════════════════════════════════════════════════════
//  Pending Detail Channel
// ═══════════════════════════════════════════════════════════════════

class PendingDetailChannelNotifier extends Notifier<Channel?> {
  @override
  Channel? build() => null;

  void set(Channel? channel) => state = channel;
  void clear() => state = null;
}

/// When Dashboard wants to open a movie/series detail, it sets this provider.
/// The corresponding screen (MoviesScreen/SeriesScreen) watches it and opens
/// the detail panel automatically.
final pendingDetailChannelProvider =
    NotifierProvider<PendingDetailChannelNotifier, Channel?>(
  PendingDetailChannelNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════
//  Back Handler (for detail panels)
// ═══════════════════════════════════════════════════════════════════

class BackHandlerNotifier extends Notifier<bool Function()?> {
  @override
  bool Function()? build() => null;

  void set(bool Function()? handler) => state = handler;
  void clear() => state = null;
}

/// The currently active screen can register a "back handler" callback.
/// When set, AppShell will call this first instead of its default back logic.
/// If the callback returns true, it means the screen handled the back event.
/// Returns false if the screen didn't handle it (no detail open, etc.)
final backHandlerProvider =
    NotifierProvider<BackHandlerNotifier, bool Function()?>(
  BackHandlerNotifier.new,
);
