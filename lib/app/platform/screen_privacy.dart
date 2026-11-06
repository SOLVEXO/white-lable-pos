import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a sensitive screen out of screenshots, screen recordings and the recent-apps thumbnail.
/// Android: `FLAG_SECURE` on the window (native side in MainActivity). iOS has no such switch — there the screen is covered while the app
/// is inactive (see `PrivacyCurtain`), which hides it from the app switcher. Tests / unsupported platforms: a no-op that records calls.
class ScreenPrivacy {
  ScreenPrivacy._();
  static const _channel = MethodChannel('solvexo/screen_privacy');

  /// How many sensitive screens currently ask for protection (a count, so two overlapping screens cannot switch it off early).
  static int _holders = 0;
  @visibleForTesting
  static int get holders => _holders;

  /// Set by tests to observe the native calls.
  @visibleForTesting
  static final List<bool> calls = [];

  @visibleForTesting
  static void reset() {
    _holders = 0;
    calls.clear();
  }

  static Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  static Future<void> _set(bool secure) async {
    calls.add(secure);
    try {
      if (!kIsWeb && Platform.isAndroid) await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {
      // a platform without the channel (tests, desktop): nothing to protect there
    }
  }
}
