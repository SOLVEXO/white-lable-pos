// Held sales (list / resume / complete / discard), barcode add (manual entry, camera path, keyboard-wedge detector),
// and the customer picker sheet — the Phase 3 surfaces that had no tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/customer_repository.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/controllers/pos_held_sales_controller.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/views/pos_held_sales_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/hid_scan_detector.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_barcode_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_customer_picker_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/sale_harness.dart';

class MockCustomerRepository extends Mock implements CustomerRepository {}

PosSaleModel held(
  String id, {
  double total = 12.5,
  String customer = 'Walk-in',
  int lines = 2,
}) => PosSaleModel(
  id: id,
  saleNumber: 'H-$id',
  storeId: 'store-1',
  sessionId: 'session-1',
  registerId: 'r',
  employeeId: 'e',
  items: [
    for (var i = 0; i < lines; i++)
      PosSaleItemModel(
        saleItemId: '$id-$i',
        productId: 'p$i',
        name: 'Item $i',
        sku: 'S$i',
        price: 2.5,
        qty: i + 1,
        lineTotal: 2.5 * (i + 1),
      ),
  ],
  discount: 0,
  tax: 0,
  subtotal: total,
  total: total,
  paymentMethod: 'cash',
  customerName: customer,
  notes: id == 'n' ? 'for pickup' : '',
  status: 'held',
  createdAt: DateTime(2026, 11, 2, 10, 30),
);

void main() {
  SaleHarness.setUpAllShared();

  // ── held sales ───────────────────────────────────────────────────────────────────────────────────────────────
  group('held sales', () {
    late MockPosRepository repo;
    late PosHeldSalesController c;

    setUp(() {
      SoundUtil.enabled = false;
      SharedPreferences.setMockInitialValues({
        'pos_sound_effects': false,
        'store_id': 'store-1',
        'pos_session_id': 'session-1',
      });
      repo = MockPosRepository();
      c = PosHeldSalesController(posRepository: repo);
    });

    Future<void> pump(
      WidgetTester t, {
      Size size = const Size(390, 844),
      ThemeData? theme,
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      addTearDown(Get.reset);
      Get.put<PosHeldSalesController>(c);
      await t.pumpWidget(
        GetMaterialApp(
          theme: theme ?? AppTheme.light,
          home: PosHeldSalesView(),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    void stubList(List<PosSaleModel> sales) => when(
      () => repo.getHeldSales(
        storeId: any(named: 'storeId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async => sales);

    testWidgets(
      'lists the held sales of this session (customer, date, total, first lines, payment, note, Held badge)',
      (t) async {
        stubList([held('a', customer: 'Ada Lovelace'), held('n', lines: 5)]);
        await pump(t);
        expect(find.text('Ada Lovelace'), findsOneWidget);
        expect(find.text('Walk-in customer'), findsOneWidget);
        expect(find.text('Held'), findsNWidgets(2));
        expect(find.text('+2 more items'), findsOneWidget);
        expect(find.text('for pickup'), findsOneWidget);
        expect(
          find.text('Cash'),
          findsNWidgets(2),
        ); // the stored payment method, capitalised
        expect(
          t.widget<AmountText>(find.byType(AmountText).first).text,
          Money.format(12.5),
        );
        verify(
          () => repo.getHeldSales(storeId: 'store-1', sessionId: 'session-1'),
        ).called(1);
      },
    );

    testWidgets(
      'loading shows a skeleton; empty shows "No Held Sales" with Refresh that reloads',
      (t) async {
        final gate = Completer<List<PosSaleModel>>();
        when(
          () => repo.getHeldSales(
            storeId: any(named: 'storeId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenAnswer((_) => gate.future);
        await pump(t);
        expect(find.byType(SkeletonBox), findsWidgets);
        gate.complete([]);
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('No Held Sales'), findsOneWidget);
        stubList([held('a')]);
        await t.tap(find.text('Refresh').last);
        await t.pump(const Duration(milliseconds: 200));
        expect(find.text('No Held Sales'), findsNothing);
        expect(c.heldSales.length, 1);
      },
    );

    testWidgets(
      'a failed load keeps the screen usable (toast, empty state with Refresh)',
      (t) async {
        stubList([]);
        await pump(t);
        when(
          () => repo.getHeldSales(
            storeId: any(named: 'storeId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(Exception('boom'));
        await c.loadHeldSales();
        await t.pump(const Duration(milliseconds: 400));
        expect(c.isLoading.value, isFalse);
        expect(find.text('No Held Sales'), findsOneWidget);
        expect(find.text('Failed to load held sales.'), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'DISCARD asks first: Cancel keeps it; Discard calls discardSale and removes the tile',
      (t) async {
        stubList([held('a'), held('b')]);
        when(() => repo.discardSale('a')).thenAnswer((_) async => true);
        await pump(t);
        await t.tap(find.byKey(const Key('discard-a')));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Discard Sale'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pump(const Duration(milliseconds: 400));
        verifyNever(() => repo.discardSale(any()));
        expect(c.heldSales.length, 2);
        await t.tap(find.byKey(const Key('discard-a')));
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Discard').last);
        await t.pump(const Duration(milliseconds: 400));
        verify(() => repo.discardSale('a')).called(1);
        expect(c.heldSales.map((s) => s.id), ['b']);
        expect(c.processingId.value, '');
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('a failed discard keeps the sale', (t) async {
      stubList([held('a')]);
      when(() => repo.discardSale('a')).thenAnswer((_) async => false);
      await pump(t);
      await c.discardSale(c.heldSales.first);
      expect(c.heldSales.length, 1);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'COMPLETE: choose the payment method, then completeSale(saleId, paymentMethod) and the tile goes',
      (t) async {
        stubList([held('a', total: 12.5)]);
        when(
          () => repo.completeSale(
            saleId: any(named: 'saleId'),
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
          ),
        ).thenAnswer(
          (_) async =>
              (success: true, sale: held('a', total: 12.5), message: null),
        );
        await pump(t);
        await t.tap(find.byKey(const Key('complete-a')));
        await t.pump(); // the frame that starts the sheet animation
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Complete Sale'), findsWidgets);
        await t.tap(find.byKey(const Key('completeMethod-card')));
        await t.pump(const Duration(milliseconds: 100));
        await t.tap(find.byKey(const Key('completeSaleConfirm')));
        await t.pump(const Duration(milliseconds: 500));
        verify(
          () => repo.completeSale(
            saleId: 'a',
            paymentMethod: 'card',
            notes: any(named: 'notes'),
          ),
        ).called(1);
        expect(c.heldSales, isEmpty);
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'completing re-priced: the toast says what was actually charged; a refused completion keeps the sale',
      (t) async {
        stubList([held('a', total: 10), held('b', total: 10)]);
        when(
          () => repo.completeSale(
            saleId: 'a',
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
          ),
        ).thenAnswer(
          (_) async =>
              (success: true, sale: held('a', total: 10.8), message: null),
        );
        when(
          () => repo.completeSale(
            saleId: 'b',
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
          ),
        ).thenAnswer(
          (_) async =>
              (success: false, sale: null, message: 'Insufficient stock'),
        );
        await pump(t);
        await c.completeSale(c.heldSales.first);
        await t.pump(const Duration(milliseconds: 300));
        expect(
          find.textContaining('charged ${Money.format(10.8)}'),
          findsOneWidget,
        );
        await c.completeSale(c.heldSales.single);
        expect(c.heldSales.map((s) => s.id), [
          'b',
        ], reason: 'a refused completion keeps it');
        await t.pump(const Duration(seconds: 6));
      },
    );

    testWidgets(
      'RESUME puts the held sale back in the cart and leaves the screen',
      (t) async {
        final h = SaleHarness();
        stubList([held('a', customer: 'Ada', lines: 2)]);
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        addTearDown(Get.reset);
        h.putController(); // the POS controller that a resume feeds
        Get.put<PosHeldSalesController>(c);
        await t.pumpWidget(
          GetMaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Text('POS home')),
          ),
        );
        Get.to<void>(() => PosHeldSalesView());
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Held Sales'), findsOneWidget);
        await t.tap(find.byKey(const Key('resume-a')));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Held Sales'), findsNothing);
        expect(find.text('POS home'), findsOneWidget);
        expect(h.c.cartItems.length, 2);
        expect(h.c.customerController.text, 'Ada');
        await t.pump(const Duration(seconds: 2));
      },
    );

    for (final theme in {
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    }.entries) {
      for (final sz in {
        'phone': const Size(390, 844),
        'tablet landscape': const Size(1180, 820),
      }.entries) {
        testWidgets('renders ${theme.key} · ${sz.key}', (t) async {
          stubList([
            held('a', customer: 'Ada Lovelace'),
            held('n', lines: 5),
            held('c'),
          ]);
          await pump(t, size: sz.value, theme: theme.value);
          expect(t.takeException(), isNull);
          expect(find.text('Held'), findsNWidgets(3));
        });
      }
    }
  });

  // ── barcode ──────────────────────────────────────────────────────────────────────────────────────────────────
  group('barcode add', () {
    late SaleHarness h;
    setUp(() => h = SaleHarness());

    void stubBarcode(PosProductModel? p) => when(
      () => h.repo.getProductByBarcode(
        storeId: any(named: 'storeId'),
        barcode: any(named: 'barcode'),
      ),
    ).thenAnswer((_) async => p);

    testWidgets(
      'addProductByBarcode: found → added (default variant); the in-flight flag is set meanwhile',
      (t) async {
        await h.mount(t);
        final gate = Completer<PosProductModel?>();
        when(
          () => h.repo.getProductByBarcode(
            storeId: any(named: 'storeId'),
            barcode: any(named: 'barcode'),
          ),
        ).thenAnswer((_) => gate.future);
        final f = h.c.addProductByBarcode('  4006381333931 ');
        expect(h.c.isScanningBarcode.value, isTrue);
        gate.complete(h.products[2]);
        await f;
        expect(h.c.isScanningBarcode.value, isFalse);
        verify(
          () => h.repo.getProductByBarcode(
            storeId: 'store-1',
            barcode: '4006381333931',
          ),
        ).called(1);
        expect(h.c.cartItems.single.product.productId, 'c');
        expect(h.c.cartItems.single.variant!.variantId, 'c_v1');
        await t.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'not found → an error toast and nothing is added; blank codes never reach the server',
      (t) async {
        await h.mount(t);
        stubBarcode(null);
        await h.c.addProductByBarcode('999');
        expect(h.c.hasItems, isFalse);
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('No product found for that barcode.'), findsOneWidget);
        clearInteractions(h.repo);
        await h.c.addProductByBarcode('   ');
        await h.c.addProductByBarcode('');
        verifyNever(
          () => h.repo.getProductByBarcode(
            storeId: any(named: 'storeId'),
            barcode: any(named: 'barcode'),
          ),
        );
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'scanning the same product twice raises its quantity (one line)',
      (t) async {
        await h.mount(t);
        stubBarcode(h.products[0]);
        await h.c.addProductByBarcode('4006381333931');
        await h.c.addProductByBarcode('4006381333931');
        expect(h.c.cartItems.length, 1);
        expect(h.c.cartItems.single.quantity.value, 2);
        await t.pump(const Duration(seconds: 3));
      },
    );

    Future<void> openSheet(WidgetTester t, {Widget Function()? scan}) async {
      Get.bottomSheet(
        PosBarcodeSheet(c: h.c, scanScreenBuilder: scan),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
      await h.settle(t, frames: 5);
    }

    testWidgets(
      'sheet, manual entry: typing a code and tapping → closes the sheet and adds the product',
      (t) async {
        await h.mount(t);
        stubBarcode(h.products[1]);
        await openSheet(t);
        expect(find.text('Scan or enter barcode'), findsOneWidget);
        await t.enterText(
          find.descendant(
            of: find.byKey(const Key('barcodeField')),
            matching: find.byType(TextFormField),
          ),
          ' 4006381333931 ',
        );
        await t.tap(find.byKey(const Key('barcodeSubmit')));
        await h.settle(t, frames: 5);
        expect(find.text('Scan or enter barcode'), findsNothing);
        verify(
          () => h.repo.getProductByBarcode(
            storeId: 'store-1',
            barcode: '4006381333931',
          ),
        ).called(1);
        expect(h.c.cartItems.single.product.productId, 'b');
        await t.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'sheet, manual entry: the keyboard Done key submits; an empty field does nothing and the sheet stays',
      (t) async {
        await h.mount(t);
        stubBarcode(h.products[1]);
        await openSheet(t);
        await t.tap(find.byKey(const Key('barcodeSubmit')));
        await h.settle(t, frames: 3);
        expect(find.text('Scan or enter barcode'), findsOneWidget);
        verifyNever(
          () => h.repo.getProductByBarcode(
            storeId: any(named: 'storeId'),
            barcode: any(named: 'barcode'),
          ),
        );
        await t.enterText(
          find.descendant(
            of: find.byKey(const Key('barcodeField')),
            matching: find.byType(TextFormField),
          ),
          '123456',
        );
        await t.testTextInput.receiveAction(TextInputAction.done);
        await h.settle(t, frames: 5);
        expect(h.c.hasItems, isTrue);
        await t.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'sheet, CAMERA path: the scanned code comes back and is added; backing out adds nothing',
      (t) async {
        await h.mount(t);
        stubBarcode(h.products[2]);
        await openSheet(
          t,
          scan: () => const _FakeCamera(code: '5901234123457'),
        );
        await t.tap(find.byKey(const Key('scanWithCamera')));
        await h.settle(t, frames: 8);
        verify(
          () => h.repo.getProductByBarcode(
            storeId: 'store-1',
            barcode: '5901234123457',
          ),
        ).called(1);
        expect(h.c.cartItems.single.product.productId, 'c');
        // cancel: the camera screen pops with nothing
        clearInteractions(h.repo);
        h.c.clearSale();
        await openSheet(t, scan: () => const _FakeCamera(code: null));
        await t.tap(find.byKey(const Key('scanWithCamera')));
        await h.settle(t, frames: 8);
        verifyNever(
          () => h.repo.getProductByBarcode(
            storeId: any(named: 'storeId'),
            barcode: any(named: 'barcode'),
          ),
        );
        expect(h.c.hasItems, isFalse);
        await t.pump(const Duration(seconds: 3));
      },
    );
  });

  // ── the keyboard-wedge detector itself ───────────────────────────────────────────────────────────────────────
  group('HidScanDetector', () {
    late List<String> scans;
    late bool armed;
    late HidScanDetector d;

    setUp(() {
      scans = [];
      armed = true;
      d = HidScanDetector(isArmed: () => armed, onScan: scans.add)..start();
    });
    tearDown(() => d.stop());

    Future<void> burst(WidgetTester t, String code, {bool enter = true}) async {
      const k = {
        '0': LogicalKeyboardKey.digit0,
        '1': LogicalKeyboardKey.digit1,
        '2': LogicalKeyboardKey.digit2,
        '3': LogicalKeyboardKey.digit3,
        '4': LogicalKeyboardKey.digit4,
        '5': LogicalKeyboardKey.digit5,
        '6': LogicalKeyboardKey.digit6,
        '7': LogicalKeyboardKey.digit7,
        '8': LogicalKeyboardKey.digit8,
        '9': LogicalKeyboardKey.digit9,
      };
      for (final ch in code.split('')) {
        await t.sendKeyDownEvent(k[ch]!, character: ch);
        await t.sendKeyUpEvent(k[ch]!);
      }
      if (enter) await t.sendKeyEvent(LogicalKeyboardKey.enter);
    }

    testWidgets('a fast burst + Enter is a scan', (t) async {
      await burst(t, '4006381333931');
      expect(scans, ['4006381333931']);
    });

    testWidgets('too short (under 4 characters) is not a scan', (t) async {
      await burst(t, '123');
      expect(scans, isEmpty);
    });

    testWidgets('no Enter, no scan', (t) async {
      await burst(t, '123456', enter: false);
      expect(scans, isEmpty);
    });

    testWidgets(
      'disarmed (e.g. a sheet is open) → nothing, and the buffer does not leak into the next scan',
      (t) async {
        armed = false;
        await burst(t, '999999');
        expect(scans, isEmpty);
        armed = true;
        await burst(t, '123456');
        expect(scans, ['123456']);
      },
    );

    testWidgets(
      'a non-character key in the middle (an arrow, shift) means a person is typing — not a scan',
      (t) async {
        await t.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
        await t.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.digit3, character: '3');
        await t.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(scans, isEmpty);
      },
    );

    testWidgets('typed at human speed (> 60 ms between keys) is not a scan', (
      t,
    ) async {
      for (final ch in ['1', '2', '3', '4', '5']) {
        await t.sendKeyEvent(LogicalKeyboardKey.digit1, character: ch);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 90)),
        );
      }
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(scans, isEmpty);
    });
  });

  // ── customer picker ──────────────────────────────────────────────────────────────────────────────────────────
  group('customer picker sheet', () {
    late MockCustomerRepository repo;
    late SaleHarness h;
    const ada = CustomerModel(
      id: 'c1',
      name: 'Ada Lovelace',
      phone: '555-0101',
      orderCount: 4,
    );
    const bob = CustomerModel(id: 'c2', name: 'Bob', email: 'bob@x.com');

    setUp(() {
      repo = MockCustomerRepository();
      h = SaleHarness();
    });

    Future<void> open(WidgetTester t) async {
      Get.bottomSheet<CustomerModel>(
        PosCustomerPickerSheet(storeId: 'store-1', customerRepository: repo),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
      await h.settle(t, frames: 5);
    }

    testWidgets('browse list loads; tapping a customer returns it', (t) async {
      await h.mount(t);
      when(() => repo.getStoreCustomers('store-1')).thenAnswer(
        (_) async =>
            (items: [ada, bob], total: 2, totalPages: 1, hasMore: false),
      );
      CustomerModel? result;
      Get.bottomSheet<CustomerModel>(
        PosCustomerPickerSheet(storeId: 'store-1', customerRepository: repo),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      ).then((v) => result = v);
      await h.settle(t, frames: 5);
      expect(find.text('Select customer'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('555-0101'), findsOneWidget);
      expect(find.text('4 orders'), findsOneWidget);
      expect(find.text('bob@x.com'), findsOneWidget);
      await t.tap(find.byKey(const Key('customer-c1')));
      await h.settle(t, frames: 5);
      expect(result?.id, 'c1');
      expect(find.text('Select customer'), findsNothing);
    });

    testWidgets(
      'typing searches (debounced); clearing returns to the browse list; no match → empty state',
      (t) async {
        await h.mount(t);
        when(() => repo.getStoreCustomers('store-1')).thenAnswer(
          (_) async =>
              (items: [ada, bob], total: 2, totalPages: 1, hasMore: false),
        );
        when(
          () => repo.searchCustomers('store-1', 'zed'),
        ).thenAnswer((_) async => []);
        await open(t);
        await t.enterText(find.byType(TextField).last, 'zed');
        await t.pump(const Duration(milliseconds: 500));
        await t.pump(const Duration(milliseconds: 100));
        verify(() => repo.searchCustomers('store-1', 'zed')).called(1);
        expect(find.text('No customers found.'), findsOneWidget);
        await t.tap(find.byTooltip('Clear'));
        await h.settle(t, frames: 4);
        expect(find.text('Ada Lovelace'), findsOneWidget);
      },
    );

    testWidgets('Walk-in closes the sheet with no customer', (t) async {
      await h.mount(t);
      when(() => repo.getStoreCustomers('store-1')).thenAnswer(
        (_) async => (items: [ada], total: 1, totalPages: 1, hasMore: false),
      );
      CustomerModel? result = ada;
      Get.bottomSheet<CustomerModel>(
        PosCustomerPickerSheet(storeId: 'store-1', customerRepository: repo),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      ).then((v) => result = v);
      await h.settle(t, frames: 5);
      await t.tap(find.byKey(const Key('walkInButton')));
      await h.settle(t, frames: 5);
      expect(result, isNull);
      expect(find.text('Select customer'), findsNothing);
    });

    testWidgets(
      'in the cart, editing the name after picking a customer detaches the customer (no stale id is sent)',
      (t) async {
        await h.mount(t, size: const Size(1180, 820));
        h.addLine(h.products[0]);
        h.c.selectedCustomer.value = ada;
        h.c.customerController.text = ada.name;
        await h.settle(t);
        expect(h.c.selectedCustomer.value, isNotNull);
        await t.enterText(
          find.descendant(
            of: find.byKey(const Key('customerField')),
            matching: find.byType(TextFormField),
          ),
          'Someone else',
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(h.c.selectedCustomer.value, isNull);
        await t.pump(const Duration(seconds: 2));
      },
    );
  });
}

/// Stands in for the real camera screen (which needs the platform camera plugin): pops with a code, or with nothing.
class _FakeCamera extends StatefulWidget {
  const _FakeCamera({required this.code});
  final String? code;
  @override
  State<_FakeCamera> createState() => _FakeCameraState();
}

class _FakeCameraState extends State<_FakeCamera> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Get.back<String>(result: widget.code),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('camera')));
}
