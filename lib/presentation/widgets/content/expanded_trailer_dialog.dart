import 'package:flutter/material.dart';
import 'package:lifeostv/presentation/widgets/content/backdrop_trailer.dart';

/// Compute the largest 16:9 box that fits inside [viewport] with
/// [scale] (0–1) of each dimension as a margin. Returns a (width,
/// height) record at the chosen size.
///
/// Pulled out of [showExpandedTrailer] so the letter-boxing math
/// can be unit-tested without standing up a media_kit Player (which
/// doesn't initialise in the test environment).
({double width, double height}) computeExpandedTrailerSize(
  Size viewport, {
  double scale = 0.9,
}) {
  final maxW = viewport.width * scale;
  final maxH = viewport.height * scale;
  double w = maxW;
  double h = w * 9 / 16;
  if (h > maxH) {
    h = maxH;
    w = h * 16 / 9;
  }
  return (width: w, height: h);
}

/// Opens a fullscreen modal showing the YouTube trailer at the largest
/// 16:9 size that fits the viewport, with sound on. The compact PiP
/// player on the detail page keeps running behind the dialog — its
/// cached extraction means this dialog plays back nearly instantly.
///
/// Dismissed by tap on the dim background, the close button, or Esc.
Future<void> showExpandedTrailer(
  BuildContext context, {
  required String? directTrailerRef,
  required String searchTitle,
  required String? searchYear,
  required String channelType,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    builder: (ctx) {
      final size = computeExpandedTrailerSize(MediaQuery.of(ctx).size);
      final w = size.width;
      final h = size.height;
      return Stack(
        children: [
          // Tap anywhere outside the video to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
          Center(
            child: SizedBox(
              width: w,
              height: h,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropTrailer(
                  backdropUrl: null,
                  directTrailerRef: directTrailerRef,
                  searchTitle: searchTitle,
                  searchYear: searchYear,
                  channelType: channelType,
                  showBackdrop: false,
                  muted: false,
                  delay: Duration.zero,
                ),
              ),
            ),
          ),
          Positioned(
            top: 24,
            right: 24,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
                tooltip: 'Kapat',
              ),
            ),
          ),
        ],
      );
    },
  );
}
