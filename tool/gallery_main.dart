// Standalone entry point to run the design gallery in --profile (the in-app /design-gallery route is debug-only).
//
//   flutter run --profile -t tool/gallery_main.dart -d <device-id>
//
// Scroll the page (especially the ProductTile grid). Every frame that takes longer than the 60 fps budget
// (16.7 ms for build or raster) is printed to the console as `SLOW FRAME …`, and a running total is printed every
// 5 seconds as `FRAMES …`. Not part of the shipped app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/core/design/gallery/design_gallery_view.dart';

int _frames = 0;
int _slow = 0;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      _frames++;
      final build = t.buildDuration.inMicroseconds / 1000;
      final raster = t.rasterDuration.inMicroseconds / 1000;
      if (build > 16.7 || raster > 16.7) {
        _slow++;
        debugPrint('SLOW FRAME build=${build.toStringAsFixed(1)}ms raster=${raster.toStringAsFixed(1)}ms total=${(t.totalSpan.inMicroseconds / 1000).toStringAsFixed(1)}ms');
      }
    }
  });
  Timer.periodic(const Duration(seconds: 5), (_) {
    if (_frames > 0) debugPrint('FRAMES total=$_frames slow(>16.7ms)=$_slow (${(100 * _slow / _frames).toStringAsFixed(1)}%)');
  });
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.light, darkTheme: AppTheme.dark, home: const DesignGalleryView()));
}
