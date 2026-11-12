import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G5.6 — the receipt logo as thermal printers need it: a 1-bit (black / white) bitmap, dithered (Floyd–Steinberg) so photos and soft edges still
/// read, sized for the paper (58 mm: 256 dots wide; 80 mm: 384 dots — about two thirds of the printable width), packed 8 dots per byte, MSB first.
class LogoBitmap {
  const LogoBitmap({required this.width, required this.height, required this.bits});
  final int width; // a multiple of 8
  final int height;
  final Uint8List bits; // (width / 8) * height bytes; 1 = black dot

  int get bytesPerRow => width ~/ 8;
  bool dot(int x, int y) => (bits[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// ESC/POS: centre, `GS v 0` raster (normal density), back to left alignment.
  List<int> escPos() {
    final w = bytesPerRow;
    return [
      0x1B, 0x61, 0x01, // ESC a 1 — centre
      0x1D, 0x76, 0x30, 0x00, w & 0xFF, (w >> 8) & 0xFF, height & 0xFF, (height >> 8) & 0xFF,
      ...bits,
      0x0A,
      0x1B, 0x61, 0x00, // ESC a 0 — left
    ];
  }

  /// For the on-screen preview (exactly the dots that will print).
  Uint8List toRgba() {
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final v = dot(x, y) ? 0 : 255;
        out[i] = v;
        out[i + 1] = v;
        out[i + 2] = v;
        out[i + 3] = 255;
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'w': width, 'h': height, 'b': base64Encode(bits)};
  static LogoBitmap? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return LogoBitmap(width: j['w'] as int, height: j['h'] as int, bits: base64Decode(j['b'] as String));
    } catch (_) {
      return null;
    }
  }
}

class ReceiptLogo {
  ReceiptLogo._();

  static const maxHeight = 240; // dots — a logo, not a poster
  static int widthFor(int paperMm) => paperMm == 58 ? 256 : 384;

  /// Pure: RGBA pixels → dithered 1-bit bitmap. Transparent pixels count as white (paper).
  @visibleForTesting
  static LogoBitmap dither(Uint8List rgba, int width, int height) {
    final w8 = (width + 7) & ~7;
    final lum = Float32List(w8 * height)..fillRange(0, w8 * height, 255);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final a = rgba[i + 3] / 255.0;
        final l = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
        lum[y * w8 + x] = l * a + 255 * (1 - a);
      }
    }
    final bits = Uint8List((w8 ~/ 8) * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < w8; x++) {
        final i = y * w8 + x;
        final old = lum[i];
        final black = old < 128;
        if (black) bits[y * (w8 ~/ 8) + (x >> 3)] |= 0x80 >> (x & 7);
        final err = old - (black ? 0 : 255);
        if (x + 1 < w8) lum[i + 1] += err * 7 / 16;
        if (y + 1 < height) {
          if (x > 0) lum[i + w8 - 1] += err * 3 / 16;
          lum[i + w8] += err * 5 / 16;
          if (x + 1 < w8) lum[i + w8 + 1] += err * 1 / 16;
        }
      }
    }
    return LogoBitmap(width: w8, height: height, bits: bits);
  }

  /// Image file bytes (PNG / JPEG / WebP) → the bitmap for [paperMm]. Null when the bytes are not an image.
  static Future<LogoBitmap?> fromImageBytes(Uint8List bytes, {required int paperMm}) async {
    try {
      final probe = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
      final iw = probe.image.width, ih = probe.image.height;
      probe.image.dispose();
      if (iw <= 0 || ih <= 0) return null;
      var tw = widthFor(paperMm);
      var th = (ih * tw / iw).round();
      if (th > maxHeight) {
        th = maxHeight;
        tw = (iw * th / ih).round();
      }
      final frame = await (await ui.instantiateImageCodec(bytes, targetWidth: tw, targetHeight: th)).getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = frame.image.width, h = frame.image.height;
      frame.image.dispose();
      if (data == null) return null;
      return dither(data.buffer.asUint8List(), w, h);
    } catch (_) {
      return null;
    }
  }
}

/// The till's cache of the store's receipt logo bitmaps (per URL and paper width). Filled when settings load ([warm]); the receipt builder only READS
/// it, so printing never waits on the network. A changed logo has a new URL, so old entries simply stop being used.
class ReceiptLogoStore {
  ReceiptLogoStore._();
  static final Map<String, LogoBitmap> _mem = {};
  static Dio dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 15), responseType: ResponseType.bytes));
  static String _key(String url, int mm) => 'receipt_logo_v1:$mm:$url';

  static LogoBitmap? cached(String? url, int paperMm) => url == null ? null : _mem[_key(url, paperMm)];

  /// Loads from the device cache, else downloads and converts. Never throws.
  static Future<LogoBitmap?> warm(String? url, int paperMm) async {
    if (url == null || !url.startsWith('https://')) return null;
    final k = _key(url, paperMm);
    if (_mem[k] != null) return _mem[k];
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(k);
      final fromDisk = saved == null ? null : LogoBitmap.fromJson(jsonDecode(saved));
      if (fromDisk != null) return _mem[k] = fromDisk;
      final res = await dio.get<List<int>>(url);
      final data = res.data;
      if (data == null) return null;
      final bmp = await ReceiptLogo.fromImageBytes(Uint8List.fromList(data), paperMm: paperMm);
      if (bmp == null) return null;
      _mem[k] = bmp;
      await prefs.setString(k, jsonEncode(bmp.toJson()));
      return bmp;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void put(String url, int paperMm, LogoBitmap b) => _mem[_key(url, paperMm)] = b;
  @visibleForTesting
  static void clear() => _mem.clear();
}
