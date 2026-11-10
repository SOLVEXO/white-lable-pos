import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Shared bits of the hand-drawn chart toolkit (owner decision: no chart package). Colours always come from the design-system palette, so the
/// charts follow light / dark mode; text is laid out with the ambient [TextScaler], so it grows with the user's text size.
class ChartStyle {
  const ChartStyle({
    required this.bar,
    required this.barSelected,
    required this.previous,
    required this.grid,
    required this.axisText,
    required this.bubble,
    required this.onBubble,
    required this.series,
    required this.textScaler,
    required this.labelStyle,
  });

  final Color bar, barSelected, previous, grid, axisText, bubble, onBubble;

  /// categorical colours (donut slices): distinct palette tones
  final List<Color> series;
  final TextScaler textScaler;
  final TextStyle labelStyle;

  factory ChartStyle.of(BuildContext context) {
    final p = context.palette;
    return ChartStyle(
      bar: p.accent,
      barSelected: p.accentFill,
      previous: p.textMuted,
      grid: p.border,
      axisText: p.textSecondary,
      bubble: p.textPrimary,
      onBubble: p.surface,
      series: [p.accentFill, p.info, p.success, p.warning, p.danger, p.textMuted, p.accent, p.infoFg],
      textScaler: MediaQuery.textScalerOf(context),
      labelStyle: context.type.caption,
    );
  }
}

/// Paints [text] at [at]; [align] 0 = left edge at x, 0.5 = centred, 1 = right edge at x. Returns the laid-out size.
Size paintChartText(Canvas canvas, String text, Offset at, {required TextStyle style, required TextScaler scaler, double align = 0, double maxWidth = double.infinity}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  tp.paint(canvas, Offset(at.dx - tp.width * align, at.dy));
  return tp.size;
}

Size measureChartText(String text, {required TextStyle style, required TextScaler scaler}) => (TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
  textScaler: scaler,
  maxLines: 1,
)..layout()).size;

/// A rounded "nice" maximum for an axis (1, 2, 2.5, 5 × 10ⁿ above [v]).
double niceMax(double v) {
  if (v <= 0) return 1;
  var mag = 1.0;
  while (mag * 10 <= v) {
    mag *= 10;
  }
  while (mag > v) {
    mag /= 10;
  }
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * mag >= v) return m * mag;
  }
  return 10 * mag;
}

/// A dashed stroke along [path] (the non-colour cue of the "previous period" series).
void drawDashedPath(Canvas canvas, Path path, Paint paint, {double dash = 6, double gap = 4}) {
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      canvas.drawPath(metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
      d += dash + gap;
    }
  }
}

/// A small legend row: a swatch drawn as a solid or dashed line, and its words (the words are the cue — never colour alone).
class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({super.key, required this.label, required this.color, this.dashed = false, this.square = false});
  final String label;
  final Color color;
  final bool dashed, square;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: square ? 12 : 22,
        height: 12,
        child: CustomPaint(
          painter: _SwatchPainter(color, dashed: dashed, square: square),
        ),
      ),
      const SizedBox(width: Space.s1),
      Flexible(
        child: Text(label, style: context.type.caption.copyWith(color: context.palette.textSecondary)),
      ),
    ],
  );
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, {required this.dashed, required this.square});
  final Color color;
  final bool dashed, square;
  @override
  void paint(Canvas canvas, Size size) {
    if (square) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)), Paint()..color = color);
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    dashed ? drawDashedPath(canvas, path, paint, dash: 5, gap: 3) : canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.dashed != dashed;
}
