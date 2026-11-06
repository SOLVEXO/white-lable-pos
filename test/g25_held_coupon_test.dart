// A held sale keeps its coupon CODE (not a reservation). On resume the code is checked again with the server; if it is no longer valid it
// is removed with a clear message that includes the new total — before anything is charged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/sale_harness.dart';

PosSaleModel heldSale({String? code}) => PosSaleModel.fromJson({
      '_id': 'held-1',
      'saleNumber': 'H-1',
      'storeId': 'store-1',
      'status': 'held',
      'currency': 'USD',
      'currencyExponent': 2,
      'subtotal': 20.0,
      'total': 20.0,
      'paymentMethod': 'cash',
      'customerName': 'Walk-in',
      'createdAt': '2026-11-06T10:00:00.000Z',
      if (code != null) 'heldCouponCode': code,
      'items': [
        {'_id': 'i1', 'productId': 'a', 'variantId': 'a_v1', 'name': 'Product a', 'sku': 'SKU-a', 'qty': 2, 'price': 10.0, 'lineTotal': 20.0}
      ],
    });

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  late PosHomeController c;
  setUp(() {
    h = SaleHarness();
    h.putController(taxRate: 0.1);
    c = h.c;
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'r';
    c.employeeId.value = 'e';
    when(() => h.repo.lastErrorCode).thenReturn(null);
  });
  tearDown(Get.reset);

  const applied = PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
  void stubCouponQuote(({PosQuote? quote, String? message, String? code}) Function() f) {
    when(() => h.repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion'), couponCode: any(named: 'couponCode'))).thenAnswer((_) async => f());
  }

  Future<void> pumpApp(WidgetTester t) => t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));

  testWidgets('holding a sale with a coupon sends the CODE and the total WITHOUT the coupon (the server prices a held sale without it)', (t) async {
    await pumpApp(t);
    h.addLine(h.products[0], qty: 2);
    c.appliedCoupon.value = applied;
    c.settings.value = null;
    List<Map<Symbol, dynamic>> calls = [];
    when(
      () => h.repo.createSale(
        storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'), items: any(named: 'items'),
        discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'), settingsVersion: any(named: 'settingsVersion'),
        clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'), payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'),
        paymentReference: any(named: 'paymentReference'), customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'),
        status: any(named: 'status'), idempotencyKey: any(named: 'idempotencyKey'), couponCode: any(named: 'couponCode'), approverToken: any(named: 'approverToken'),
      ),
    ).thenAnswer((inv) async {
      calls.add(Map.of(inv.namedArguments));
      return (success: true, sale: sale(status: 'held'), message: null, queued: false);
    });
    await c.holdSale();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 4));
    }
    final call = calls.single;
    expect(call[#status], 'held');
    expect(call[#couponCode], 'SAVE10');
    expect(call[#discountType], isNull);
    expect(call[#clientTotal], 20.0); // 2 × 10.00, tax rate unknown here: the point is "no coupon discount in it"
  });

  testWidgets('RESUME with a code that still works: it is applied again (live check) and nothing is said', (t) async {
    await pumpApp(t);
    stubCouponQuote(() => (quote: PosQuote(subtotal: 20, discount: 2, tax: 1.8, total: 19.8, taxRate: 0.1, currency: 'USD', currencyExponent: 2, settingsVersion: 1, coupon: applied), message: null, code: null));
    c.resumeHeldSale(heldSale(code: 'SAVE10'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 1));
    expect(c.appliedCoupon.value?.code, 'SAVE10');
    expect(c.heldCouponNotice.value, isNull);
    expect(c.itemCount, 2);
  });

  testWidgets('RESUME with a code that is no longer valid: removed, with the reason AND the new total, before charging', (t) async {
    await pumpApp(t);
    stubCouponQuote(() => (quote: null, message: 'This coupon has expired', code: 'COUPON_EXPIRED'));
    c.resumeHeldSale(heldSale(code: 'SAVE10'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 4));
    expect(c.appliedCoupon.value, isNull);
    final msg = c.heldCouponNotice.value!;
    expect(msg, contains('SAVE10'));
    expect(msg, contains('expired'));
    expect(msg, contains(Money.format(c.total)));
    expect(c.hasItems, isTrue); // the cart is intact: the sale can still be charged at the full price
  });

  testWidgets('the notice is shown in the cart (with a dismiss) so the cashier sees it before charging', (t) async {
    t.view.physicalSize = const Size(1180, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    stubCouponQuote(() => (quote: null, message: 'This coupon has reached its limit', code: 'COUPON_LIMIT_REACHED'));
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: CartPanel(c: c)))));
    c.resumeHeldSale(heldSale(code: 'SAVE10'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 4));
    expect(find.byKey(const Key('heldCouponNotice')), findsOneWidget);
    expect(find.textContaining('reached its limit'), findsOneWidget);
    await t.tap(find.byKey(const Key('heldCouponNoticeDismiss')));
    await t.pump();
    expect(find.byKey(const Key('heldCouponNotice')), findsNothing);
  });

  testWidgets('a held sale WITHOUT a code resumes as before (no check, no notice)', (t) async {
    await pumpApp(t);
    c.resumeHeldSale(heldSale());
    await t.pump(const Duration(milliseconds: 100));
    expect(c.appliedCoupon.value, isNull);
    expect(c.heldCouponNotice.value, isNull);
    verifyNever(() => h.repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion'), couponCode: any(named: 'couponCode')));
  });
}
