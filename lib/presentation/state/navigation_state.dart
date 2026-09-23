import 'package:flutter_riverpod/flutter_riverpod.dart';
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
