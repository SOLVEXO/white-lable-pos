// G4.0 chart toolkit (CustomPainter, no package): every chart paints in light and dark and at a large text size, reads as one sentence to a screen
// reader, and answers taps (a bar → its value bubble / onSelect; a heatmap cell → onCell). Comparisons carry a non-colour cue (dash / words / ▲ / outline).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/core/charts/charts.dart';
import 'package:solvexo_pos/core/design/design.dart';

void main() {
  Future<void> pump(WidgetTester t, Widget w, {bool dark = false, double textScale = 1}) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 900), textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(child: w),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  const bars = [ChartBar(label: 'Mon', value: 100, valueText: 'Rs 1.00'), ChartBar(label: 'Tue', value: 300, valueText: 'Rs 3.00'), ChartBar(label: 'Wed', value: 0, valueText: 'Rs 0.00')];

  test('niceMax rounds an axis up to 1 / 2 / 2.5 / 5 × 10ⁿ', () {
    expect([niceMax(0), niceMax(7), niceMax(13), niceMax(240), niceMax(2600), niceMax(51000)], [1, 10, 20, 250, 5000, 100000]);
  });

  group('BarChart', () {
    for (final dark in [false, true]) {
      testWidgets('paints (${dark ? 'dark' : 'light'}), the label summarises it, a tap selects a bar and announces its value', (t) async {
        int? picked;
        final handle = t.ensureSemantics();
        await pump(
          t,
          BarChart(bars: bars, semanticsLabel: 'Sales by day: Mon Rs 1.00, Tue Rs 3.00', onSelect: (i) => picked = i),
          dark: dark,
        );
        expect(find.bySemanticsLabel(RegExp('Sales by day')), findsOneWidget);
        final box = t.getRect(find.byType(BarChart));
        // tap the middle third (Tue), right of the axis
        await t.tapAt(Offset(box.left + box.width * 0.55, box.center.dy));
        await t.pump();
        expect(picked, 1);
        expect(t.getSemantics(find.byType(BarChart)).value, 'Tue: Rs 3.00');
        expect(t.takeException(), isNull);
        handle.dispose();
      });
    }

    testWidgets('large text, a highlighted bar, an empty list and many bars do not throw', (t) async {
      await pump(
        t,
        BarChart(
          bars: [for (var h = 0; h < 24; h++) ChartBar(label: h.toString().padLeft(2, '0'), value: h * 10.0)],
          highlight: 23,
          semanticsLabel: 'x',
          initialSelected: 23,
        ),
        textScale: 2,
      );
      expect(t.takeException(), isNull);
      await pump(t, const BarChart(bars: [], semanticsLabel: 'empty'));
      expect(t.takeException(), isNull);
    });
  });

  group('LineChart', () {
    testWidgets('the previous period is dashed and NAMED in a legend; without it there is no legend', (t) async {
      final handle = t.ensureSemantics();
      await pump(t, const LineChart(current: [1, 5, 3], previous: [2, 2, 2], labels: ['1 Nov', '2 Nov', '3 Nov'], semanticsLabel: 'Sales by day vs previous'));
      expect(find.bySemanticsLabel(RegExp('Sales by day vs previous')), findsOneWidget);
      expect(find.text('This period', skipOffstage: false), findsOneWidget);
      expect(find.text('Previous period', skipOffstage: false), findsOneWidget);
      await pump(t, const LineChart(current: [4], labels: ['1 Nov'], semanticsLabel: 'one day'), dark: true, textScale: 1.8);
      expect(find.text('Previous period'), findsNothing);
      expect(t.takeException(), isNull);
      handle.dispose();
    });
  });

  group('DonutChart', () {
    testWidgets('every slice is named with its share in the legend (not colour alone); a refund-heavy tender counts as zero', (t) async {
      final handle = t.ensureSemantics();
      await pump(
        t,
        const DonutChart(
          slices: [
            DonutSlice(label: 'Cash', value: 75),
            DonutSlice(label: 'Card', value: 25),
            DonutSlice(label: 'Store credit', value: -5),
          ],
          centerText: 'Rs 100',
          semanticsLabel: 'Payment mix: Cash 75 percent',
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Payment mix')), findsOneWidget);
      expect(find.text('Cash · 75.0%', skipOffstage: false), findsOneWidget);
      expect(find.text('Card · 25.0%', skipOffstage: false), findsOneWidget);
      expect(find.text('Store credit · 0.0%', skipOffstage: false), findsOneWidget);
      await pump(t, const DonutChart(slices: [], semanticsLabel: 'nothing'), dark: true);
      expect(t.takeException(), isNull);
      handle.dispose();
    });
  });

  group('HeatmapChart', () {
    testWidgets('names the busiest cell, explains the shading, reports a tapped cell', (t) async {
      final values = List.generate(7, (_) => List<num>.filled(24, 0));
      values[2][15] = 900;
      values[0][9] = 100;
      (int, int)? tapped;
      final handle = t.ensureSemantics();
      final chart = HeatmapChart(values: values, semanticsLabel: 'Busiest Wednesday 15:00', onCell: (r, h) => tapped = (r, h));
      expect(chart.busiest, (2, 15));
      await pump(t, chart);
      expect(find.bySemanticsLabel(RegExp('Busiest Wednesday')), findsOneWidget);
      expect(find.text('Less', skipOffstage: false), findsOneWidget);
      expect(find.text('Busiest', skipOffstage: false), findsOneWidget);
      final grid = t.getRect(find.descendant(of: find.byType(HeatmapChart), matching: find.byType(GestureDetector)).first);
      // tap the right-most column of the first row
      await t.tapAt(Offset(grid.right - 2, grid.top + 3));
      expect(tapped?.$1, 0);
      expect(tapped?.$2, 23);
      await pump(t, HeatmapChart(values: List.generate(7, (_) => List<num>.filled(24, 0)), semanticsLabel: 'none'), dark: true, textScale: 2);
      expect(t.takeException(), isNull);
      handle.dispose();
    });
  });
}
