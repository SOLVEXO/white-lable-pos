import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/charts/chart_common.dart';

class ChartBar {
  const ChartBar({required this.label, required this.value, this.valueText});

  /// the label under the bar (a day, an hour, a category)
  final String label;
  final double value;

  /// what the value bubble and the screen reader say (e.g. "Rs 1,250.00"); [value] as text when null
  final String? valueText;
}

/// A vertical bar chart: a labelled value axis, labels under the bars (thinned out when crowded), an optional highlighted bar (marked with a ▲,
/// not only by colour) and tap-to-select with a value bubble. The whole chart reads as one sentence to a screen reader ([semanticsLabel]) and the
/// selected bar is announced as its value.
class BarChart extends StatefulWidget {
  const BarChart({super.key, required this.bars, required this.semanticsLabel, this.axisLabel, this.height = 200, this.highlight, this.initialSelected, this.onSelect});
  final List<ChartBar> bars;
  final String semanticsLabel;

  /// formats an axis value (e.g. compact money); `toStringAsFixed(0)` when null
  final String Function(double)? axisLabel;
  final double height;

  /// a bar to mark (the busiest hour); drawn with a ▲ above it
  final int? highlight;
  final int? initialSelected;
  final ValueChanged<int>? onSelect;

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  late int? selected = widget.initialSelected;
  _BarPainter? _painter;

  Size _size = Size.zero;

  void _tap(Offset local) {
    final i = _painter?.indexAt(local, _size);
    if (i == null) return;
    setState(() => selected = i);
    widget.onSelect?.call(i);
  }

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    _painter = _BarPainter(bars: widget.bars, style: style, selected: selected, highlight: widget.highlight, axisLabel: widget.axisLabel ?? (v) => v.toStringAsFixed(0));
    final sel = selected != null && selected! < widget.bars.length ? widget.bars[selected!] : null;
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      value: sel == null ? null : '${sel.label}: ${sel.valueText ?? sel.value.toStringAsFixed(0)}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _tap(d.localPosition),
          child: SizedBox(
            height: widget.height * style.textScaler.scale(1).clamp(1.0, 1.6),
            width: double.infinity,
            child: LayoutBuilder(
              builder: (_, c) {
                _size = c.biggest;
                return CustomPaint(painter: _painter, size: c.biggest);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.bars, required this.style, required this.selected, required this.highlight, required this.axisLabel});
  final List<ChartBar> bars;
  final ChartStyle style;
  final int? selected, highlight;
  final String Function(double) axisLabel;

  double get _max => niceMax(bars.fold<double>(0, (m, b) => math.max(m, b.value)));

  Rect plotFor(Size size) {
    final ts = style.labelStyle;
    final axisW = math.max(measureChartText(axisLabel(_max), style: ts, scaler: style.textScaler).width, measureChartText(axisLabel(0), style: ts, scaler: style.textScaler).width) + 6;
    final labelH = measureChartText('0', style: ts, scaler: style.textScaler).height + 6;
    final bubbleH = labelH + 10;
    return Rect.fromLTRB(axisW, bubbleH, size.width, size.height - labelH);
  }

  /// the bar under [p] (only after the chart was painted once)
  int? indexAt(Offset p, Size size) {
    final plot = plotFor(size);
    if (bars.isEmpty || plot.width <= 0 || p.dx < plot.left || p.dx > plot.right) return null;
    return ((p.dx - plot.left) / (plot.width / bars.length)).floor().clamp(0, bars.length - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotFor(size);
    if (bars.isEmpty || plot.width <= 0 || plot.height <= 0) return;
    final ts = style.labelStyle.copyWith(color: style.axisText);
    final max = _max;
    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    // value axis: 0, half, max
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * f;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final s = measureChartText(axisLabel(max * f), style: ts, scaler: style.textScaler);
      paintChartText(canvas, axisLabel(max * f), Offset(plot.left - 4, y - s.height / 2), style: ts, scaler: style.textScaler, align: 1);
    }
    final slot = plot.width / bars.length;
    final barW = math.max(2.0, slot * 0.68);
    // labels under the bars: as many as fit without touching
    final widest = bars.fold<double>(0, (m, b) => math.max(m, measureChartText(b.label, style: ts, scaler: style.textScaler).width));
    final every = math.max(1, ((widest + 6) / slot).ceil());
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final cx = plot.left + slot * (i + 0.5);
      final h = max <= 0 ? 0.0 : (b.value.clamp(0, max) / max) * plot.height;
      final r = Rect.fromLTWH(cx - barW / 2, plot.bottom - h, barW, h);
      final isSel = i == selected;
      canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), Paint()..color = isSel ? style.barSelected : style.bar);
      if (i == highlight) {
        final tri = Path()
          ..moveTo(cx - 5, r.top - 9)
          ..lineTo(cx + 5, r.top - 9)
          ..lineTo(cx, r.top - 3)
          ..close();
        canvas.drawPath(tri, Paint()..color = style.axisText);
      }
      if (i % every == 0) paintChartText(canvas, b.label, Offset(cx, plot.bottom + 4), style: ts, scaler: style.textScaler, align: 0.5);
    }
    // the value bubble over the selected bar
    if (selected != null && selected! < bars.length) {
      final b = bars[selected!];
      final text = '${b.label}: ${b.valueText ?? b.value.toStringAsFixed(0)}';
      final bs = style.labelStyle.copyWith(color: style.onBubble, fontWeight: FontWeight.w600);
      final s = measureChartText(text, style: bs, scaler: style.textScaler);
      final cx = (plot.left + slot * (selected! + 0.5)).clamp(s.width / 2 + 6, size.width - s.width / 2 - 6);
      final box = Rect.fromCenter(center: Offset(cx, s.height / 2 + 4), width: s.width + 12, height: s.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(6)), Paint()..color = style.bubble);
      paintChartText(canvas, text, Offset(cx, box.top + 3), style: bs, scaler: style.textScaler, align: 0.5);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.bars != bars || old.selected != selected || old.highlight != highlight || old.style.bar != style.bar;
}
