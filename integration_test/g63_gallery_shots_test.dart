// G6.3 component gallery screenshots (the debug-only /design-gallery screen), phone, light and dark: the top (tokens), buttons and fields, and
// the G6.3 page patterns. Run: SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g63_gallery_shots_test.dart docs/pos-blueprint/g6_3_screenshots/gallery x
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/core/design/gallery/design_gallery_view.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT $name');
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    testWidgets('G6.3 gallery ($tn)', (t) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: dark ? AppTheme.dark : AppTheme.light, home: DesignGalleryView(startDark: dark)));
      await t.pump(const Duration(milliseconds: 800));
      await shot(t, 'g63_gallery_01_tokens_$tn');
      for (final (title, n) in [('Buttons', '02_buttons'), ('Empty state · skeleton', '03_states'), ('Page patterns (G6.3)', '04_patterns')]) {
        final f = find.text(title).first;
        await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
        await t.pump(const Duration(milliseconds: 300));
        await t.ensureVisible(f);
        await shot(t, 'g63_gallery_${n}_$tn');
      }
    });
  }
}
