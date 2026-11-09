// REAL end-to-end for G3.2 (lot sale rules) and G3.3 (customers, store credit, loyalty) on the iOS simulator against the dev stack
// (real repositories, real API, the real till controllers; the manager-approval sheet is the real one where the flow needs it):
//   a  add a customer by phone (a second add with the same phone is the SAME customer); a bad phone is refused under its field
//   b  sell 6 DEV-YOGURT online: the cart line suggests LOT-SOON then LOT-LATER, the sale takes 5 + 1, the order shows the lots, stock and lots fall;
//      4 more are refused (only 2 sellable units remain) → a manager's PIN lets the cashier sell them: 2 sellable + 2 from the expired lot → LOT-OLD falls and the audit exists
//   c  a sale paid with 10.00 store credit + cash for the credit customer → the balance drops by exactly 10.00
//   d  redeem 10 points on a sale → the server's discount is applied, points fall by 10 and the earned points are added
//   e  a cashier returns that sale to store credit: within the limit alone, above a lowered limit with a manager's PIN (real sheet)
//   f  the credit balance equals the expected figure after every step
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g32_g33_flow_test.dart
// Afterwards `npm run dev:seed` puts the lots, the points and the stock back (the credit is restored by the test itself).
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

const _creditPhone = '03001112222'; // "Dev Customer (credit)" in solvexo-api/dev/seed.ts: 20.00 credit, 40 points, 1 point per 10.00, a point is 0.50
const _limitKey = 'storeCreditRefundMinor';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    SoundUtil.enabled = false;
    ReasonPicker.testOverride = (_) async => const PosReasonChoice('customer_changed_mind', 'e2e');
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'g32/g33 probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> app(WidgetTester tester) => tester.pumpWidget(
    ResponsiveSizer(
      builder: (_, __, ___) => GetMaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );

  /// The sale screen's controller on a real till (after [app], so snackbars and Get.back() have a navigator).
  Future<PosHomeController> home(WidgetTester tester, Till t, String sessionId, {Future<String?> Function({required String reason, PosRepository? repository})? approval}) async {
    final c = PosHomeController(posRepository: t.repo, approval: approval);
    Get.put<PosHomeController>(c);
    c.storeId.value = storeId;
    c.sessionId.value = sessionId;
    c.registerId.value = registerId;
    c.employeeId.value = t.employee!.id;
    await eventually(() async => c.allProducts.isNotEmpty, reason: 'catalogue loaded');
    await eventually(() async => c.settings.value != null, reason: 'tax settings loaded');
    return c;
  }

  Future<({PosProductModel product, PosProductVariant variant})> findProduct(PosHomeController c, String name) async {
    c.searchController.text = name;
    c.onSearchChanged(name);
    await eventually(() async => c.allProducts.any((p) => p.name.contains(name)) && c.allProducts.length < 10, reason: 'search $name');
    final p = c.allProducts.firstWhere((p) => p.name.contains(name));
    return (product: p, variant: p.variants.first);
  }

  Future<CustomerProfile> profileOf(Till t, String id) async => (await t.repo.getCustomerProfile(storeId, id))!;

  Future<InvDetail> detailOf(Till t, String variantId) async => (await t.repo.getInventoryVariant(storeId, variantId))!;

  Future<Map<String, dynamic>> limits() async {
    final r = await owner.get('/api/pos/inventory/limits/$storeId');
    expect(r.statusCode, 200, reason: '${r.data}');
    return {for (final l in (r.data['data']['limits'] as List).cast<Map>()) l['key'] as String: l['value']};
  }

  Future<void> setLimit(int minor) async {
    final r = await owner.patch('/api/pos/inventory/limits/$storeId', {_limitKey: minor});
    expect(r.statusCode, anyOf(200, 201), reason: 'limit: ${r.data}');
  }

  testWidgets('G3.2 lots + G3.3 customers, store credit, loyalty and returns to credit, end to end', (tester) async {
    final limitBefore = (await limits())[_limitKey] as int;
    final policy = await owner.get('/api/pos/settings/$storeId');
    print('limit before: $limitBefore, settings ${policy.statusCode}');
    int? creditBaseline;
    String? creditCustomerId;
    Till? t;
    try {
      // ── a · customers ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
      t = await till(managerEmail, managerPin);
      await app(tester); // after Till.boot (it resets GetX), so snackbars and Get.back() have a navigator
      final phone = '03${(DateTime.now().millisecondsSinceEpoch % 1000000000).toString().padLeft(9, '0')}';
      final first = CustomerFormController(repository: t.repo, storeId: storeId)
        ..name.value = 'E2E Walker'
        ..phone.value = phone;
      final created = await first.submit();
      expect(created, isNotNull, reason: first.error.value ?? '${first.fieldErrors}');
      expect(created!.existing, isFalse);
      final again = CustomerFormController(repository: t.repo, storeId: storeId)
        ..name.value = 'E2E Walker Again'
        ..phone.value = phone;
      final same = await again.submit();
      expect(same!.id, created.id, reason: 'the same phone is the same customer');
      expect(same.existing, isTrue);
      expect(same.name, 'E2E Walker', reason: 'the existing customer is returned unchanged');
      final bad = CustomerFormController(repository: t.repo, storeId: storeId)
        ..name.value = 'Bad Phone'
        ..phone.value = 'abc';
      expect(await bad.submit(), isNull);
      expect(bad.fieldErrors['phone'], isNotNull, reason: 'PHONE_INVALID lands under the phone field');
      final list = CustomerListController(repository: t.repo, storeId: storeId)..onInit();
      await list.search(phone);
      expect(list.items.map((c) => c.id), contains(created.id));
      list.onClose();
      print('a ok: customer ${created.id}, same-phone add -> existing=${same.existing}');

      final found = await t.repo.searchPosCustomers(storeId, _creditPhone);
      final credit = found!.items.firstWhere((c) => c.phone == _creditPhone);
      creditCustomerId = credit.id;
      final p0 = await profileOf(t, credit.id);
      creditBaseline = p0.creditBalanceMinor!;
      var expectedCredit = creditBaseline;
      var points = p0.loyaltyPoints;
      print('credit customer ${credit.id}: credit $creditBaseline minor, $points points');
      expect(p0.cur, const InvCur('USD', 2));
      expect(expectedCredit, greaterThanOrEqualTo(1000), reason: 'dev data: run npm run dev:seed (needs at least 10.00 credit)');

      // ── b · lots: FEFO, the order shows the lots, stock falls ─────────────────────────────────────────────────────────────
      final session = await t.openShift(openingCash: 100);
      var c = await home(tester, t, session.id);
      final yogurt = await findProduct(c, 'Yogurt');
      final vid = yogurt.variant.variantId;
      final before = await detailOf(t, vid);
      print('yogurt before: stock ${before.row.stock}, lots ${before.lots.map((l) => '${l.lotNumber}=${l.remaining}').join(', ')}, expired ${before.row.expiredUnits}');
      expect(before.row.trackLots, isTrue);
      expect(before.row.expiredUnits, 4, reason: 'dev data: run npm run dev:seed');
      c.addToCart(yogurt.product, yogurt.variant);
      for (var i = 0; i < 5; i++) {
        c.increment(c.cartItems.single);
      }
      final line = c.cartItems.single;
      await eventually(() async => line.lotPreviewLive.value && line.lotPreview.value?.qty == 6, reason: 'live lot suggestion for 6');
      final prev = line.lotPreview.value!;
      expect(prev.headline, startsWith('Lot LOT-SOON · expires in'));
      expect(prev.spill, '+ 1 from LOT-LATER');
      expect(prev.expiresWithin(7), isTrue, reason: 'the amber badge');
      expect(prev.shortBy, 0);
      c.selectedPayment.value = PosPaymentMethod.card;
      await c.completeSale();
      var sold = c.lastSale.value;
      expect(sold, isNotNull, reason: 'the 6-unit sale went through');
      final lots6 = sold!.items.single.lots;
      expect(lots6.map((l) => '${l.lotNumber}x${l.qty}'), ['LOT-SOONx5', 'LOT-LATERx1'], reason: 'first-expiry-first-out');
      expect(sold.items.single.soldExpired, isFalse);
      final order = (await t.repo.getSaleById(sold.id))!;
      expect(order.items.single.lots.map((l) => l.label), ['Lot LOT-SOON ×5', 'Lot LOT-LATER ×1'], reason: 'the order shows the lots');
      final afterSix = await detailOf(t, vid);
      expect(afterSix.row.stock, before.row.stock - 6);
      expect({for (final l in afterSix.lots) l.lotNumber: l.remaining}['LOT-LATER'], 2);
      print('b1 ok: lots ${lots6.map((l) => l.label).join(' + ')}; stock ${afterSix.row.stock}');
      await t.closeAnyOpenShift();
      await t.dispose();

      // 4 more as a cashier: only expired units are left beyond the 2 sellable ones → refused → a manager's PIN lets the cashier sell the expired lot
      t = await till(cashierEmail, cashierPin);
      await app(tester);
      final session2 = await t.openShift(openingCash: 50);
      final tillRef = t;
      c = await home(
        tester,
        t,
        session2.id,
        approval: ({required String reason, PosRepository? repository}) async {
          expect(reason, contains('expired stock'));
          final r = await tillRef.repo.pinLogin(storeId: storeId, email: managerEmail, pin: managerPin);
          return r.employeeToken;
        },
      );
      final y2 = await findProduct(c, 'Yogurt');
      c.addToCart(y2.product, y2.variant);
      for (var i = 0; i < 3; i++) {
        c.increment(c.cartItems.single);
      }
      final line2 = c.cartItems.single;
      await eventually(() async => line2.lotPreviewLive.value && line2.lotPreview.value?.qty == 4, reason: 'live lot suggestion for 4');
      expect(line2.lotPreview.value!.shortBy, 2);
      expect(line2.lotPreview.value!.expiredUnits, 4);
      expect(line2.lotPreview.value!.needsExpiredOverride, isTrue, reason: 'the "Sell expired stock (manager)" action is offered');
      c.selectedPayment.value = PosPaymentMethod.card;
      await c.completeSale();
      expect(c.lastSale.value, isNull, reason: 'refused: not enough sellable stock');
      expect((await detailOf(t, vid)).row.stock, afterSix.row.stock, reason: 'nothing was sold');
      expect(await c.approveSellExpired(line2), isTrue);
      expect(line2.sellExpired.value, isTrue);
      await c.completeSale();
      sold = c.lastSale.value;
      expect(sold, isNotNull, reason: 'the manager-approved sale of the expired lot went through');
      expect(sold!.items.single.soldExpired, isTrue);
      final expiredPart = sold.items.single.lots.where((l) => l.expired).fold<int>(0, (a, l) => a + l.qty);
      expect(expiredPart, 2, reason: 'only the 2 units the sellable lots could not cover come from the expired lot');
      final afterOverride = await detailOf(t, vid);
      expect({for (final l in afterOverride.lots) l.lotNumber: l.remaining}['LOT-OLD'], 2, reason: 'LOT-OLD fell from 4 to 2');
      expect(afterOverride.row.expiredUnits, 2);
      expect(afterOverride.row.stock, afterSix.row.stock - 4);
      final audit = await owner.get('/api/pos/audit-logs/$storeId?action=expired_lot_sold&limit=5');
      expect('${audit.data}', contains('expired_lot_sold'), reason: 'the audit event exists');
      print('b2 ok: expired lot sold with the manager token; audit present');
      await t.closeAnyOpenShift();
      await t.dispose();

      // ── c · store credit + cash ──────────────────────────────────────────────────────────────────────────────────────────────────
      t = await till(managerEmail, managerPin);
      await app(tester);
      final session3 = await t.openShift(openingCash: 100);
      c = await home(tester, t, session3.id);
      final latte = await findProduct(c, 'Latte');
      await owner.topUp(storeId, latte.variant.variantId, await t.stockOf('DEV-LATTE'), 100);
      c.addToCart(latte.product, latte.variant);
      c.cartItems.single.quantity.value = 3; // 15.00 + 10% = 16.50
      c.cartItems.refresh();
      final cust = (await t.repo.searchPosCustomers(storeId, _creditPhone))!;
      c.attachCustomer(cust.items.firstWhere((x) => x.id == creditCustomerId), cust.cur);
      await c.saleCustomer.refresh();
      expect(c.storeCreditOffered, isTrue);
      c.useStoreCredit();
      expect(c.splitLines.single.amount.text, '16.50', reason: 'the default is min(balance, amount due)');
      c.splitLines.single.amount.text = '10.00';
      c.addSplitLine();
      c.splitLines.last.amount.text = '6.50';
      expect(c.canCharge, isTrue);
      await c.completeSale();
      sold = c.lastSale.value;
      expect(sold, isNotNull, reason: 'credit + cash sale');
      expect(sold!.payments.map((p) => '${p.method}:${p.amount}'), ['store_credit:10.0', 'cash:6.5']);
      expectedCredit -= 1000;
      final afterC = await profileOf(t, creditCustomerId);
      expect(afterC.creditBalanceMinor, expectedCredit, reason: 'the balance dropped by exactly 10.00');
      points += sold.loyalty?.earnedPoints ?? 0;
      expect(afterC.loyaltyPoints, points, reason: 'earned points are added');
      print('c ok: balance ${afterC.creditBalanceMinor}, points ${afterC.loyaltyPoints} (earned ${sold.loyalty?.earnedPoints})');

      // ── d · redeem points ────────────────────────────────────────────────────────────────────────────────────────────────────────
      c.addToCart(latte.product, latte.variant);
      c.cartItems.single.quantity.value = 4; // 20.00
      c.cartItems.refresh();
      c.attachCustomer(cust.items.firstWhere((x) => x.id == creditCustomerId), cust.cur);
      await c.saleCustomer.refresh();
      expect(c.saleCustomer.pointsEnabled, isTrue);
      c.setRedeemPoints(10); // 10 x 0.50 = 5.00 off: (20.00 - 5.00) + 10% tax = 16.50
      expect(c.redeemValueMajor, 5.0);
      expect(c.total, 16.5);
      c.selectedPayment.value = PosPaymentMethod.card;
      await c.completeSale();
      final redeemSale = c.lastSale.value;
      expect(redeemSale, isNotNull, reason: 'the redeem sale went through');
      expect(redeemSale!.discount, 5.0, reason: 'the server priced the redemption');
      expect(redeemSale.total, 16.5);
      expect(redeemSale.loyalty!.redeemedPoints, 10);
      points = points - 10 + redeemSale.loyalty!.earnedPoints;
      final afterD = await profileOf(t, creditCustomerId);
      expect(afterD.loyaltyPoints, points, reason: 'points fell by 10 and the earned ones were added');
      expect(afterD.creditBalanceMinor, expectedCredit);
      print('d ok: discount ${redeemSale.discount}, total ${redeemSale.total}, points ${afterD.loyaltyPoints}');
      await t.closeAnyOpenShift();
      await t.dispose();

      // ── e · return to store credit as a cashier: within the limit alone, above a lowered limit with a manager's PIN ─────────────────
      final patched = await owner.patch('/api/pos/settings/$storeId', {'cashierReturnsEnabled': true, 'returnApprovalAboveMinor': 100000, 'returnApprovalAfterDays': 30});
      expect(patched.statusCode, anyOf(200, 201), reason: '${patched.data}');
      await setLimit(100000); // 1000.00: a credit refund is within it
      t = await till(cashierEmail, cashierPin);
      await app(tester);
      await t.openShift(openingCash: 50);
      final r1 = PosReturnController(repository: t.repo, saleId: redeemSale.id);
      Get.put(r1, tag: 'r1');
      await r1.load();
      await eventually(() async => r1.creditLedgerOn.value, reason: 'the ledger is on for the sale\'s customer');
      expect(r1.canChooseRefundTo, isTrue);
      r1.setQty(r1.sale.value!.items.single.saleItemId!, 1);
      r1.setRefundTo('store_credit');
      final est1 = r1.estimateMinor!;
      expect(await r1.confirm(), isTrue, reason: r1.error.value ?? '');
      final back1 = Money1.minor(r1.resultAmount);
      expect(back1, est1, reason: 'the till\'s estimate equals what the server credited');
      expect(r1.resultCreditText.value, isNotNull, reason: 'Refunded to store credit ...');
      expectedCredit += back1;
      expect(r1.resultBalanceText.value, isNotNull);
      final n1 = (await t.repo.getSaleDocuments(redeemSale.id))!.creditNotes.single;
      expect(n1.approvedBy, isNull, reason: 'within the limit: no manager');
      expect(n1.tenders.map((x) => x.method), contains('store_credit'));
      expect((await profileOf(t, creditCustomerId)).creditBalanceMinor, expectedCredit);
      print('e1 ok: refunded $back1 minor to credit alone; balance $expectedCredit');

      await setLimit(100); // 1.00: the next credit refund is above it
      final r2 = PosReturnController(repository: t.repo, saleId: redeemSale.id);
      Get.put(r2, tag: 'r2');
      await r2.load();
      await eventually(() async => r2.creditLedgerOn.value, reason: 'ledger flag');
      r2.setQty(r2.sale.value!.items.single.saleItemId!, 1);
      r2.setRefundTo('store_credit');
      final done = r2.confirm();
      await pumpFor(tester, const Duration(seconds: 3));
      expect(find.byKey(const Key('approverEmail')), findsOneWidget, reason: 'the manager approval sheet');
      expect(find.textContaining('store credit is above the limit'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('approverEmail')), managerEmail);
      for (final d in managerPin.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await pumpFor(tester, const Duration(seconds: 3));
      expect(await done, isTrue, reason: r2.error.value ?? '');
      final back2 = Money1.minor(r2.resultAmount);
      expectedCredit += back2;
      final notes = (await t.repo.getSaleDocuments(redeemSale.id))!.creditNotes;
      expect(notes.last.approvedBy, isNotNull);
      expect(notes.last.approvalReasons, contains('store_credit_refund_above_limit'));
      expect((await profileOf(t, creditCustomerId)).creditBalanceMinor, expectedCredit, reason: 'f: the balance reflects every step');
      print('e2 ok: refunded $back2 minor with the manager\'s PIN; balance $expectedCredit');
      await t.closeAnyOpenShift();
      await t.dispose();
      t = null;
    } finally {
      // ── cleanup: policy, limit, shifts, credit back to where it started ──────────────────────────────────────────────────────────
      await setLimit(limitBefore);
      await owner.patch('/api/pos/settings/$storeId', {'cashierReturnsEnabled': false, 'returnApprovalAboveMinor': null, 'returnApprovalAfterDays': null});
      try {
        final m = await till(managerEmail, managerPin);
        await m.closeAnyOpenShift();
        if (creditBaseline != null && creditCustomerId != null) {
          final now = (await m.repo.getCustomerProfile(storeId, creditCustomerId))!.creditBalanceMinor!;
          if (now != creditBaseline) {
            final r = await m.repo.adjustCustomerCredit(storeId, creditCustomerId, amountMinor: creditBaseline - now, note: 'e2e cleanup');
            print('credit restored by ${creditBaseline - now}: ${r.success} ${r.code ?? ''}');
          }
        }
        await m.dispose();
      } catch (e) {
        print('cleanup problem: $e');
      }
      await t?.dispose();
    }
  });
}

/// A refund amount in major units back to minor (USD: two decimals).
abstract final class Money1 {
  static int minor(double major) => (major * 100).round();
}
