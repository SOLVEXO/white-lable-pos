import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';
import 'brand_logo.dart';
import 'ink_scope.dart';

/// Always-dark brand panel for the login split layout: a slow gradient "mesh"
/// (three drifting radial gradients, painted — no blur, no shaders beyond
/// gradients) behind the logo, name and value props. Static under reduced motion.
class BrandPanel extends StatefulWidget {
  const BrandPanel({
    super.key,
    required this.title,
    required this.tagline,
    this.points = const [],
  });
  final String title;
  final String tagline;
  final List<String> points;

  @override
  State<BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<BrandPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduced(context);
    if (!reduced && !_started) {
      _c.repeat();
      _started = true;
    } else if (reduced && _started) {
      _c.stop();
      _started = false;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkScope(
      child: Builder(
        builder: (context) {
          final p = context.palette;
          // Clip: the radial blobs are larger than the panel and must not bleed into the form beside it.
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(painter: BrandMeshPainter(_c, p)),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const BrandLogo(size: 96),
                        const SizedBox(height: Space.s6),
                        Text(
                          widget.title,
                          style: context.type.display.copyWith(
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Space.s2),
                        Text(
                          widget.tagline,
                          style: context.type.subtitle.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Space.s8),
                        for (final t in widget.points)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.s3),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: p.accent,
                                ),
                                const SizedBox(width: Space.s3),
                                Expanded(
                                  child: Text(
                                    t,
                                    style: context.type.body.copyWith(
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints the panel's slow gradient mesh: three drifting radial blobs over the ink background, then a scrim.
///
/// The scrim exists for contrast: where all three blobs overlap, the raw mix is bright enough to drop the
/// secondary text on the panel below 4.5:1. [scrimAlpha] is tuned (and test-checked by sampling the painted
/// pixels over the whole animation, test/brand_panel_contrast_test.dart) so that never happens.
class BrandMeshPainter extends CustomPainter {
  BrandMeshPainter(this.t, this.p) : super(repaint: t);
  final Animation<double> t;
  final AppPalette p;

  /// Opaque-ink overlay painted last, over the blobs.
  static const double scrimAlpha = 0.38;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = p.background);
    final a = t.value * 2 * math.pi;
    void blob(
      Color color,
      double alpha,
      double fx,
      double fy,
      double phase,
      double radius,
    ) {
      final c = Offset(
        size.width * (0.5 + 0.38 * math.sin(a * fx + phase)),
        size.height * (0.5 + 0.38 * math.cos(a * fy + phase * 1.3)),
      );
      final r = size.shortestSide * radius;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    blob(p.accent, 0.28, 1, 1, 0, 0.85);
    blob(p.info, 0.22, 1, 2, 2.1, 0.8);
    blob(p.accentStrong, 0.26, 2, 1, 4.2, 0.7);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = p.background.withValues(alpha: scrimAlpha),
    );
  }

  @override
  bool shouldRepaint(BrandMeshPainter o) => o.p != p;
}
