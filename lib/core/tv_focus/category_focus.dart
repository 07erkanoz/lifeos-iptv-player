import 'package:flutter/widgets.dart';

/// Focus the selected category only while its lazy list item is mounted.
/// A detached FocusNode can still report canRequestFocus, but requesting it
/// does not move focus and leaves the remote apparently unresponsive.
bool focusMountedCategory(FocusNode selected, FocusNode fallback) {
  if (selected.context?.mounted == true && selected.canRequestFocus) {
    selected.requestFocus();
    return true;
  }
  if (fallback.context?.mounted == true && fallback.canRequestFocus) {
    fallback.requestFocus();
    return true;
  }
  return false;
}
