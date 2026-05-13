import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tv_focus_registry.dart';

/// Shared DI for the focus registry. Held as a plain `Provider` (not a
/// notifier) because the registry is mutable and intentionally does NOT
/// drive rebuilds — consumers just read the instance and call its
/// imperative methods.
final tvFocusRegistryProvider = Provider<TvFocusRegistry>((ref) {
  return TvFocusRegistry();
});
