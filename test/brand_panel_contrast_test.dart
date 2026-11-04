// The login brand panel is always dark ink with a slowly drifting gradient mesh behind white text. The text must stay
// readable at the WORST pixel the gradient ever produces (WCAG: body >= 4.5:1, large text >= 3:1).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/core/design/design.dart';

double _lin(num v) {
  final c = v / 255;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _lum(int r, int g, int b) =>
    0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);

double _contrastLum(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

double _lumOfColor(Color c) =>
    _lum((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

void main() {
  const size = Size(
    560,
    840,
  ); // a typical brand-panel size (left half of a tablet landscape screen)
  final p = AppPalette.dark;

  testWidgets(
    'worst pixel of the gradient (sampled across the whole 28 s loop) keeps the panel text readable',
    (t) async {
      double brightest = 0;
      int bx = 0, by = 0;
      double phaseOfWorst = 0;
      await t.runAsync(() async {
        for (var i = 0; i <= 56; i++) {
          final phase = i / 56; // 0..1 of the loop (0.5 s steps)
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec);
          BrandMeshPainter(
            AlwaysStoppedAnimation(phase),
            p,
          ).paint(canvas, size);
          final img = await rec.endRecording().toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          final data = (await img.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          for (var y = 0; y < size.height.toInt(); y += 2) {
            for (var x = 0; x < size.width.toInt(); x += 2) {
              final o = (y * size.width.toInt() + x) * 4;
              final l = _lum(
                data.getUint8(o),
                data.getUint8(o + 1),
                data.getUint8(o + 2),
              );
              if (l > brightest) {
                brightest = l;
                bx = x;
                by = y;
                phaseOfWorst = phase;
              }
            }
          }
          img.dispose();
        }
      });

      final secondary = _contrastLum(_lumOfColor(p.textSecondary), brightest);
      final primary = _contrastLum(_lumOfColor(p.textPrimary), brightest);
      // ignore: avoid_print
      print(
        'worst (brightest) pixel L=${brightest.toStringAsFixed(4)} at ($bx,$by) phase ${phaseOfWorst.toStringAsFixed(2)}  '
        '-> secondary ${secondary.toStringAsFixed(2)}:1, primary ${primary.toStringAsFixed(2)}:1',
      );
      expect(
        secondary,
        greaterThanOrEqualTo(4.5),
        reason: 'tagline + value points (body-size secondary text)',
      );
      expect(
        primary,
        greaterThanOrEqualTo(4.5),
        reason: 'title (large) would only need 3:1, body-size would need 4.5',
      );
      expect(primary, greaterThanOrEqualTo(3.0));
      // The accent check icons are graphics (3:1 needed).
      expect(
        _contrastLum(_lumOfColor(p.accent), brightest),
        greaterThanOrEqualTo(3.0),
      );
    },
  );

  test(
    'analytic upper bound: even with all three blobs fully overlapping at their centres, text passes',
    () {
      // Alpha-composite in painting order over the ink background, then the scrim.
      List<double> over(List<double> base, Color c, double a) => [
        for (var i = 0; i < 3; i++)
          base[i] * (1 - a) + [c.r, c.g, c.b][i] * 255 * a,
      ];
      var px = [
        p.background.r * 255,
        p.background.g * 255,
        p.background.b * 255,
      ];
      px = over(px, p.accent, 0.28);
      px = over(px, p.info, 0.22);
      px = over(px, p.accentStrong, 0.26);
      px = over(px, p.background, BrandMeshPainter.scrimAlpha);
      final l = _lum(px[0].round(), px[1].round(), px[2].round());
      expect(
        _contrastLum(_lumOfColor(p.textSecondary), l),
        greaterThanOrEqualTo(4.5),
      );
    },
  );
}
