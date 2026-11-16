import 'dart:io';

/// Small platform helpers. (G6.3: the legacy dialog / bottom-sheet / time-picker helpers that lived here had no callers and were
/// removed with the legacy UI kit; dialogs and sheets are `AppDialog` / `AppBottomSheet` from the design system.)
class Util {
  /// "ios" or "android" — sent to the API as the `Platform` header.
  static String deviceType() => Platform.isIOS ? 'ios' : 'android';
}
