// G6.4 dark-mode spot-check on the REAL local backend: the device's Appearance is set to Dark through the real setting (ThemePreference's saved
// key), the shipped app starts (app.main()), and it is driven by taps through: dashboard → a cash sale from the Sell tab to sale success →
// products → orders → settings (+ the Appearance sheet) → the close-shift dialog (cancelled, so the shift stays open). Any layout or render
// error fails the test. Run (dev stack up + seeded):
//   SIM_DEVICE_ID=<udid> tool/shoot_real.sh integration_test/g64_dark_spotcheck_test.dart docs/pos-blueprint/g6_4_screenshots/dark phone
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/theme_preference.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_close_shift_button.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/main.dart' as app;
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 2500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (Get.isRegistered<IdleLockService>()) Get.find<IdleLockService>().onActivity();
    await settle(t, 800);
    print('SHOT $name');
    await settle(t, 2500);
  }

  Future<void> until(WidgetTester t, bool Function() cond, String what, {int seconds = 30}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!cond()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what (route ${Get.currentRoute})');
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('G6.4 dark spot-check: dashboard, checkout → sale success, products, orders, settings, shift close', (t) async {
    SoundUtil.enabled = false;
    final owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    await owner.revokeAllDevices(s.storeId);
    final till = await Till.boot(storeId: s.storeId, registerId: s.registerId);
    expect('${await till.setUpDevice(name: 'G6.4 dark')}', endsWith('.ok'));
    await till.pinLogin(managerEmail, managerPin);
    await till.openShift(openingCash: 100);
    await AppPreferences.setHasSeenOnboarding(true);
    await AppPreferences.setPosAutoLockMinutes(120);
    // the real setting: Settings → Appearance → Dark, as saved on the device
    await (await SharedPreferences.getInstance()).setString(ThemePreference.prefsKey, AppearanceChoice.dark.name);
    Get.reset();

    app.main();
    await until(t, () => Get.currentRoute == Routes.posHome, 'the POS home', seconds: 60);
    await settle(t, 4000);
    OwnerSession.start(owner.ownerToken);
    expect(Get.find<ThemePreference>().choice.value, AppearanceChoice.dark);
    expect(Theme.of(Get.context!).brightness, Brightness.dark, reason: 'the saved choice applied before the first screen');

    final nav = Get.find<PosBottomNavController>();
    nav.changeTab(PosBottomNavController.homeTab);
    await shot(t, 'g64_01_dashboard');

    // checkout: add a product, open the cart, charge cash (a quick amount), confirm → sale success
    nav.changeTab(PosBottomNavController.saleTab);
    await until(t, () => find.byType(ProductTile).evaluate().isNotEmpty, 'the product grid');
    await t.tap(find.byType(ProductTile).first);
    await settle(t, 800);
    await shot(t, 'g64_02_sell_item_added');
    await t.tap(find.byKey(const Key('pillCount')));
    await settle(t, 1200);
    await shot(t, 'g64_03_cart');
    await t.tap(find.byKey(const Key('chargeButton')));
    await settle(t, 1500);
    final quick = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('quick-'));
    await until(t, () => quick.evaluate().isNotEmpty, 'the cash quick amounts');
    await t.tap(quick.first);
    await settle(t, 600);
    await shot(t, 'g64_04_payment_cash');
    await t.tap(find.byKey(const Key('confirmCharge')));
    await until(t, () => find.byKey(const Key('successTitle')).evaluate().isNotEmpty, 'sale success', seconds: 45);
    await shot(t, 'g64_05_sale_success');
    await t.tap(find.byKey(const Key('newSale')));
    await settle(t, 1500);

    Get.toNamed(Routes.posProducts);
    await settle(t, 3500);
    await shot(t, 'g64_06_products');
    Get.back();
    await settle(t, 800);

    nav.changeTab(PosBottomNavController.ordersTab);
    await settle(t, 3500);
    await shot(t, 'g64_07_orders');

    Get.toNamed(Routes.posSettings);
    await until(t, () => find.byKey(const Key('settingsAppearance')).evaluate().isNotEmpty, 'the settings screen');
    await settle(t, 1000);
    await shot(t, 'g64_08_settings');
    await t.tap(find.byKey(const Key('settingsAppearance')));
    await settle(t, 1200);
    await shot(t, 'g64_09_settings_appearance_sheet');
    await t.tap(find.byKey(const Key('appearance_dark'))); // keep Dark (closes the sheet)
    await settle(t, 1200);

    // shift close: the dialog with the live cash breakdown — cancelled, so the shift stays open for clean-up
    await t.scrollUntilVisible(find.byType(PosCloseShiftButton), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byType(PosCloseShiftButton));
    await until(t, () => find.text('Cancel').evaluate().isNotEmpty, 'the close-shift dialog');
    await settle(t, 1000);
    await shot(t, 'g64_10_close_shift_dialog');
    await t.tap(find.text('Cancel').last);
    await settle(t, 1000);

    await till.closeAnyOpenShift();
    await owner.revokeAllDevices(s.storeId);
  });
}
