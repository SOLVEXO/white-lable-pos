// ignore_for_file: avoid_print
// Phase 2, registered till with a running shift (device mode): splash -> POS home; the till locks -> the PIN pad
// reports a failed check (the real PIN endpoint is unreachable here) -> "Switch user" lands on the PIN login.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
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

  testWidgets('device mode + shift: splash -> POS home; lock -> failed unlock; switch user -> PIN login', (t) async {
    await AppPreferences.clearPreference();
    await AppPreferences.clearTokens();
    await AppPreferences.setPosSoundEffects(false);
    await AppPreferences.setTokens(accessToken: 'device-token', refreshToken: 'x');
    await AppPreferences.setUserRole('seller');
    await AppPreferences.saveStoreId('store-1');
    await AppPreferences.setHasSeenOnboarding(true);
    await AppPreferences.saveDeviceRegistration(deviceToken: 'device-token', deviceId: 'dev-1', name: 'Front iPad', storeId: 'store-1', registerId: 'register-1');
    await AppPreferences.savePosEmployee(id: 'emp-1', name: 'Cal', role: 'cashier');
    await AppPreferences.setPosEmployeeEmail('cal@example.com');
    await AppPreferences.savePosSession(sessionId: 's-1', registerId: 'register-1', shiftId: 'sh-1');

    app.main();
    await t.pump();
    await pumpUntil(t, () => Get.currentRoute == Routes.posHome);
    print('✅ splash routed a registered till with a running shift to POS home');
    await pumpFor(t, const Duration(seconds: 2));

    // Idle -> lock (the timing rule is unit-tested; here the real overlay goes up over the real app).
    await t.runAsync(() => Get.find<IdleLockService>().lock());
    await pumpFor(t, const Duration(milliseconds: 800));
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Cal — enter your PIN to continue'), findsOneWidget);
    print('SHOT locked');
    await pumpFor(t, const Duration(seconds: 1));

    // A wrong/unverifiable PIN stays locked and says so (and the dots shake).
    for (final d in ['1', '2', '3', '4']) {
      await t.tap(find.descendant(of: find.byType(PinPad), matching: find.text(d)).first);
      await pumpFor(t, const Duration(milliseconds: 150));
    }
    await pumpUntil(t, () => find.text("Couldn't check the PIN. Try again.").evaluate().isNotEmpty || find.text('Wrong PIN.').evaluate().isNotEmpty, timeout: const Duration(seconds: 40));
    expect(find.text('Locked'), findsOneWidget);
    print('SHOT lock_error');
    await pumpFor(t, const Duration(seconds: 1));
    print('✅ failed unlock keeps the till locked and shows the error');
    print('SHOT lock');
    await pumpFor(t, const Duration(milliseconds: 1800));

    // Switch user.
    await t.tap(find.byKey(const Key('lockSwitchUser')));
    await pumpUntil(t, () => Get.currentRoute == Routes.posPinLogin, timeout: const Duration(seconds: 40));
    await pumpFor(t, const Duration(seconds: 1));
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Employee login'), findsOneWidget);
    print('SHOT pin_after_switch');
    await pumpFor(t, const Duration(seconds: 1));
    print('✅ switch user -> PIN login');
    print('SHOT pin');
    await pumpFor(t, const Duration(milliseconds: 1800));
  });
}
