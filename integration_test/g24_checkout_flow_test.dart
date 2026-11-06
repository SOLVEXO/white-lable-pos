// REAL end-to-end for G2.4 on the iOS simulator against the dev stack (real repositories, real SQLite queue, real API, mock payment provider):
//   1 full sale: search → variant → coupon → split cash + card → the receipt QR link opens the public page
//   2 custom item above the limit: a cashier is refused, a manager's PIN (the real sheet) approves it, stock untouched
//   3 shift close with a card-slip variance: refused without a manager, closes with one; reconciliation recorded
//   4 offline sale → sync (API stopped, the sale is queued, the API returns, the queue empties) — a coupon is NEVER queued
//   5 scan latency measured on the simulator
// Run:  (solvexo-api) bash dev/up.sh && npm run dev:seed      then   tool/run_real_e2e.sh integration_test/g24_checkout_flow_test.dart
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;
  final plain = Dio(BaseOptions(validateStatus: (_) => true, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final couponCode = 'E2E${stamp % 100000}';

  setUpAll(() async {
    SoundUtil.enabled = false; // the audio plugin keeps a frame callback alive after the test ends
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    await t.setUpDevice(name: 'g24 stock probe');
    await t.pinLogin(managerEmail, managerPin);
    final v = await t.variantsBySku();
    for (final sku in ['DEV-LATTE', 'DEV-BEANS']) {
      await owner.topUp(storeId, v[sku]!.variantId, v[sku]!.stock, 80);
    }
    await t.closeAnyOpenShift();
    await t.dispose();
    // a POS coupon: 10% off, usable at the till
    final r = await owner.post('/api/marketing/$storeId/coupons', {'code': couponCode, 'discountType': 'percentage', 'discountValue': 10, 'posEnabled': true, 'scope': 'seller'});
    expect(r.statusCode, anyOf(200, 201), reason: 'create coupon: ${r.data}');
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<PosHomeController> home(WidgetTester tester, Till t, String sessionId) async {
    final c = PosHomeController(posRepository: t.repo);
    Get.put<PosHomeController>(c);
    await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));
    c.storeId.value = storeId;
    c.sessionId.value = sessionId;
    c.registerId.value = registerId;
    c.employeeId.value = t.employee!.id;
    await eventually(() async => c.allProducts.isNotEmpty, reason: 'catalogue loaded');
    await eventually(() async => c.settings.value != null, reason: 'tax settings loaded');
    return c;
  }

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('1 full sale: search → variant → coupon → split cash + card → receipt QR link opens the public page', (tester) async {
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final c = await home(tester, t, session.id);
    final stockBefore = await t.stockOf('DEV-LATTE');

    // search
    c.searchController.text = 'Latte';
    c.onSearchChanged('Latte');
    await eventually(() async => c.allProducts.any((p) => p.name.contains('Latte')) && c.allProducts.length < 10, reason: 'search results');
    final latte = c.allProducts.firstWhere((p) => p.name.contains('Latte'));
    // variant (explicit, as the variant picker does)
    c.addToCart(latte, latte.variants.first);
    c.addToCart(latte, latte.variants.first);
    expect(c.itemCount, 2);

    // coupon: a live check on the real server
    expect(await c.applyCoupon(couponCode.toLowerCase()), isNull);
    expect(c.appliedCoupon.value!.code, couponCode);
    expect(c.totals.discount, 1.0); // 10% of 10.00
    // wrong code → the server's reason
    c.removeCoupon();
    expect(await c.applyCoupon('NOPE-$stamp'), isNotNull);
    expect(await c.applyCoupon(couponCode), isNull);

    // split cash + card: total = (10.00 - 1.00) + 10% tax on 9.00 = 9.90
    expect(c.total, 9.9);
    c.isSplitPayment.value = true;
    c.splitLines.clear();
    final cash = SplitPaymentLine('cash')..amount.text = '5.00';
    final card = SplitPaymentLine('card')..amount.text = '4.90';
    card.reference.text = 'AUTH-$stamp';
    c.splitLines.addAll([cash, card]);
    await c.completeSale();
    await pumpFor(tester, const Duration(seconds: 2));
    expect(c.lastOutcome.value, SaleOutcome.completed, reason: 'sale should complete');
    final receipt = c.lastReceipt.value!;
    expect(receipt.saleId, isNotNull);
    expect(await t.stockOf('DEV-LATTE'), stockBefore - 2);

    // the receipt QR link → the PUBLIC page (no auth), rendered by the API
    final url = await t.repo.getReceiptLink(receipt.saleId!);
    expect(url, isNotNull);
    final page = await plain.get('${AppEnv.apiBaseUrl}${Uri.parse(url!).path}');
    expect(page.statusCode, 200);
    final html = page.data as String;
    expect(html, contains(receipt.receiptNumber));
    expect(html, contains('9.90'));
    expect(html.toLowerCase(), isNot(contains('@solvexo.dev')));
    // a guessed token is a plain 404
    final bad = await plain.get('${AppEnv.apiBaseUrl}/r/${'A' * 32}');
    expect(bad.statusCode, 404);
    // the same link every time; revoking (manager) kills it
    expect(await t.repo.getReceiptLink(receipt.saleId!), url);
    // a manager revokes it (owner JWT + the manager's PIN-session token): the page is a 404 from then on
    final revoke = await plain.post('${AppEnv.apiBaseUrl}/api/pos/sales/${receipt.saleId}/receipt-link/revoke', options: Options(headers: {'Authorization': 'Bearer ${owner.ownerToken}', 'x-pos-employee-token': (await AppPreferences.getPosEmployeeToken()) ?? ''}));
    expect(revoke.statusCode, anyOf(200, 201), reason: 'revoke: ${revoke.data}');
    expect((await plain.get('${AppEnv.apiBaseUrl}${Uri.parse(url).path}')).statusCode, 404);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  testWidgets('2 custom item: a cashier is refused (manager needed), the real PIN sheet approves, no stock moves, the sale is recorded as custom', (tester) async {
    final t = await till(cashierEmail, cashierPin);
    final session = await t.openShift(openingCash: 50);
    final c = await home(tester, t, session.id);
    final stockBefore = await t.stockOf('DEV-LATTE');
    c.selectedPayment.value = PosPaymentMethod.card;
    expect(c.addCustomItem(name: 'Engraving', price: 20, taxCategory: 'exempt', note: 'e2e'), isTrue);
    final sale = c.completeSale(); // the server asks for a manager → the approval sheet opens
    await pumpFor(tester, const Duration(seconds: 3));
    expect(find.byKey(const Key('approverEmail')), findsOneWidget, reason: 'manager approval sheet');
    await tester.enterText(find.byKey(const Key('approverEmail')), managerEmail);
    for (final d in managerPin.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await pumpFor(tester, const Duration(seconds: 3));
    await sale;
    await pumpFor(tester, const Duration(seconds: 2));
    expect(c.lastOutcome.value, SaleOutcome.completed);
    expect(await t.stockOf('DEV-LATTE'), stockBefore, reason: 'a custom item never touches stock');
    final saleId = c.lastReceipt.value!.saleId!;
    expect(saleId, isNotEmpty);
    final audit = await owner.get('/api/pos/audit-logs/$storeId');
    expect(audit.data.toString(), contains('custom_item_sold'), reason: 'the custom item is audited');
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  testWidgets('3 shift close with a card-slip variance: refused for a cashier, a manager\'s approval closes it, reconciliation recorded', (tester) async {
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final c = await home(tester, t, session.id);
    c.selectedPayment.value = PosPaymentMethod.card;
    final latte = c.allProducts.firstWhere((p) => p.name.contains('Latte'));
    c.addToCart(latte, latte.variants.first);
    await c.completeSale(); // 5.00 + 10% tax = 5.50 on the card
    await pumpFor(tester, const Duration(seconds: 2));
    expect(c.lastOutcome.value, SaleOutcome.completed);
    await t.dispose();

    // a CASHIER signs in on the same register and tries to close with a slip that does not match
    final cashier = await till(cashierEmail, cashierPin);
    final active = await cashier.repo.getActiveSession(storeId: storeId, registerId: registerId);
    final refused = await cashier.repo.closeSession(sessionId: active!.id, closingCash: active.expectedCash, cardTotalFromSlip: 4.00);
    expect(refused.success, isFalse);
    expect(cashier.repo.lastErrorCode, 'CARD_VARIANCE_APPROVAL_REQUIRED');
    // the manager approves with their PIN (token), the same call succeeds
    final mgr = await cashier.repo.pinLogin(storeId: storeId, email: managerEmail, pin: managerPin);
    expect(mgr.employee!.role, 'manager');
    final closed = await cashier.repo.closeSession(sessionId: active.id, closingCash: active.expectedCash, cardTotalFromSlip: 4.00, approverToken: mgr.employeeToken);
    expect(closed.success, isTrue, reason: closed.message ?? '');
    await cashier.dispose();
  });

  testWidgets('4 offline: the API is stopped, a cash sale is queued, the API returns and the queue syncs; a coupon sale is NOT queued', (tester) async {
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final c = await home(tester, t, session.id);
    final stockBefore = await t.stockOf('DEV-BEANS');
    final beans = c.allProducts.firstWhere((p) => p.name.contains('Beans'));
    c.addToCart(beans, beans.variants.first);
    c.selectedPayment.value = PosPaymentMethod.cash;
    c.tenderedController.text = '30';
    await Control.stopApi();
    try {
      await c.completeSale();
      await pumpFor(tester, const Duration(seconds: 2));
      expect(c.lastOutcome.value, SaleOutcome.queuedOffline);
      expect(t.sync.items.where((i) => i.isUnresolved), isNotEmpty);
      // a coupon sale offline: never queued — the cashier is told to retry when the connection is back
      c.addToCart(beans, beans.variants.first);
      c.appliedCoupon.value = PosAppliedCoupon(code: couponCode, discountType: 'percentage', discountValue: 10);
      c.selectedPayment.value = PosPaymentMethod.cash;
      c.tenderedController.text = '40';
      final before = t.sync.items.length;
      await c.completeSale();
      await pumpFor(tester, const Duration(seconds: 2));
      expect(t.sync.items.length, before, reason: 'a coupon sale must not enter the offline queue');
      expect(c.lastOutcome.value, isNull);
    } finally {
      await Control.startApi();
    }
    await eventually(() async {
      await t.sync.syncNow(ignoreBackoff: true);
      await t.sync.refreshCounts();
      return t.sync.items.where((i) => i.isUnresolved).isEmpty;
    }, timeout: const Duration(seconds: 60), reason: 'queue empty after the API is back');
    expect(await t.stockOf('DEV-BEANS'), stockBefore - 1);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  testWidgets('5 scan latency on the simulator: local catalogue hit and server fallback', (tester) async {
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final c = await home(tester, t, session.id);
    // warm path (catalogue on the device)
    await c.addProductByBarcode('1000000000011');
    final local = c.lastScanMs!;
    expect(c.cartItems.single.product.name, contains('Latte'));
    // cold path (not in the loaded page → the server)
    c.allProducts.clear();
    await c.addProductByBarcode('1000000000042');
    final server = c.lastScanMs!;
    print('SCAN LATENCY (iOS simulator): local catalogue $local ms, server lookup $server ms');
    expect(local, lessThan(300));
    await t.closeAnyOpenShift();
    await t.dispose();
  });
}
