import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/charts/chart_common.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A weekday × hour heatmap: rows Monday … Sunday, 24 columns. The intensity is the accent's opacity; the busiest cell is OUTLINED and named in the
/// caption, and a "Less → More" scale explains the shading (so it does not rely on colour alone). Tapping a cell reports it.
class HeatmapChart extends StatelessWidget {
  const HeatmapChart({super.key, required this.values, required this.semanticsLabel, this.rowLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], this.onCell});

  /// rows × 24
  final List<List<num>> values;
  final List<String> rowLabels;
  final String semanticsLabel;
  final void Function(int row, int hour)? onCell;

  (int, int)? get busiest {
    (int, int)? best;
    num top = 0;
    for (var r = 0; r < values.length; r++) {
      for (var h = 0; h < values[r].length; h++) {
        if (values[r][h] > top) {
          top = values[r][h];
          best = (r, h);
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    final ts = style.labelStyle.copyWith(color: style.axisText);
    final labelW = rowLabels.fold<double>(0, (m, l) => math.max(m, measureChartText(l, style: ts, scaler: style.textScaler).width)) + 6;
    final hourH = measureChartText('00', style: ts, scaler: style.textScaler).height + 4;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (_, c) {
                final cell = math.max(6.0, (c.maxWidth - labelW) / 24);
                final h = cell * values.length + hourH;
                final painter = _HeatPainter(values: values, rowLabels: rowLabels, style: style, labelW: labelW, cell: cell, hourH: hourH, busiest: busiest);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: onCell == null
                      ? null
                      : (d) {
                          final col = ((d.localPosition.dx - labelW) / cell).floor();
                          final row = (d.localPosition.dy / cell).floor();
                          if (col >= 0 && col < 24 && row >= 0 && row < values.length) onCell!(row, col);
                        },
                  child: SizedBox(
                    width: c.maxWidth,
                    height: h,
                    child: CustomPaint(painter: painter),
                  ),
                );
              },
            ),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                Text('Less', style: ts),
                const SizedBox(width: Space.s1),
                for (final a in const [0.08, 0.3, 0.55, 0.8, 1.0])
                  Container(
                    width: 14,
                    height: 10,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: style.barSelected.withValues(alpha: a),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: Space.s1),
                Text('More', style: ts),
                const SizedBox(width: Space.s3),
                Container(
                  width: 12,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: style.bubble, width: 1.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: Space.s1),
                Flexible(child: Text('Busiest', style: ts)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({required this.values, required this.rowLabels, required this.style, required this.labelW, required this.cell, required this.hourH, required this.busiest});
  final List<List<num>> values;
  final List<String> rowLabels;
  final ChartStyle style;
  final double labelW, cell, hourH;
  final (int, int)? busiest;

  @override
  void paint(Canvas canvas, Size size) {
    final ts = style.labelStyle.copyWith(color: style.axisText);
    final top = values.fold<num>(0, (m, r) => r.fold<num>(m, (a, v) => math.max(a, v)));
    for (var r = 0; r < values.length; r++) {
      final y = r * cell;
      if (r < rowLabels.length) {
        final s = measureChartText(rowLabels[r], style: ts, scaler: style.textScaler);
        paintChartText(canvas, rowLabels[r], Offset(0, y + (cell - s.height) / 2), style: ts, scaler: style.textScaler);
      }
      for (var h = 0; h < 24 && h < values[r].length; h++) {
        final v = values[r][h];
        final rect = Rect.fromLTWH(labelW + h * cell + 1, y + 1, cell - 2, cell - 2);
        final color = v <= 0 || top <= 0 ? style.grid.withValues(alpha: 0.5) : style.barSelected.withValues(alpha: 0.12 + 0.88 * (v / top));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), Paint()..color = color);
        if (busiest == (r, h)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(2)),
            Paint()
              ..color = style.bubble
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    for (final h in const [0, 6, 12, 18, 23]) {
      paintChartText(canvas, h.toString().padLeft(2, '0'), Offset(labelW + h * cell + cell / 2, values.length * cell + 2), style: ts, scaler: style.textScaler, align: 0.5);
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => old.values != values || old.cell != cell || old.style.bar != style.bar;
}
