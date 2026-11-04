// REAL end-to-end at the WIDGET level: the shipped app (app.main()) on the simulator against the real local backend.
// Drives: owner login screen → store list → set up this device → employee PIN keypad → open-register screen, then checks
// the backend independently. No fakes. Run: tool/run_real_e2e.sh integration_test/real_backend_ui_test.dart
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/store_card.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart' show AppButton;
import 'package:solvexo_pos/main.dart' as app;
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(WidgetTester t, bool Function() cond, {Duration timeout = const Duration(seconds: 45), String? what}) async {
    final end = DateTime.now().add(timeout);
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for ${what ?? 'condition'} (route: ${Get.currentRoute})');
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  // Phase 2 redesign: fields now carry floating LABELS (not hints) — match on the label text
  Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

  testWidgets('owner login → store → set up device → PIN keypad → open-register, against the real backend', (tester) async {
    final owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final store = await owner.mainStore();
    await owner.revokeAllDevices(store.storeId);

    await AppPreferences.clearPreference();
    await AppPreferences.setPosSoundEffects(false);
    await AppPreferences.setHasSeenOnboarding(true);

    app.main();
    await tester.pump();

    // ── owner login screen ─────────────────────────────────────────────────────────────────────────────────────────
    await pumpUntil(tester, () => field('Email').evaluate().isNotEmpty, what: 'the owner login screen');
    await tester.enterText(field('Email'), ownerEmail);
    await tester.enterText(field('Password'), ownerPassword);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sign in').last);
    await pumpUntil(tester, () => find.text('Dev Coffee').evaluate().isNotEmpty, what: 'the store list with Dev Coffee');
    expect(AppPreferences.cachedToken, isNotEmpty, reason: 'owner session stored');

    // ── pick the store, then the device-setup screen ──────────────────────────────────────────────────────────────
    final card = find.ancestor(of: find.text('Dev Coffee').first, matching: find.byType(StoreCard)).first;
    await tester.tap(find.descendant(of: card, matching: find.text('Open')));
    await pumpUntil(tester, () => Get.currentRoute == Routes.sellerHome, what: 'seller home');
    Get.toNamed(Routes.posDeviceSetup);
    await pumpUntil(tester, () => find.byKey(const Key('setupConfirm')).evaluate().isNotEmpty, what: 'device setup screen');
    await pumpUntil(tester, () {
      final b = find.byKey(const Key('setupConfirm')).evaluate().firstOrNull?.widget as AppButton?;
      return b?.onPressed != null;
    }, what: 'a register to be selected');
    await tester.enterText(find.byKey(const Key('setupName')), 'UI e2e iPhone');
    await tester.tap(find.byKey(const Key('setupConfirm')));
    await pumpUntil(tester, () => Get.currentRoute == Routes.posPinLogin, what: 'the PIN login screen');
    expect(AppPreferences.cachedDeviceMode, isTrue);
    final reg = await AppPreferences.getDeviceRegistration();
    expect(reg.storeId, store.storeId);
    expect(reg.name, 'UI e2e iPhone');
    expect((await owner.devices(store.storeId)).any((d) => d['name'] == 'UI e2e iPhone' && d['status'] == 'active'), isTrue, reason: 'the backend registered this device');

    // ── employee PIN login on the keypad: wrong PIN first, then the right one ─────────────────────────────────────
    await pumpUntil(tester, () => field('Employee email').evaluate().isNotEmpty, what: 'PIN email field');
    await tester.enterText(field('Employee email'), cashierEmail);
    await tester.pump(const Duration(milliseconds: 300));
    Future<void> keys(String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d).first);
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await keys('9999');
    await pumpFor(tester, const Duration(seconds: 3));
    expect(Get.currentRoute, Routes.posPinLogin, reason: 'a wrong PIN keeps the user on the PIN screen');
    expect(await AppPreferences.getPosEmployeeToken(), isNull);

    await keys(cashierPin);
    await pumpUntil(tester, () => Get.currentRoute == Routes.posOpenRegister || Get.currentRoute == Routes.posHome, what: 'open-register / home after the right PIN');
    expect(await AppPreferences.getPosEmployeeToken(), isNotEmpty, reason: 'signed-in employee token stored');
    expect(await AppPreferences.getPosEmployeeRole(), 'cashier');
    print('UI flow reached ${Get.currentRoute}');

    // cleanup: remove the test device through the real API
    for (final d in await owner.devices(store.storeId)) {
      if (d['name'] == 'UI e2e iPhone' && d['status'] == 'active') await owner.post('/api/pos/devices/${store.storeId}/${d['_id']}/revoke');
    }
    await AppPreferences.clearPreference();
    // the wrong-PIN toast is a GetX snackbar: let it finish, or its ticker is reported as leaked when the tree is torn down
    Get.closeAllSnackbars();
    await pumpFor(tester, const Duration(seconds: 4));
  });
}

Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
  }
}
