// G2.4 acceptance targets (the blueprint's numbers), as tests:
//   * add to cart in ≤ 2 taps from the sell screen
//   * a barcode scan puts the line in the cart, with haptic + sound feedback, in < 300 ms (the iOS-simulator figure is measured
//     separately by integration_test/g24_checkout_flow_test.dart; this is the same code path on the host)
//   * double-submit protection on Charge and refund (coupon apply / custom item are in g24_custom_coupon_test.dart)
//   * a sale in progress is restored after the app is killed and restarted
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_grid.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/sale_harness.dart';

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  setUp(() => h = SaleHarness());
  tearDown(() => ReasonPicker.testOverride = null);

  group('add to cart in ≤ 2 taps', () {
    testWidgets('a single-variant product: ONE tap', (t) async {
      await h.mount(t);
      var taps = 0;
      await t.tap(find.descendant(of: find.byType(ProductGrid), matching: find.text('Product a')));
      taps++;
      await h.settle(t);
      expect(h.c.itemCount, 1);
      expect(taps, lessThanOrEqualTo(2));
    });

    testWidgets('a product with variants: TWO taps (the tile, then the variant)', (t) async {
      h.products = [multiVariant('m')];
      await h.mount(t);
      var taps = 0;
      await t.tap(find.descendant(of: find.byType(ProductGrid), matching: find.text('Shirt m')));
      taps++;
      await h.settle(t);
      await t.tap(find.text(Money.format(22)).last);
      taps++;
      await h.settle(t);
      expect(h.c.cartItems.single.variant!.variantId, 'm_m');
      expect(taps, lessThanOrEqualTo(2));
    });
  });

  group('barcode scan feedback < 300 ms', () {
    PosProductModel withBarcode() => PosProductModel(
          productId: 'pb',
          name: 'Scanned tea',
          type: 'physical',
          categoryId: 'c1',
          variants: const [PosProductVariant(variantId: 'pb_v1', sku: 'TEA', barcode: '8964000012345', price: 3, stock: 10, isDefault: true)],
        );

    testWidgets('a code in the on-device catalogue: line added at once (no network), haptic + sound, measured under 300 ms', (t) async {
      h.products = [withBarcode()];
      await h.mount(t);
      final platformCalls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add('${call.method}:${call.arguments}');
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final watch = Stopwatch()..start();
      await h.c.addProductByBarcode('8964000012345');
      watch.stop();
      expect(h.c.cartItems.single.product.productId, 'pb');
      expect(h.c.lastScanMs, isNotNull);
      expect(h.c.lastScanMs!, lessThan(300));
      expect(watch.elapsedMilliseconds, lessThan(300));
      expect(platformCalls.any((c) => c.startsWith('HapticFeedback.vibrate')), isTrue, reason: 'haptic');
      expect(platformCalls.any((c) => c.startsWith('SystemSound.play')), isTrue, reason: 'sound');
      verifyNever(() => h.repo.getProductByBarcode(storeId: any(named: 'storeId'), barcode: any(named: 'barcode'))); // no server round trip
      await t.pump(const Duration(seconds: 1)); // lets the cart's save timer finish
    });

    testWidgets('a code that is not in the catalogue on the device still asks the server and gives the same feedback', (t) async {
      await h.mount(t);
      when(() => h.repo.getProductByBarcode(storeId: any(named: 'storeId'), barcode: any(named: 'barcode'))).thenAnswer((_) async => withBarcode());
      await h.c.addProductByBarcode('8964000012345');
      expect(h.c.cartItems.single.product.productId, 'pb');
      expect(h.c.lastScanMs, isNotNull);
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('double-submit protection', () {
    testWidgets('Charge pressed twice while the first is in flight sends ONE sale', (t) async {
      h.putController();
      final c = h.c;
      c.storeId.value = 'store-1';
      c.sessionId.value = 'session-1';
      c.registerId.value = 'r';
      c.employeeId.value = 'e';
      c.selectedPayment.value = PosPaymentMethod.card;
      h.addLine(h.products[0]);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));
      final gate = Completer<SaleResult>();
      h.stubCreateSale((_) => gate.future);
      final first = c.completeSale();
      await t.pump();
      final second = c.completeSale(); // the second tap
      await t.pump();
      gate.complete((success: true, sale: sale(total: 10), message: null, queued: false));
      await first;
      await second;
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 4));
      }
      h.verifyCreateSale(times: 1); // (verify() asserts at least one; the count is checked next)
      expect(h.calls, hasLength(1));
    });

    testWidgets('Hold pressed twice sends ONE held sale', (t) async {
      h.putController();
      final c = h.c;
      c.storeId.value = 'store-1';
      c.sessionId.value = 'session-1';
      c.registerId.value = 'r';
      c.employeeId.value = 'e';
      h.addLine(h.products[0]);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));
      final gate = Completer<SaleResult>();
      h.stubCreateSale((_) => gate.future);
      final first = c.holdSale();
      await t.pump();
      final second = c.holdSale();
      gate.complete((success: true, sale: sale(status: 'held'), message: null, queued: false));
      await first;
      await second;
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 4));
      }
      expect(h.calls, hasLength(1));
    });

    testWidgets('Refund pressed twice sends ONE refund (the reason picker counts as "in flight")', (t) async {
      final repo = MockPosRepository();
      final c = PosReturnController(repository: repo, saleId: 'sale-1');
      c.sale.value = PosSaleModel(
        id: 'sale-1',
        saleNumber: 'S-1',
        storeId: 'store-1',
        sessionId: 's',
        registerId: 'r',
        employeeId: 'e',
        items: const [PosSaleItemModel(saleItemId: 'i1', productId: 'p', name: 'W', qty: 1, price: 10, lineTotal: 10)],
        discount: 0,
        tax: 0,
        subtotal: 10,
        total: 10,
        paymentMethod: 'cash',
        customerName: 'Walk-in',
        notes: '',
        status: 'completed',
        createdAt: DateTime(2026, 1, 1),
      );
      when(() => repo.getSaleById(any())).thenAnswer((_) async => c.sale.value);
      when(() => repo.getPosSettings(any())).thenAnswer((_) async => null);
      final picker = Completer<PosReasonChoice?>();
      ReasonPicker.testOverride = (_) => picker.future; // the cashier is still choosing a reason
      final gate = Completer<({bool success, double? refundedAmount, String? newStatus, String? message, List<PosPaymentLine> tenders})>();
      when(() => repo.refundSale(any(), items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).thenAnswer((_) => gate.future);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(home: const Scaffold(body: SizedBox.shrink()))));
      final first = c.confirm(all: true);
      await t.pump();
      final second = c.confirm(all: true); // a second tap while the picker is open
      picker.complete(const PosReasonChoice('price_error', ''));
      await t.pump();
      gate.complete((success: false, refundedAmount: null, newStatus: null, message: 'No', tenders: const <PosPaymentLine>[]));
      await first;
      await second;
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(seconds: 4));
      }
      verify(() => repo.refundSale('sale-1', items: null, reasonCode: 'price_error', reason: '', receiptPresented: null, approverToken: null)).called(1);
    });
  });

  group('a sale in progress is restored after an app kill', () {
    testWidgets('lines, quantities, discount, customer, payment choice and the checkout intent come back in a new controller', (t) async {
      await t.runAsync(() async {
        h.putController(manager: true);
        final c = h.c;
        c.storeId.value = 'store-1';
        c.sessionId.value = 'session-1';
        h.addLine(h.products[0], qty: 3);
        h.addLine(h.products[1]);
        c.discountController.text = '2';
        c.customerController.text = 'Ayesha';
        c.noteController.text = 'gift';
        c.selectedPayment.value = PosPaymentMethod.card;
        await c.persistNow();
        // --- the app is killed: a brand new controller starts from nothing ---
        final restarted = PosHomeController(posRepository: h.repo, categoryRepository: h.cats);
        restarted.storeId.value = 'store-1';
        restarted.sessionId.value = 'session-1';
        await restarted.restoreCart();
        expect(restarted.cartItems.map((i) => (i.product.productId, i.quantity.value)).toList(), [('a', 3), ('b', 1)]);
        expect(restarted.discountController.text, '2');
        expect(restarted.customerController.text, 'Ayesha');
        expect(restarted.noteController.text, 'gift');
        expect(restarted.selectedPayment.value, PosPaymentMethod.card);
        expect(restarted.total, c.total);
      });
    });

    testWidgets('a different register session does NOT inherit the old cart', (t) async {
      await t.runAsync(() async {
        h.putController();
        h.c.storeId.value = 'store-1';
        h.c.sessionId.value = 'session-1';
        h.addLine(h.products[0]);
        await h.c.persistNow();
        final other = PosHomeController(posRepository: h.repo, categoryRepository: h.cats);
        other.storeId.value = 'store-1';
        other.sessionId.value = 'session-2';
        await other.restoreCart();
        expect(other.cartItems, isEmpty);
      });
    });
  });
}
