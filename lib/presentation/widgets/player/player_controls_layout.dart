import 'package:flutter/material.dart';

/// The information panel uses remaining space; the footer always stays at the
/// bottom, including while paused and when the panel is taller than the window.
class PlayerControlsLayout extends StatelessWidget {
  const PlayerControlsLayout({
    super.key,
    required this.topBar,
    required this.bottomBar,
    this.infoPanel,
  });
  final Widget topBar, bottomBar;
  final Widget? infoPanel;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      topBar,
      Expanded(
        child: Align(
          alignment: Alignment.bottomLeft,
          child: infoPanel == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SingleChildScrollView(child: infoPanel),
                ),
        ),
      ),
      bottomBar,
    ],
  );
}
