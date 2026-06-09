import 'package:flutter/foundation.dart';

/// Global flag: `true` while a full-screen video player is alive.
///
/// The app does main-isolate background work on timers — catalogue
/// enrichment + embeddings (Gemini HTTP + Drift batch writes + vector
/// math), LAN auto-sync (mDNS + Drift merges), and EPG sync. On the
/// main isolate those block the UI thread for a beat, which shows up
/// as periodic stutter in the player every ~45 s.
///
/// The player flips this on while it's mounted; the background passes
/// check it and skip while a video is playing, resuming on the next
/// tick once playback ends. Cheap, global, no provider plumbing needed
/// across the player ↔ app-root boundary.
final ValueNotifier<bool> playbackActiveNotifier = ValueNotifier<bool>(false);
