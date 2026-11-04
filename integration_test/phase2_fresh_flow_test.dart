// ignore_for_file: avoid_print
// Phase 2 (splash + auth), real app on a simulator, first launch: splash -> onboarding (Next, Next, Get started)
// -> owner login with inline validation. No token is seeded, so boot makes no authenticated call.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/modules/splash_screen/views/splash_screen_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/main.dart' as app;
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(WidgetTester t, bool Function() ok, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition');
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFor(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('fresh install: splash -> onboarding -> login (inline validation)', (t) async {
    await AppPreferences.clearPreference(); // a clean install
    await AppPreferences.clearTokens();
    await AppPreferences.setPosSoundEffects(false);

    final started = DateTime.now();
    app.main();
    await t.pump();
    await pumpUntil(t, () => find.byType(SplashScreenView).evaluate().isNotEmpty);
    final splashShownAt = DateTime.now();
    print('✅ Flutter splash is up');

    await pumpUntil(t, () => Get.currentRoute == Routes.onboarding);
    final splashMs = DateTime.now().difference(splashShownAt).inMilliseconds;
    print('✅ splash -> onboarding after ${splashMs}ms (was a fixed 5200ms)');
    print('SHOT onboarding');
    await pumpFor(t, const Duration(milliseconds: 1800));
    expect(splashMs, lessThan(2500), reason: 'animation ~1.4s + the session check, no artificial delay');
    expect(DateTime.now().difference(started).inSeconds, lessThan(40));
    await pumpFor(t, const Duration(milliseconds: 600));

    print('SHOT onboarding_1');
    await pumpFor(t, const Duration(seconds: 1));
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('Next'));
      await pumpFor(t, const Duration(milliseconds: 700));
    }
    expect(find.text('Get started'), findsOneWidget);
    print('SHOT onboarding_last');
    await pumpFor(t, const Duration(seconds: 1));
    await t.tap(find.text('Get started'));
    await pumpUntil(t, () => Get.currentRoute == Routes.posLogin);
    expect(await AppPreferences.getHasSeenOnboarding(), isTrue);
    print('✅ onboarding finished -> login, seen flag set');
    print('SHOT login');
    await pumpFor(t, const Duration(milliseconds: 1800));
    await pumpFor(t, const Duration(seconds: 1));

    // inline validation (nothing is sent)
    await t.tap(find.text('Sign in').last);
    await pumpFor(t, const Duration(milliseconds: 500));
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    print('SHOT login_errors');
    await pumpFor(t, const Duration(seconds: 1));
    print('✅ inline validation shown');
    print('SHOT login_validation');
    await pumpFor(t, const Duration(milliseconds: 1800));
  });
}
