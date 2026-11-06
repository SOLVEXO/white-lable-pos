// G2.4 — custom item, coupon and manager approval on the sale path (controller + sheets).
// What the server decides (the approval limit, the coupon rules) is NOT re-implemented here: these tests check that the till sends the
// right things, reacts to the server's refusals, and cannot be double-submitted.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'support/sale_harness.dart';

PosQuote quote({double subtotal = 20, double discount = 0, double tax = 0, PosAppliedCoupon? coupon}) => PosQuote(
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: subtotal - discount + tax,
      taxRate: 0,
      currency: 'PKR',
      currencyExponent: 2,
      settingsVersion: 1,
      coupon: coupon,
    );

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  late PosHomeController c;

  PosEmployeeModel employee(String role) => PosEmployeeModel(id: 'm1', storeId: 'store-1', sellerId: 's', name: 'Mia', email: 'mia@x.pk', role: role, shiftIds: const [], status: 'active', createdAt: DateTime(2026));

  setUp(() {
    h = SaleHarness();
    h.putController(taxRate: 0.1);
    c = h.c;
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'r';
    c.employeeId.value = 'e';
    c.selectedPayment.value = PosPaymentMethod.card;
    when(() => h.repo.lastErrorCode).thenReturn(null);
  });
  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester t) => t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  // createSale stubs that include the two G2.4 named arguments (a plain sale is the long-standing call, see SaleHarness)
  void stubG24CreateSale(Future<SaleResult> Function(Invocation) f) {
    when(
      () => h.repo.createSale(
        storeId: any(named: 'storeId'),
        sessionId: any(named: 'sessionId'),
        registerId: any(named: 'registerId'),
        employeeId: any(named: 'employeeId'),
        items: any(named: 'items'),
        discountType: any(named: 'discountType'),
        discountValue: any(named: 'discountValue'),
        clientTotal: any(named: 'clientTotal'),
        settingsVersion: any(named: 'settingsVersion'),
        clientCreatedAt: any(named: 'clientCreatedAt'),
        paymentMethod: any(named: 'paymentMethod'),
        payments: any(named: 'payments'),
        amountTendered: any(named: 'amountTendered'),
        paymentReference: any(named: 'paymentReference'),
        customerName: any(named: 'customerName'),
        customerId: any(named: 'customerId'),
        notes: any(named: 'notes'),
        status: any(named: 'status'),
        idempotencyKey: any(named: 'idempotencyKey'),
        couponCode: any(named: 'couponCode'),
        approverToken: any(named: 'approverToken'),
      ),
    ).thenAnswer((inv) {
      h.calls.add(Map.of(inv.namedArguments));
      return f(inv);
    });
  }

  void stubCouponQuote(({PosQuote? quote, String? message, String? code}) Function(String? code) f) {
    when(
      () => h.repo.quoteSale(
        storeId: any(named: 'storeId'),
        items: any(named: 'items'),
        discountType: any(named: 'discountType'),
        discountValue: any(named: 'discountValue'),
        settingsVersion: any(named: 'settingsVersion'),
        couponCode: any(named: 'couponCode'),
      ),
    ).thenAnswer((inv) async => f(inv.namedArguments[#couponCode] as String?));
  }

  group('custom item', () {
    test('is added as its own line: name, price, quantity, tax category — with no catalogue product', () {
      expect(c.addCustomItem(name: ' Gift wrap ', price: 4.5, qty: 2, taxCategory: 'exempt', note: 'red'), isTrue);
      final i = c.cartItems.single;
      expect(i.isCustom, isTrue);
      expect(i.product.name, 'Gift wrap');
      expect(i.lineTotal, 9);
      expect(i.taxCategory, 'exempt');
      expect(c.hasCustomItems, isTrue);
    });

    test('a nameless, free or zero-quantity item is refused', () {
      expect(c.addCustomItem(name: '  ', price: 5), isFalse);
      expect(c.addCustomItem(name: 'x', price: 0), isFalse);
      expect(c.addCustomItem(name: 'x', price: 5, qty: 0), isFalse);
      expect(c.cartItems, isEmpty);
    });

    test('a double tap on Add is ONE line (the guard is released on the next microtask)', () async {
      expect(c.addCustomItem(name: 'Service', price: 10), isTrue);
      expect(c.addCustomItem(name: 'Service', price: 10), isFalse); // same frame
      await Future<void>.delayed(Duration.zero);
      expect(c.cartItems, hasLength(1));
    });

    test('a tax-exempt custom item is left out of the tax base; a standard one is taxed (10% store rate)', () {
      c.settings.value = const PosSettingsModel(storeId: 'store-1', taxRate: 0.1);
      c.addCustomItem(name: 'Exempt', price: 10, taxCategory: 'exempt');
      expect(c.totals.tax, 0);
      c.isAddingCustomItem.value = false; // (the double-tap guard is released a microtask later)
      c.addCustomItem(name: 'Taxed', price: 10);
      expect(c.totals.tax, 1); // only the second line
      expect(c.totals.total, 21);
    });

    testWidgets('is sent as isCustom / customName / taxCategory / unitPrice / qty — no productId, no variantId', (t) async {
      await pumpApp(t);
      c.addCustomItem(name: 'Gift wrap', price: 4.5, qty: 2, taxCategory: 'exempt', note: 'red');
      // no coupon and no approver: the ordinary createSale call
      h.stubCreateSale((_) async => (success: true, sale: sale(total: 9), message: null, queued: false));
      await c.completeSale();
      await settle(t);
      final items = h.calls.single[#items] as List<Map<String, dynamic>>;
      expect(items.single, {'isCustom': true, 'customName': 'Gift wrap', 'taxCategory': 'exempt', 'customNote': 'red', 'qty': 2, 'unitPrice': 4.5});
    });

    testWidgets('survives an app kill: saved with the cart and restored with its tax category and note', (t) async {
      await t.runAsync(() async {
        c.addCustomItem(name: 'Repair', price: 12, taxCategory: 'exempt', note: 'screen');
        await c.persistNow();
        final c2 = PosHomeController(posRepository: h.repo, categoryRepository: h.cats);
        c2.storeId.value = 'store-1';
        c2.sessionId.value = 'session-1';
        await c2.restoreCart();
        final i = c2.cartItems.single;
        expect([i.isCustom, i.product.name, i.unitPrice, i.taxCategory, i.customNote], [true, 'Repair', 12.0, 'exempt', 'screen']);
      });
    });
  });

  group('manager approval (the server decides when it is needed)', () {
    testWidgets('CUSTOM_ITEM_NEEDS_MANAGER → manager PIN sheet → the sale is sent again with THAT manager\'s token', (t) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpApp(t);
      SharedPreferences.setMockInitialValues({'store_id': 'store-1'});
      c.addCustomItem(name: 'Big job', price: 500);
      var attempts = 0;
      when(() => h.repo.lastErrorCode).thenAnswer((_) => attempts == 1 ? 'CUSTOM_ITEM_NEEDS_MANAGER' : null);
      when(() => h.repo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
          .thenAnswer((_) async => (success: true, employee: employee('manager'), activeSession: null, employeeToken: 'mgr-token', message: null));
      stubG24CreateSale((inv) async {
        attempts++;
        // the first try carries no approver and is refused; the second carries the manager's token and is accepted
        if (inv.namedArguments[#approverToken] == null) return (success: false, sale: null, message: 'A manager must approve this custom item', queued: false);
        return (success: true, sale: sale(total: 550), message: null, queued: false);
      });
      final done = c.completeSale();
      await settle(t);
      expect(find.byKey(const Key('approverEmail')), findsOneWidget);
      await t.enterText(find.byKey(const Key('approverEmail')), 'mia@x.pk');
      for (final d in ['1', '2', '3', '4']) {
        await t.tap(find.text(d).last);
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 300));
      await done;
      await settle(t);
      expect(h.calls, hasLength(2));
      expect(h.calls.first[#approverToken], isNull); // the first try: the cashier's own session
      expect(h.calls.last[#approverToken], 'mgr-token');
      expect(c.lastOutcome.value, SaleOutcome.completed);
    });

    testWidgets('a PIN that belongs to a CASHIER is refused ("not a manager") and no token is used', (t) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pumpApp(t);
      SharedPreferences.setMockInitialValues({'store_id': 'store-1'});
      c.addCustomItem(name: 'Big job', price: 500);
      when(() => h.repo.lastErrorCode).thenReturn('CUSTOM_ITEM_NEEDS_MANAGER');
      when(() => h.repo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
          .thenAnswer((_) async => (success: true, employee: employee('cashier'), activeSession: null, employeeToken: 'cashier-token', message: null));
      h.stubCreateSale((_) async => (success: false, sale: null, message: 'A manager must approve this custom item', queued: false));
      final done = c.completeSale();
      await settle(t);
      await t.enterText(find.byKey(const Key('approverEmail')), 'mia@x.pk');
      for (final d in ['1', '2', '3', '4']) {
        await t.tap(find.text(d).last);
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('That person is not a manager.'), findsOneWidget);
      await t.tap(find.byKey(const Key('approverCancel')));
      await settle(t);
      await done;
      expect(c.lastOutcome.value, isNull);
      expect(c.hasItems, isTrue); // nothing was sold
    });
  });

  group('coupon', () {
    setUp(() {
      c.settings.value = const PosSettingsModel(storeId: 'store-1', taxRate: 0.1); // the till's own figures must equal the quote's (no "Total updated" dialog)
      c.addCustomItem(name: 'Thing', price: 20);
    });

    test('apply: the server accepts it, the code shows, and the discount reaches the totals', () async {
      stubCouponQuote((code) => (quote: quote(discount: 2, coupon: PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10)), message: null, code: null));
      expect(await c.applyCoupon('save10'), isNull);
      expect(c.appliedCoupon.value!.code, 'SAVE10');
      expect(c.totals.discount, 2);
    });

    test('a refused code shows the server\'s reason and applies nothing', () async {
      stubCouponQuote((_) => (quote: null, message: 'This coupon has expired', code: 'COUPON_EXPIRED'));
      expect(await c.applyCoupon('OLD'), 'This coupon has expired');
      expect(c.appliedCoupon.value, isNull);
    });

    test('double submit: two taps on Apply are ONE check', () async {
      final gate = Completer<({PosQuote? quote, String? message, String? code})>();
      var calls = 0;
      when(
        () => h.repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion'), couponCode: any(named: 'couponCode')),
      ).thenAnswer((_) {
        calls++;
        return gate.future;
      });
      final first = c.applyCoupon('SAVE10');
      final second = c.applyCoupon('SAVE10');
      expect(c.isApplyingCoupon.value, isTrue);
      gate.complete((quote: quote(discount: 2, coupon: PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10)), message: null, code: null));
      await first;
      expect(await second, isNull);
      expect(calls, 1);
      expect(c.isApplyingCoupon.value, isFalse);
    });

    test('cannot be combined with a manual discount (either order)', () async {
      c.discountController.text = '5';
      expect(await c.applyCoupon('SAVE10'), contains('Remove the discount first'));
      verifyNever(() => h.repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion'), couponCode: any(named: 'couponCode')));
    });

    test('an empty cart cannot take a coupon', () async {
      c.cartItems.clear();
      expect(await c.applyCoupon('SAVE10'), 'Add items before applying a coupon');
    });

    testWidgets('Charge sends couponCode and NO manual discount; the coupon is gone after the sale', (t) async {
      await pumpApp(t);
      c.appliedCoupon.value = PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
      stubCouponQuote((_) => (quote: quote(discount: 2, tax: 1.8, coupon: PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10)), message: null, code: null));
      stubG24CreateSale((_) async => (success: true, sale: sale(total: 19.8), message: null, queued: false));
      await c.completeSale();
      await settle(t);
      final call = h.calls.single;
      expect(call[#couponCode], 'SAVE10');
      expect(call[#discountType], isNull);
      expect(call[#discountValue], isNull);
      expect(c.appliedCoupon.value, isNull);
    });

    testWidgets('a coupon the server now refuses at Charge (expired / min spend) is dropped with its reason and nothing is sold', (t) async {
      await pumpApp(t);
      c.appliedCoupon.value = PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
      stubCouponQuote((_) => (quote: null, message: 'The sale is below this coupon\'s minimum spend', code: 'COUPON_MIN_SPEND'));
      await c.completeSale();
      await settle(t);
      expect(c.appliedCoupon.value, isNull);
      expect(c.hasItems, isTrue);
      expect(c.lastOutcome.value, isNull);
      expect(h.calls, isEmpty);
    });

    testWidgets('survives an app kill: the applied coupon is saved with the cart', (t) async {
      await t.runAsync(() async {
        c.appliedCoupon.value = PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
        await c.persistNow();
        final c2 = PosHomeController(posRepository: h.repo, categoryRepository: h.cats);
        c2.storeId.value = 'store-1';
        c2.sessionId.value = 'session-1';
        await c2.restoreCart();
        expect(c2.appliedCoupon.value!.code, 'SAVE10');
      });
    });
  });
}
