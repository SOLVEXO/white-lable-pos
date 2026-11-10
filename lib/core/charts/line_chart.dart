import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/charts/chart_common.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A line / area chart of the current period, optionally over the previous period drawn DASHED (the dash, and the legend's words, are the cue —
/// not only the colour). Labels: first, middle and last point. The chart reads as one sentence to a screen reader ([semanticsLabel]).
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.current,
    required this.labels,
    required this.semanticsLabel,
    this.previous,
    this.axisLabel,
    this.height = 180,
    this.currentLabel = 'This period',
    this.previousLabel = 'Previous period',
  });
  final List<double> current;
  final List<double>? previous;

  /// one per point of [current]
  final List<String> labels;
  final String semanticsLabel;
  final String Function(double)? axisLabel;
  final double height;
  final String currentLabel, previousLabel;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: height * style.textScaler.scale(1).clamp(1.0, 1.6),
              width: double.infinity,
              child: CustomPaint(
                painter: _LinePainter(current: current, previous: previous, labels: labels, style: style, axisLabel: axisLabel ?? (v) => v.toStringAsFixed(0)),
              ),
            ),
            if (previous != null) ...[
              const SizedBox(height: Space.s2),
              Wrap(
                spacing: Space.s4,
                runSpacing: Space.s1,
                children: [
                  ChartLegendItem(label: currentLabel, color: style.barSelected),
                  ChartLegendItem(label: previousLabel, color: style.previous, dashed: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.current, required this.previous, required this.labels, required this.style, required this.axisLabel});
  final List<double> current;
  final List<double>? previous;
  final List<String> labels;
  final ChartStyle style;
  final String Function(double) axisLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (current.isEmpty) return;
    final ts = style.labelStyle.copyWith(color: style.axisText);
    final all = [...current, ...?previous];
    final max = niceMax(all.fold<double>(0, (m, v) => math.max(m, v)));
    final axisW = math.max(measureChartText(axisLabel(max), style: ts, scaler: style.textScaler).width, measureChartText(axisLabel(0), style: ts, scaler: style.textScaler).width) + 6;
    final labelH = measureChartText('0', style: ts, scaler: style.textScaler).height + 6;
    final plot = Rect.fromLTRB(axisW, labelH / 2, size.width - 4, size.height - labelH);
    if (plot.width <= 0 || plot.height <= 0) return;
    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * f;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final s = measureChartText(axisLabel(max * f), style: ts, scaler: style.textScaler);
      paintChartText(canvas, axisLabel(max * f), Offset(plot.left - 4, y - s.height / 2), style: ts, scaler: style.textScaler, align: 1);
    }
    final n = math.max(current.length, previous?.length ?? 0);
    double x(int i) => n <= 1 ? plot.center.dx : plot.left + plot.width * i / (n - 1);
    double y(double v) => plot.bottom - (max <= 0 ? 0 : (v.clamp(0, max) / max) * plot.height);
    Path line(List<double> v) {
      final p = Path()..moveTo(x(0), y(v.first));
      for (var i = 1; i < v.length; i++) {
        p.lineTo(x(i), y(v[i]));
      }
      return p;
    }

    if (previous != null && previous!.isNotEmpty) {
      drawDashedPath(
        canvas,
        line(previous!),
        Paint()
          ..color = style.previous
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    final cur = line(current);
    final area = Path.from(cur)
      ..lineTo(x(current.length - 1), plot.bottom)
      ..lineTo(x(0), plot.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = style.bar.withValues(alpha: 0.18));
    canvas.drawPath(
      cur,
      Paint()
        ..color = style.barSelected
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    if (current.length == 1) canvas.drawCircle(Offset(x(0), y(current.first)), 4, Paint()..color = style.barSelected);
    // labels: first, middle, last
    final idx = {0, if (labels.length > 2) labels.length ~/ 2, labels.length - 1}.where((i) => i >= 0 && i < labels.length);
    for (final i in idx) {
      final align = i == 0 ? 0.0 : (i == labels.length - 1 ? 1.0 : 0.5);
      paintChartText(canvas, labels[i], Offset(x(i), plot.bottom + 4), style: ts, scaler: style.textScaler, align: align);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.current != current || old.previous != previous || old.style.bar != style.bar;
}
