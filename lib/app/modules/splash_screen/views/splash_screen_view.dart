import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/splash_screen/controllers/splash_screen_controller.dart';
import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Always dark ink, whatever the app theme. Frame 0 is the native splash, pixel
/// for pixel: #0B1020 and the 120-logical-px logo tile dead centre (the same PNG
/// the native splash uses). From there: an accent ring traces the tile, a soft
/// glow breathes behind it, the wordmark rises in, and a receipt-ticker line
/// runs underneath. 1.0 s (about 1.45 s to the next screen on a simulator, debug build). Reduced motion: wordmark fade only.
class SplashScreenView extends StatefulWidget {
  const SplashScreenView({super.key});

  /// The NATIVE splash colour (pubspec flutter_native_splash). The native splash and launcher icon are not regenerated yet
  /// (waiting for the vector/1024 logo master), so frame 0 must keep matching it exactly — the app's dark palette now
  /// uses the blueprint ink instead.
  static const Color nativeSplashInk = Color(0xFF0B1020);

  @override
  State<SplashScreenView> createState() => _SplashScreenViewState();
}

class _SplashScreenViewState extends State<SplashScreenView> {
  static const double _tile = 120;
  final SplashScreenController _c = Get.find<SplashScreenController>();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = Motion.reduced(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _c.start(reducedMotion: reduced),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkScope(
      lightStatusBar: true,
      child: Builder(
        builder: (context) {
          final p = context.palette;
          final reduced = Motion.reduced(context);
          return Scaffold(
            backgroundColor: SplashScreenView.nativeSplashInk,
            body: Semantics(
              label: '${AppBrand.posName}, loading',
              child: LayoutBuilder(
                builder: (context, box) {
                  final cy = box.maxHeight / 2;
                  return Stack(
                    children: [
                      // Glow + ring: painted behind/around the tile, driven by the timeline.
                      if (!reduced)
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _HaloPainter(_c.animation, p, _tile),
                            ),
                          ),
                        ),
                      // The tile itself — dead centre, exactly like the native splash.
                      Center(
                        child: AnimatedBuilder(
                          animation: _c.animation,
                          builder: (context, child) {
                            final t = _c.animation.value;
                            final pulse = reduced
                                ? 1.0
                                : 1 +
                                      0.035 *
                                          math.sin(
                                            math.pi * _span(t, 0.30, 0.70),
                                          );
                            return Transform.scale(scale: pulse, child: child);
                          },
                          child: const BrandLogo(size: _tile),
                        ),
                      ),
                      // Wordmark + ticker.
                      Positioned(
                        top: cy + _tile / 2 + Space.s6,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: _c.animation,
                          builder: (context, _) {
                            final t = _c.animation.value;
                            final wm = Curves.easeOut.transform(
                              _span(t, reduced ? 0 : 0.35, reduced ? 1 : 0.75),
                            );
                            final rise = reduced
                                ? 0.0
                                : (1 -
                                          Motion.emphasized.transform(
                                            _span(t, 0.35, 0.75),
                                          )) *
                                      16;
                            return Column(
                              children: [
                                Opacity(
                                  opacity: wm,
                                  child: Transform.translate(
                                    offset: Offset(0, rise),
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: 'Solvexo',
                                            style: context.type.headline
                                                .copyWith(
                                                  color: p.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          TextSpan(
                                            text: ' POS',
                                            style: context.type.headline
                                                .copyWith(
                                                  color: p.accent,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: Space.s4),
                                Opacity(
                                  opacity: wm,
                                  child: SizedBox(
                                    width: 112,
                                    height: 6,
                                    child: CustomPaint(
                                      painter: _TickerPainter(
                                        reduced ? 1 : _span(t, 0.6, 1.0),
                                        p,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Maps [t] from [a, b] onto 0..1, clamped.
double _span(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Soft accent glow behind the tile + a ring that traces the tile's outline.
class _HaloPainter extends CustomPainter {
  _HaloPainter(this.t, this.p, this.tile) : super(repaint: t);
  final Animation<double> t;
  final AppPalette p;
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final center = size.center(Offset.zero);

    // Glow: breathes in and out between 0.15 and 0.75 of the timeline.
    final g = math.sin(math.pi * _span(v, 0.15, 0.75));
    if (g > 0) {
      final r = tile * 1.35;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              p.accent.withValues(alpha: 0.30 * g),
              p.accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // Ring: draws clockwise from the top over the first ~55 %, then fades away.
    final draw = Curves.easeOutCubic.transform(_span(v, 0.0, 0.55));
    final fade = 1 - _span(v, 0.55, 0.85);
    if (draw > 0 && fade > 0) {
      const gap = 12.0;
      final side = tile + gap * 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: side, height: side),
        Radius.circular(tile * 0.22 + gap),
      );
      // Start at the top-centre: build the outline there explicitly.
      final path = Path()..moveTo(rrect.left + rrect.tlRadiusX, rrect.top);
      path.lineTo(rrect.right - rrect.trRadiusX, rrect.top);
      path.arcToPoint(
        Offset(rrect.right, rrect.top + rrect.trRadiusY),
        radius: Radius.circular(rrect.trRadiusX),
      );
      path.lineTo(rrect.right, rrect.bottom - rrect.brRadiusY);
      path.arcToPoint(
        Offset(rrect.right - rrect.brRadiusX, rrect.bottom),
        radius: Radius.circular(rrect.brRadiusX),
      );
      path.lineTo(rrect.left + rrect.blRadiusX, rrect.bottom);
      path.arcToPoint(
        Offset(rrect.left, rrect.bottom - rrect.blRadiusY),
        radius: Radius.circular(rrect.blRadiusX),
      );
      path.lineTo(rrect.left, rrect.top + rrect.tlRadiusY);
      path.arcToPoint(
        Offset(rrect.left + rrect.tlRadiusX, rrect.top),
        radius: Radius.circular(rrect.tlRadiusX),
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = p.accent.withValues(alpha: fade);
      for (final PathMetric m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * draw), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HaloPainter o) => o.p != p || o.tile != tile;
}

/// Thin dashed "receipt ticker" line that reveals left → right with a bright head.
class _TickerPainter extends CustomPainter {
  _TickerPainter(this.progress, this.p);
  final double progress;
  final AppPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final reveal = size.width * progress;
    final dash = Paint()
      ..color = p.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double x = 1; x < reveal; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 6, reveal), y), dash);
    }
    if (progress > 0 && progress < 1) {
      canvas.drawLine(
        Offset(math.max(0, reveal - 18), y),
        Offset(reveal, y),
        Paint()
          ..color = p.accent
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_TickerPainter o) => o.progress != progress || o.p != p;
}
