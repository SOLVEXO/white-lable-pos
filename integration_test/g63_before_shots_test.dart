// G6.3 "before" screenshots: every screen the UI-consistency audit marks Old or Mixed, as the shipped app draws it today (phone, light), against the
// REAL local backend (seeded store, real data, real repositories). The device is set up and a shift opened through the app's own code, the owner gate
// is opened (so owner-only screens render), then the shipped app (app.main()) starts and each route is pushed in turn.
// Run (dev stack up + seeded):  SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g63_before_shots_test.dart docs/pos-blueprint/g6_3_screenshots/before/screens light
//   (the e2e control sidecar is not needed)
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
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
    await settle(t, 600);
    print('SHOT $name');
    await settle(t, 3000);
  }

  testWidgets('G6.3 before: every Old / Mixed screen (phone, light)', (t) async {
    SoundUtil.enabled = false;
    final owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    await owner.revokeAllDevices(s.storeId);
    final till = await Till.boot(storeId: s.storeId, registerId: s.registerId);
    expect('${await till.setUpDevice(name: 'G6.3 shots')}', endsWith('.ok'));
    await till.pinLogin(managerEmail, managerPin);
    final session = await till.openShift(openingCash: 100);
    final sale = await till.repo.createSale(
      storeId: s.storeId, sessionId: session.id, registerId: s.registerId, employeeId: till.employee!.id,
      items: [await till.line('DEV-REFILL', 2)], paymentMethod: 'cash', status: 'completed',
    );
    expect(sale.success, isTrue, reason: '${sale.message}');
    await AppPreferences.setHasSeenOnboarding(true);
    await AppPreferences.setPosAutoLockMinutes(120); // the 5-minute idle lock would cover the later screens
    Get.reset();

    app.main();
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (Get.currentRoute != Routes.posHome) {
      if (DateTime.now().isAfter(end)) fail('never reached the POS home (route ${Get.currentRoute})');
      await t.pump(const Duration(milliseconds: 250));
    }
    await settle(t, 4000);
    OwnerSession.start(owner.ownerToken); // the owner gate is open, so owner-only screens render instead of the gate

    final nav = Get.find<PosBottomNavController>();
    // G63_FROM=<n> re-shoots from the n-th screen on (the tabs only on a full run)
    const from = int.fromEnvironment('G63_FROM', defaultValue: 1);
    if (from == 1) {
      nav.changeTab(PosBottomNavController.saleTab);
      await shot(t, 'g63b_tab_sell');
      nav.changeTab(PosBottomNavController.ordersTab);
      await shot(t, 'g63b_tab_orders');
    }

    final screens = <(String, String, Object?)>[
      ('posHeldSales', Routes.posHeldSales, null),
      ('posSaleDetail', Routes.posSaleDetail, sale.sale!.id),
      ('posSessionReport', Routes.posSessionReport, session.id),
      ('posSessionHistory', Routes.posSessionHistory, null),
      ('posDailyReport', Routes.posDailyReport, null),
      ('posRangeReport', Routes.posRangeReport, null),
      ('posProducts', Routes.posProducts, null),
      ('posCatalog', Routes.posCatalog, null),
      ('posCatalogImport', Routes.posCatalogImport, null),
      ('posInventory', Routes.posInventory, null),
      ('posStockActivity', Routes.posStockActivity, null),
      ('posStockCount', Routes.posStockCount, null),
      ('posNeedsAttention', Routes.posNeedsAttention, null),
      ('posCustomers', Routes.posCustomers, null),
      ('posSupplyOrderForm', Routes.posSupplyOrderForm, null),
      ('posSupplyReceive', Routes.posSupplyReceive, null),
      ('posCash', Routes.posCash, null),
      ('posCashExpenses', Routes.posCashExpenses, null),
      ('posSettings', Routes.posSettings, null),
      ('posSettingsHub', Routes.posSettingsHub, null),
      ('posReceiptDesigner', Routes.posReceiptDesigner, null),
      ('posAlertSettings', Routes.posAlertSettings, null),
      ('posSecuritySettings', Routes.posSecuritySettings, null),
      ('posBackupSync', Routes.posBackupSync, null),
      ('posIntegrations', Routes.posIntegrations, null),
      ('posDevices', Routes.posDevices, null),
      ('posDeleteAccount', Routes.posDeleteAccount, null),
      ('posPlanStatus', Routes.posPlanStatus, null),
      ('posPlanInactive', Routes.posPlanInactive, null),
      ('sellerPosManagement', Routes.sellerPosManagement, null),
      ('sellerPosLocations', Routes.sellerPosLocations, null),
      ('sellerStores', Routes.sellerStores, null),
      ('sellerOnboarding', Routes.sellerOnboarding, null),
      ('onboarding', Routes.onboarding, null),
      ('posOpenRegister', Routes.posOpenRegister, {'employee': till.employee, 'registerId': s.registerId, 'registerName': 'Front counter', 'storeId': s.storeId}),
      ('posPinLogin', Routes.posPinLogin, null),
    ];
    var i = 0;
    for (final (name, route, args) in screens) {
      i++;
      if (i < from) continue;
      Get.toNamed(route, arguments: args);
      await settle(t, 3500);
      await shot(t, 'g63b_${i.toString().padLeft(2, '0')}_$name');
      if (Get.currentRoute != Routes.posHome) Get.until((r) => r.settings.name == Routes.posHome || r.isFirst);
      await settle(t, 800);
    }
    // leave the dev store as it was
    await AppPreferences.setPosAutoLockMinutes(5);
    await till.closeAnyOpenShift();
    await owner.revokeAllDevices(s.storeId);
  });
}
