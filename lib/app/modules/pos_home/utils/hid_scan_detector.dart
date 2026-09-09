import 'package:flutter/services.dart';

/// Detects a keyboard-wedge (HID) barcode scanner acting as a hardware
/// keyboard: it "types" the barcode's characters as fast keystrokes followed
/// by Enter, indistinguishable at the widget level from a human typing —
/// except for speed. There's no dedicated HID-scanner plugin in this app, so
/// this is a timing heuristic: a burst of characters typed close enough
/// together (under [_maxInterKeyGap]) and terminated by Enter is treated as
/// a scan; anything slower is left alone as ordinary typing.
///
/// Call [start] once (e.g. `PosHomeController.onInit`) and [stop] when done
/// (`onClose`). [isArmed] gates whether keystrokes are currently being
/// captured — the caller should keep it false while a text field has focus
/// or while a sheet/dialog is open on top of the screen, so this never
/// double-fires against intentional typing.
class HidScanDetector {
  HidScanDetector({required this.isArmed, required this.onScan});

  /// Returns true only when it's safe to intercept keystrokes right now
  /// (POS Home is the foreground screen, no text field focused, no
  /// sheet/dialog open).
  final bool Function() isArmed;

  /// Called with the completed barcode once a fast burst + Enter is seen.
  final void Function(String barcode) onScan;

  static const _maxInterKeyGap = Duration(milliseconds: 60);
  static const _minBarcodeLength = 4;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;
  bool _looksLikeScan = true;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!isArmed()) {
      _reset();
      return false;
    }

    final now = DateTime.now();
    if (_lastKeyAt != null && now.difference(_lastKeyAt!) > _maxInterKeyGap) {
      // Gap too long since the last key — this isn't a scanner burst
      // (or it's the start of a new one); drop whatever was buffered.
      _reset();
    }
    _lastKeyAt = now;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      final wasLikelyScan = _looksLikeScan && code.length >= _minBarcodeLength;
      _reset();
      if (wasLikelyScan) {
        onScan(code);
        return true;
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.trim().isNotEmpty) {
      _buffer.write(char);
    } else {
      // A non-character key (shift, arrows, etc.) mid-sequence means this
      // isn't a plain barcode burst.
      _looksLikeScan = false;
    }
    return false;
  }

  void _reset() {
    _buffer.clear();
    _lastKeyAt = null;
    _looksLikeScan = true;
  }
}
