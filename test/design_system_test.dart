import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/core/design/gallery/design_gallery_view.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Flattens a translucent colour over an opaque backdrop.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

Widget _host(Widget child, {ThemeData? theme, Size? size, double textScale = 1}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: size ?? const Size(390, 844), textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    );

void main() {
  group('palette contrast (WCAG ≥ 4.5:1) — every text/background pair, both modes', () {
    for (final entry in {'light': AppPalette.light, 'dark': AppPalette.dark}.entries) {
      final p = entry.value;
      final name = entry.key;

      // every surface a text colour can sit on (soft tints flattened over the surface they are drawn on)
      final surfaces = <String, Color>{
        'background': p.background,
        'surface': p.surface,
        'surfaceRaised': p.surfaceRaised,
        'fill': p.fill,
        'accentSoft': _over(p.accentSoft, p.surface),
        'successSoft': _over(p.successSoft, p.surface),
        'warningSoft': _over(p.warningSoft, p.surface),
        'dangerSoft': _over(p.dangerSoft, p.surface),
        'infoSoft': _over(p.infoSoft, p.surface),
      };
      final neutralText = <String, Color>{'textPrimary': p.textPrimary, 'textSecondary': p.textSecondary, 'textMuted': p.textMuted};
      final coloredText = <String, Color>{'accentFg': p.accentFg, 'successFg': p.successFg, 'warningFg': p.warningFg, 'dangerFg': p.dangerFg, 'infoFg': p.infoFg};

      test('$name: neutral text on every neutral surface', () {
        for (final t in neutralText.entries) {
          for (final b in ['background', 'surface', 'surfaceRaised', 'fill']) {
            expect(_contrast(t.value, surfaces[b]!), greaterThanOrEqualTo(4.5), reason: '${t.key} on $b');
          }
        }
      });
      test('$name: coloured (accent / semantic) text on every neutral surface AND on its own soft tint', () {
        for (final t in coloredText.entries) {
          for (final b in ['background', 'surface', 'surfaceRaised', 'fill']) {
            expect(_contrast(t.value, surfaces[b]!), greaterThanOrEqualTo(4.5), reason: '${t.key} on $b');
          }
        }
        final own = {'accentFg': 'accentSoft', 'successFg': 'successSoft', 'warningFg': 'warningSoft', 'dangerFg': 'dangerSoft', 'infoFg': 'infoSoft'};
        for (final e in own.entries) {
          expect(_contrast(coloredText[e.key]!, surfaces[e.value]!), greaterThanOrEqualTo(4.5), reason: '${e.key} on ${e.value}');
        }
      });
      test('$name: button / label colours on their fills', () {
        expect(_contrast(p.onAccentFill, p.accentFill), greaterThanOrEqualTo(4.5), reason: 'white label on the filled primary button');
        expect(_contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: 'ink label on the brand coral');
        expect(_contrast(p.onAccent, p.accentStrong), greaterThanOrEqualTo(4.5));
        expect(_contrast(p.onDanger, p.danger), greaterThanOrEqualTo(4.5), reason: 'label on the danger fill');
      });
      test('$name: the secondary text colours the app really draws on the accent / danger fills', () {
        // the accent fill is the one place white text sits on coral; it must be the darker coral, never the brand coral
        expect(p.accentFill, const Color(0xFFB4553A));
        expect(p.accent, const Color(0xFFDC7758));
      });
    }
    test('white would NOT pass on the brand coral (why filled buttons use #B4553A and icons use #DC7758)', () {
      expect(_contrast(Colors.white, AppPalette.light.accent), lessThan(4.5));
      expect(_contrast(Colors.white, AppPalette.light.accentFill), greaterThanOrEqualTo(4.5));
    });
    test('the blueprint\'s own semantic hues are NOT used as text (they fail on white) — only their darker "fg" shades are', () {
      for (final c in [const Color(0xFF20976B), const Color(0xFFE8A22B), const Color(0xFFD94C5C), const Color(0xFF4D72DB), const Color(0xFFDC7758)]) {
        expect(_contrast(c, Colors.white), lessThan(4.5), reason: '$c');
      }
    });
  });

  group('blueprint tokens', () {
    test('radii 10 / 14 / 18 / 24', () {
      expect([Radii.sm, Radii.md, Radii.lg, Radii.xl], [10, 14, 18, 24]);
    });
    test('spacing includes the blueprint scale 4 8 12 16 20 24 32 and the tap target is never below 44', () {
      expect([Space.s1, Space.s2, Space.s3, Space.s4, Space.s5, Space.s6, Space.s8], [4, 8, 12, 16, 20, 24, 32]);
      expect(Space.minTouch, greaterThanOrEqualTo(44));
    });
    test('fonts: Manrope for display/headline/title, DM Sans for body; amounts stay JetBrains Mono (DM Sans has no tnum)', () {
      for (final t in [AppTypeScale.phone, AppTypeScale.tablet]) {
        for (final st in [t.display, t.headline, t.title]) {
          expect(st.fontFamily, 'Manrope');
          expect(st.fontVariations, isNotEmpty, reason: 'variable font: wght axis must be set explicitly');
        }
        for (final st in [t.subtitle, t.body, t.bodySmall, t.label, t.caption]) {
          expect(st.fontFamily, 'DMSans');
        }
        for (final st in [t.amountXl, t.amountLg, t.amountMd]) {
          expect(st.fontFamily, 'JetBrainsMono');
        }
      }
    });
    test('the wght axis equals the FontWeight on every variable-font style', () {
      for (final t in [AppTypeScale.phone, AppTypeScale.tablet]) {
        for (final st in [t.display, t.headline, t.title, t.subtitle, t.body, t.bodySmall, t.label, t.caption]) {
          expect(st.fontVariations!.single.value, st.fontWeight!.value.toDouble());
        }
      }
    });
    test('font files and OFL licences are bundled', () {
      for (final f in ['manrope/Manrope-Variable.ttf', 'manrope/OFL.txt', 'dm_sans/DMSans-Variable.ttf', 'dm_sans/OFL.txt', 'jetbrains_mono/OFL.txt']) {
        expect(File('assets/app_fonts/$f').existsSync(), isTrue, reason: f);
      }
      expect(Directory('assets/app_fonts/plus_jakarta_sans').existsSync(), isFalse);
    });
  });

  test('breakpoints: phone < 600, tablet 600–1100, large > 1100', () {
    expect(ScreenClass.fromWidth(599), ScreenClass.phone);
    expect(ScreenClass.fromWidth(600), ScreenClass.tablet);
    expect(ScreenClass.fromWidth(1100), ScreenClass.tablet);
    expect(ScreenClass.fromWidth(1101), ScreenClass.large);
  });

  test('JetBrains Mono never uses a weight above w600 (no synthetic bold)', () {
    for (final s in [AppTypeScale.phone, AppTypeScale.tablet]) {
      for (final st in [s.amountXl, s.amountLg, s.amountMd]) {
        expect(st.fontWeight!.value, lessThanOrEqualTo(600));
      }
    }
    // No source file may put a >w600 weight on an amount style.
    final bad = RegExp(r'amount(Xl|Lg|Md)\.copyWith\((?:[^()]|\([^()]*\))*?fontWeight:\s*FontWeight\.w[789]00', dotAll: true);
    for (final f in Directory('lib/core/design').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('money styles use JetBrains Mono with tabular figures', () {
    for (final s in [AppTypeScale.phone, AppTypeScale.tablet]) {
      for (final st in [s.amountXl, s.amountLg, s.amountMd]) {
        expect(st.fontFamily, AppTypeScale.mono);
        expect(st.fontFeatures, isNotNull);
      }
    }
  });

  group('gallery renders without exceptions or overflow', () {
    final sizes = {'phone portrait': const Size(390, 844), 'tablet portrait': const Size(820, 1180), 'tablet landscape': const Size(1180, 820), 'small phone @1.3x': const Size(360, 640)};
    for (final e in sizes.entries) {
      testWidgets(e.key, (tester) async {
        tester.view.physicalSize = e.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(e.key.contains('1.3') ? 1.3 : 1)), child: child!),
          home: const DesignGalleryView(),
        ));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        // Scroll the whole list so every lazily-built section is exercised.
        final list = find.byType(Scrollable).first;
        for (var i = 0; i < 14; i++) {
          await tester.drag(list, const Offset(0, -700));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: 'after scroll $i');
        }
      });
    }
  });

  group('components', () {
    testWidgets('AppButton: loading ignores taps; enabled fires; disabled does not', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Column(children: [
        AppButton(label: 'Go', onPressed: () => taps++),
        AppButton(label: 'Busy', loading: true, onPressed: () => taps += 100),
        const AppButton(label: 'Off', onPressed: null),
      ])));
      await tester.tap(find.text('Go'));
      await tester.tap(find.byType(AppButton).at(1), warnIfMissed: false);
      await tester.tap(find.text('Off'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 1);
      expect(tester.getSize(find.byType(AppButton).first).height, greaterThanOrEqualTo(48));
    });

    testWidgets('PinPad reports digits, backspace and clear; keys are ≥ 48px', (tester) async {
      final got = <String>[];
      var back = 0, clear = 0;
      await tester.pumpWidget(_host(Center(child: PinPad(onDigit: got.add, onBackspace: () => back++, onClear: () => clear++))));
      for (final d in ['1', '5', '0']) {
        await tester.tap(find.text(d));
      }
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.longPress(find.byIcon(Icons.backspace_outlined));
      expect(got, ['1', '5', '0']);
      expect(back, 1);
      expect(clear, 1);
      expect(tester.getSize(find.text('5')).height, lessThan(64)); // text itself
      expect(tester.getSize(find.ancestor(of: find.text('5'), matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(48));
    });

    testWidgets('PinDots shows semantic progress', (tester) async {
      await tester.pumpWidget(_host(const PinDots(length: 4, filled: 2)));
      expect(find.bySemanticsLabel('PIN'), findsOneWidget);
    });

    testWidgets('AmountText rolls only changed digits and stays slot-aligned', (tester) async {
      final text = ValueNotifier('\$9.99');
      await tester.pumpWidget(_host(ValueListenableBuilder<String>(valueListenable: text, builder: (_, v, __) => AmountText(v))));
      expect(find.text('9'), findsNWidgets(3));
      text.value = '\$10.99';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('9'), findsNWidgets(2));
    });

    testWidgets('AmountText is a plain Text under reduced motion', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const MediaQuery(data: MediaQueryData(disableAnimations: true), child: AmountText('\$12.50'))));
      expect(find.text('\$12.50'), findsOneWidget);
    });

    testWidgets('QuantityStepper respects min/max and 48px targets', (tester) async {
      var v = 1;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (c, set) => QuantityStepper(value: v, min: 1, max: 2, onChanged: (n) => set(() => v = n)))));
      await tester.tap(find.byIcon(Icons.remove_rounded)); // at min: ignored
      await tester.pump();
      expect(v, 1);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(v, 2);
      await tester.tap(find.byIcon(Icons.add_rounded)); // at max: ignored
      await tester.pump();
      expect(v, 2);
      expect(tester.getSize(find.ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(SizedBox)).first).width, greaterThanOrEqualTo(48));
    });

    testWidgets('ProductTile: sold-out is not tappable; in-stock adds', (tester) async {
      var adds = 0;
      await tester.pumpWidget(_host(Row(children: [
        Expanded(child: SizedBox(height: 220, child: ProductTile(name: 'Bread', priceText: '\$4.50', stock: 5, onAdd: () => adds++))),
        Expanded(child: SizedBox(height: 220, child: ProductTile(name: 'Gone', priceText: '\$1.00', stock: 0, onAdd: () => adds += 100))),
      ])));
      await tester.tap(find.text('Bread'));
      await tester.tap(find.text('Gone'), warnIfMissed: false);
      await tester.pump();
      expect(adds, 1);
      expect(find.text('Sold out'), findsOneWidget);
    });

    testWidgets('CategoryChips reports selection', (tester) async {
      var sel = 0;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (c, set) => CategoryChips(labels: const ['All', 'Dairy', 'Drinks'], selectedIndex: sel, onSelected: (i) => set(() => sel = i)))));
      await tester.pump();
      await tester.tap(find.text('Drinks'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(sel, 2);
    });

    testWidgets('AppToast shows, replaces, and auto-dismisses', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      AppToast.success('Saved', context: ctx);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saved'), findsOneWidget);
      AppToast.error('Oops', context: ctx);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Oops'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Oops'), findsNothing);
    });

    testWidgets('AppDialog.confirm resolves true / false', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final f = AppDialog.confirm(ctx, title: 'Sure?', confirmLabel: 'Yes', cancelLabel: 'No');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Yes'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(await f, isTrue);
    });

    testWidgets('AppTextField password toggle reveals text', (tester) async {
      await tester.pumpWidget(_host(const Scaffold(body: AppTextField(label: 'Password', obscureText: true, showObscureToggle: true))));
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    });
  });

  group('AppNetworkImage', () {
    test('decode width follows the laid-out box x DPR (larger side), with fallback', () {
      expect(AppNetworkImage.decodeWidthFor(const BoxConstraints.tightFor(width: 120, height: 150), 2, 400), 300);
      expect(AppNetworkImage.decodeWidthFor(const BoxConstraints(maxWidth: 200), 3, 400), 600);
      expect(AppNetworkImage.decodeWidthFor(const BoxConstraints(), 2, 400), 400);
      expect(AppNetworkImage.decodeWidthFor(BoxConstraints.tightFor(width: 5000, height: 5000), 3, 400), 2048);
    });

    testWidgets('sets memCacheWidth from the layout size', (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const Center(child: SizedBox(width: 100, height: 120, child: AppNetworkImage(url: 'http://localhost:1/x.png')))));
      final img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.memCacheWidth, 240);
    });

    testWidgets('no URL -> neutral fallback icon, no network widget', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(width: 80, height: 80, child: AppNetworkImage(url: null))));
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });

  test('font OFL texts are registered with LicenseRegistry', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerDesignFontLicenses();
    final packages = <String>{};
    await for (final e in LicenseRegistry.licenses) {
      packages.addAll(e.packages);
    }
    expect(packages, containsAll(['Manrope', 'DM Sans', 'JetBrains Mono']));
  });

  group('AppShell', () {
    const dests = [AppDestination(icon: Icons.home_outlined, label: 'Sale'), AppDestination(icon: Icons.list, label: 'Orders', badge: 2)];
    Widget shell(Size size, void Function(int) onSel) => _host(
          AppShell(destinations: dests, currentIndex: 0, onDestinationSelected: onSel, body: const Text('BODY'), topBanner: const Text('BANNER')),
          size: size,
        );

    testWidgets('phone: bottom bar, no rail', (tester) async {
      var sel = -1;
      await tester.pumpWidget(shell(const Size(390, 844), (i) => sel = i));
      expect(find.text('BODY'), findsOneWidget);
      expect(find.text('BANNER'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
      await tester.tap(find.text('Orders'));
      expect(sel, 1);
    });

    testWidgets('tablet: collapsed rail that toggles; large: starts expanded', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: AppShell(destinations: dests, currentIndex: 0, onDestinationSelected: (_) {}, body: const Text('BODY'))));
      expect(find.byType(VerticalDivider), findsOneWidget);
      final collapsedW = tester.getTopLeft(find.byType(VerticalDivider)).dx; // rail width
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump(); // build the frame that starts the animation
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.getTopLeft(find.byType(VerticalDivider)).dx, greaterThan(collapsedW));
      expect(tester.takeException(), isNull);
    });
  });
}
