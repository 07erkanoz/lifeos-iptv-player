import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:lifeostv/core/platform_helper.dart';

/// A frosted-glass wrapper that **drops the blur on Android TV**.
///
/// `BackdropFilter` + `ImageFilter.blur` forces a full-screen GPU
/// readback + gaussian pass every frame. On a desktop/phone GPU that's
/// fine; on the weak GPUs in most Android TV boxes/sticks it's one of
/// the single biggest causes of jank — especially for overlays drawn
/// ON TOP of live video (channel list, EPG), where the blur composites
/// over a decoding video surface every frame.
///
/// On TV we render the child as-is (the caller's semi-opaque tint
/// container stays, so panels are still readable) and skip the blur
/// entirely. Everywhere else we keep the real frosted blur.
class Frosted extends StatelessWidget {
  final double sigma;
  final Widget child;

  const Frosted({super.key, required this.sigma, required this.child});

  @override
  Widget build(BuildContext context) {
    if (PlatformHelper.isTV) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}
