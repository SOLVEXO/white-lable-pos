// G6.4: the app follows the device's light / dark setting by default; Settings → Appearance (System / Light / Dark) is a per-device choice,
// saved locally, applied at once to every open screen, kept across restarts and sign-out, available to every role.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/services/theme_preference.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/appearance_section.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// What the app root does (main.dart): an Obx around the MaterialApp reading the choice.
Widget app(ThemePreference pref, Widget home) =>
    Obx(() => GetMaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: pref.choice.value.themeMode, home: home));

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text(Theme.of(context).brightness.name, key: const Key('brightness')),
          Text(context.palette.isDark ? 'palette-dark' : 'palette-light'),
        ]),
      );
}

class _BrightnessText extends StatelessWidget {
  const _BrightnessText();
  @override
  Widget build(BuildContext context) => Text(Theme.of(context).brightness.name, key: const Key('brightness'));
}

String brightness(WidgetTester t) => t.widget<Text>(find.byKey(const Key('brightness'))).data!;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Get.reset);

  test('default (nothing saved) = follow the system', () async {
    final p = await ThemePreference().init();
    expect(p.choice.value, AppearanceChoice.system);
    expect(p.themeMode, ThemeMode.system);
    expect(AppearanceChoice.parse('nonsense'), AppearanceChoice.system);
  });

  test('each choice persists across a restart (a fresh service reads it back)', () async {
    for (final c in AppearanceChoice.values) {
      await (await ThemePreference().init()).set(c);
      final restarted = await ThemePreference().init();
      expect(restarted.choice.value, c, reason: c.name);
      expect(restarted.themeMode, c.themeMode);
    }
  });

  test('the choice survives sign-out (it is a device preference, not account data)', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'x', 'store_id': 's1'});
    await (await ThemePreference().init()).set(AppearanceChoice.dark);
    await AppPreferences.clearPreference();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('store_id'), isNull, reason: 'account data is cleared');
    expect((await ThemePreference().init()).choice.value, AppearanceChoice.dark);
  });

  testWidgets('System follows the device: the device turning dark turns the app dark', (t) async {
    final pref = await ThemePreference().init();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(app(pref, const _Probe()));
    expect(brightness(t), 'light');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await t.pumpAndSettle();
    expect(brightness(t), 'dark');
    expect(find.text('palette-dark'), findsOneWidget);
  });

  testWidgets('switching updates the open screen at once (no restart), both ways, regardless of the device setting', (t) async {
    final pref = await ThemePreference().init();
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(app(pref, const _Probe()));
    await pref.set(AppearanceChoice.dark);
    await t.pumpAndSettle();
    expect(brightness(t), 'dark');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await pref.set(AppearanceChoice.light);
    await t.pumpAndSettle();
    expect(brightness(t), 'light', reason: 'Light wins over a dark device');
  });

  testWidgets('Settings → Appearance: the row shows the choice; picking Dark in the sheet applies it and closes the sheet (any role: no gate)', (t) async {
    final pref = await ThemePreference().init();
    Get.put<ThemePreference>(pref);
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(pref, const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: Column(children: [AppearanceSection(), _BrightnessText()])))));
    expect(find.descendant(of: find.byKey(const Key('settingsAppearance')), matching: find.text('System')), findsOneWidget);
    await t.tap(find.byKey(const Key('settingsAppearance')));
    await t.pumpAndSettle();
    for (final c in AppearanceChoice.values) {
      expect(find.byKey(Key('appearance_${c.name}')), findsOneWidget);
    }
    await t.tap(find.byKey(const Key('appearance_dark')));
    await t.pumpAndSettle();
    expect(pref.choice.value, AppearanceChoice.dark);
    expect(find.byKey(const Key('appearance_dark')), findsNothing, reason: 'the sheet closed');
    expect(find.descendant(of: find.byKey(const Key('settingsAppearance')), matching: find.text('Dark')), findsOneWidget);
    expect(brightness(t), 'dark');
    expect((await SharedPreferences.getInstance()).getString(ThemePreference.prefsKey), 'dark');
  });
}
