// Screenshot pass for the Raast QR screen and the payment chooser on the iOS simulator (real rendering, real fonts).
// Prints `SHOT <name>` for tools/shoot-style capture; theme via --dart-define=QR_THEME=light|dark.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_screen.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/payment_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';

import '../test/support/fake_payments.dart';
import '../test/support/sale_harness.dart';

const _theme = String.fromEnvironment('QR_THEME', defaultValue: 'light');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final dark = _theme == 'dark';
  final theme = dark ? AppTheme.dark : AppTheme.light;
  Future<void> shot(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    print('SHOT $name');
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  }

  Future<RaastQrController> showQr(WidgetTester t, FakePaymentsRepo pay, {String tag = 'shot'}) async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    final c = RaastQrController(
      amountMinor: 150000, sessionId: 's', saleAttemptKey: 'k', repository: pay, store: memoryQrStore(),
      pollInterval: const Duration(milliseconds: 150), tick: const Duration(milliseconds: 150), clock: () => serverNow, keepAwake: (_) async {},
    );
    Get.put<RaastQrController>(c, tag: tag);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: RaastQrScreen(key: ValueKey(tag), tag: tag))); // a new State per payment (the screen captures its controller once)
    await t.pump(const Duration(milliseconds: 600));
    return c;
  }

  testWidgets('QR screen: every state', (t) async {
    // waiting
    var pay = FakePaymentsRepo();
    var c = await showQr(t, pay);
    await t.pump(const Duration(milliseconds: 400));
    await shot('qr_1_waiting');

    // checking (network dropped)
    pay.getScript..clear()..add(FakePaymentsRepo.offline());
    await t.pump(const Duration(milliseconds: 600));
    await shot('qr_2_checking');
    c.onClose();

    // creating
    pay = FakePaymentsRepo()..createDelay = const Duration(minutes: 5);
    await showQr(t, pay, tag: 'creating');
    await shot('qr_0_creating');

    // low time left
    pay = FakePaymentsRepo()
      ..createAnswers.add(FakePaymentsRepo.ok(fakeIntent('pi-1', secondsLeft: 22)))
      ..getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', secondsLeft: 22)));
    await showQr(t, pay, tag: 'low');
    await t.pump(const Duration(milliseconds: 400));
    await shot('qr_3_low_time');

    for (final (name, status, late) in [('qr_4_confirmed', PosQrStatus.confirmed, false), ('qr_5_expired', PosQrStatus.expired, false), ('qr_6_failed', PosQrStatus.failed, false), ('qr_7_cancelled', PosQrStatus.cancelled, false), ('qr_8_paid_after_expiry', PosQrStatus.confirmed, true)]) {
      pay = FakePaymentsRepo()..getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-x', status: status, secondsLeft: 0, paidAfterExpiry: late)));
      await showQr(t, pay, tag: name);
      await t.pump(const Duration(milliseconds: 700));
      await shot(name);
    }

    // unavailable
    pay = FakePaymentsRepo()..createAnswers.add(FakePaymentsRepo.refused('STORE_NOT_VERIFIED'));
    await showQr(t, pay, tag: 'unavail');
    await t.pump(const Duration(milliseconds: 400));
    await shot('qr_9_unavailable');
    Get.reset();
  });

  testWidgets('payment chooser: who sees what', (t) async {
    final h = SaleHarness();
    Future<void> chooser(String name, {required bool? verified, required bool online, required bool manager}) async {
      Get.reset();
      Get.put(NetworkStatusService()).isOnline.value = online;
      Get.put(PosEntitlementService()).digitalPaymentsEnabled.value = verified;
      h.putController(manager: manager, payments: FakePaymentsRepo(), qrStore: memoryQrStore());
      h.addLine(h.products[0]);
      await t.pumpWidget(GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: PaymentSheet(c: h.c)))))));
      await t.pump(const Duration(milliseconds: 800));
      await shot(name);
    }

    await chooser('chooser_1_available', verified: true, online: true, manager: false);
    await chooser('chooser_2_cashier_not_verified', verified: false, online: true, manager: false);
    await chooser('chooser_3_manager_not_verified', verified: false, online: true, manager: true);
    await chooser('chooser_4_offline', verified: true, online: false, manager: false);
    Get.reset();
  });
}
