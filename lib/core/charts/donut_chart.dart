import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/charts/chart_common.dart';
import 'package:solvexo_pos/core/design/design.dart';

class DonutSlice {
  const DonutSlice({required this.label, required this.value, this.valueText});
  final String label;
  final double value;
  final String? valueText;
}

/// A donut (the payment mix) with a legend that names every slice with its share in words — the legend is the cue, never the colour alone.
/// Negative values (a tender that refunded more than it took) are drawn as zero but still listed.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, required this.semanticsLabel, this.centerText, this.size = 160});
  final List<DonutSlice> slices;
  final String semanticsLabel;
  final String? centerText;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    final total = slices.fold<double>(0, (n, s) => n + math.max(0, s.value));
    String pct(DonutSlice s) => total <= 0 ? '0%' : '${(math.max(0, s.value) / total * 100).toStringAsFixed(1)}%';
    final chart = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(values: [for (final s in slices) math.max(0, s.value)], colors: style.series, track: style.grid, gap: context.palette.surface),
        child: centerText == null
            ? null
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.s6),
                  child: FittedBox(
                    child: Text(centerText!, style: context.type.subtitle.copyWith(color: context.palette.textPrimary)),
                  ),
                ),
              ),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s1),
            child: ChartLegendItem(
              label: '${slices[i].label} · ${pct(slices[i])}${slices[i].valueText == null ? '' : ' · ${slices[i].valueText}'}',
              color: style.series[i % style.series.length],
              square: true,
            ),
          ),
      ],
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (_, c) => c.maxWidth >= size * 2.2
              ? Row(
                  children: [
                    chart,
                    const SizedBox(width: Space.s4),
                    Expanded(child: legend),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: chart),
                    const SizedBox(height: Space.s3),
                    legend,
                  ],
                ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors, required this.track, required this.gap});
  final List<double> values;
  final List<Color> colors;
  final Color track, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final stroke = r * 0.32;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r - stroke / 2);
    final total = values.fold<double>(0, (n, v) => n + v);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start, sweep, false, paint..color = colors[i % colors.length]);
      // a thin gap between slices so neighbours stay apart without relying on colour
      if (values.where((v) => v > 0).length > 1) {
        canvas.drawArc(
          rect,
          start + sweep - 0.015,
          0.015,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke + 1
            ..color = gap,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.values != values || old.colors != colors;
}
