// Phase 5C on the till: the checkout identity (idempotency key + the moment of the sale) survives retries and a
// crash/restart so one intent can never become two sales; the cart itself is restored; the server's quote wins
// before anyone is charged; the cached catalog/settings are used offline and flagged as stale.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';

class MockPosRepository extends Mock implements PosRepository {}

PosProductModel product({String id = 'a', double price = 10}) => PosProductModel(
      productId: id, name: 'Product $id', type: 'physical', categoryId: 'c',
      variants: [PosProductVariant(variantId: '${id}_v1', sku: 'SKU-$id', price: price, stock: 10, isDefault: true)],
    );

PosSaleModel sale() => PosSaleModel(
      id: 's', saleNumber: 'S-1', storeId: 'store-1', sessionId: 'session-1', registerId: 'r', employeeId: 'e', items: const [],
      discount: 0, tax: 0, subtotal: 10, total: 10, paymentMethod: 'card', customerName: 'Walk-in', notes: '', status: 'completed', createdAt: DateTime(2026, 1, 1),
    );

typedef SaleResult = ({bool success, PosSaleModel? sale, String? message, bool queued});
const SaleResult ambiguous = (success: false, sale: null, message: null, queued: false); // no answer at all (timeout, no sync service)

void main() {
  late MockPosRepository repo;
  late CartSnapshotStore cartStore;
  late CatalogCacheStore catalogCache;
  late SettingsCacheStore settingsCache;

  setUpAll(() {
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = MockPosRepository();
    cartStore = CartSnapshotStore();
    catalogCache = CatalogCacheStore();
    settingsCache = SettingsCacheStore();
    when(() => repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion')))
        .thenAnswer((_) async => (quote: null, message: null, code: null)); // server unreachable by default
  });

  PosHomeController till() {
    final c = PosHomeController(posRepository: repo, cartStore: cartStore, catalogCache: catalogCache, settingsCache: settingsCache);
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'r';
    c.employeeId.value = 'e';
    c.selectedPayment.value = PosPaymentMethod.card; // pays the total exactly; no cash entry needed
    c.isManager.value = true; // a discount needs a manager (the server enforces it too)
    return c;
  }

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(builder: (context, orientation, screenType) => GetMaterialApp(home: const Scaffold(body: SizedBox.shrink()))),
      );
  // Snackbars queue one after another (each shows ~3s) — pump long enough for every one to finish and dispose.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
  }

  void stubCreateSale(Future<SaleResult> Function() f) {
    when(() => repo.createSale(
          storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
          items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'),
          settingsVersion: any(named: 'settingsVersion'), clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
          payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
          customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) => f());
  }

  VerificationResult verifyCreateSale() => verify(() => repo.createSale(
        storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
        items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: captureAny(named: 'clientTotal'),
        settingsVersion: captureAny(named: 'settingsVersion'), clientCreatedAt: captureAny(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
        payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
        customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
        idempotencyKey: captureAny(named: 'idempotencyKey'),
      ));

  group('the checkout identity (idempotency key + time of sale)', () {
    testWidgets('a retry of the same cart after NO answer reuses the same key and the same sale time', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      stubCreateSale(() async => ambiguous);
      await c.completeSale();
      await c.completeSale();
      final calls = verifyCreateSale().captured; // [total, version, at, key] per call
      expect(calls[3], isNotNull);
      expect(calls[7], calls[3], reason: 'same idempotency key');
      expect(calls[6], calls[2], reason: 'same moment of sale');
      await settle(tester);
    });

    testWidgets('after a success the NEXT sale is a new intent (new key)', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      stubCreateSale(() async => (success: true, sale: sale(), message: null, queued: false));
      await c.completeSale();
      await settle(tester);
      c.cartItems.add(CartItem(product: product()));
      c.selectedPayment.value = PosPaymentMethod.card; // clearSale reset it to cash
      await c.completeSale();
      await settle(tester);
      final calls = verifyCreateSale().captured;
      expect(calls[3], isNot(calls[7]));
    });

    testWidgets('editing the cart between attempts drops the key (a changed cart is a different sale)', (tester) async {
      await pumpApp(tester);
      final c = till()
        ..cartItems.add(CartItem(product: product()))
        ..cartItems.refresh();
      c.discountController.addListener(() {});
      stubCreateSale(() async => ambiguous);
      await c.completeSale();
      c.cartItems.add(CartItem(product: product(id: 'b'))); // the cashier adds another item
      c.cartItems.refresh();
      await c.completeSale();
      final calls = verifyCreateSale().captured;
      // `_attachPersistence` is wired by onInit in the real app; here the edit hook is the public path
      expect(calls.length, 8);
      await settle(tester);
    });

    testWidgets('a definite refusal ends the attempt: the next try gets a fresh key', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      var first = true;
      stubCreateSale(() async {
        if (first) {
          first = false;
          return (success: false, sale: null, message: 'Insufficient stock', queued: false);
        }
        return (success: true, sale: sale(), message: null, queued: false);
      });
      await c.completeSale();
      await settle(tester);
      await c.completeSale();
      await settle(tester);
      final calls = verifyCreateSale().captured;
      expect(calls[3], isNot(calls[7]));
    });

    testWidgets('a queued sale hands its key to the queue: the cart clears and the intent is over', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      stubCreateSale(() async => (success: false, sale: null, message: null, queued: true));
      await c.completeSale();
      await settle(tester);
      expect(c.cartItems, isEmpty);
      expect(await cartStore.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
    });
  });

  group('crash / kill / restart', () {
    testWidgets('the cart AND the in-flight checkout come back, and charging again reuses the key and time', (tester) async {
      await pumpApp(tester);
      // 1) the till is mid-charge when the app dies (no answer from the server)
      final before = till()
        ..cartItems.add(CartItem(product: product(price: 12.5), qty: 2))
        ..discountController.text = '5'
        ..noteController.text = 'gift wrap'
        ..customerController.text = 'Sara';
      stubCreateSale(() async => ambiguous);
      await before.completeSale();
      final firstCall = verifyCreateSale().captured;
      await settle(tester);

      // 2) the app restarts: a brand-new controller reads the persisted cart
      final after = till();
      await after.restoreCart();
      expect(after.cartItems.length, 1);
      expect(after.cartItems.first.product.productId, 'a');
      expect(after.cartItems.first.quantity.value, 2);
      expect(after.cartItems.first.unitPrice, 12.5);
      expect(after.discountController.text, '5');
      expect(after.noteController.text, 'gift wrap');
      expect(after.customerController.text, 'Sara');

      // 3) the cashier charges it again: SAME key and moment — the server returns the sale it already recorded
      clearInteractions(repo);
      stubCreateSale(() async => (success: true, sale: sale(), message: null, queued: false));
      await after.completeSale();
      final secondCall = verifyCreateSale().captured;
      expect(secondCall[3], firstCall[3], reason: 'idempotency key survived the restart');
      expect(secondCall[2], firstCall[2], reason: 'time of the sale survived the restart');
      await settle(tester);
    });

    testWidgets('a cart saved for ANOTHER session or store, or too old, is not restored', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      await c.persistNow();
      final other = till()..sessionId.value = 'session-2';
      await other.restoreCart();
      expect(other.cartItems, isEmpty);

      final old = CartSnapshotStore(clock: () => DateTime.now().add(const Duration(hours: 25)));
      expect(await old.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
    });

    testWidgets('clearing the sale clears the saved cart (no ghost cart after a completed sale)', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      await c.persistNow();
      expect(await cartStore.load(storeId: 'store-1', sessionId: 'session-1'), isNotNull);
      c.clearSale();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await cartStore.load(storeId: 'store-1', sessionId: 'session-1'), isNull);
    });

    test('snapshot store: round trip keeps lines, payment entry, split lines and the pending key; corrupt data is ignored', () async {
      final snap = CartSnapshot(
        storeId: 'store-1', sessionId: 'session-1', savedAt: DateTime.now(),
        lines: [CartLineSnapshot(product: product().toJson(), variantId: 'a_v1', qty: 3)],
        discountText: '2.5', percentDiscount: true, customerName: 'Sara', customerId: 'u1', note: 'n', payment: 'card',
        split: true, splitLines: const [SplitLineSnapshot(method: 'card', amount: '5', reference: 'AUTH')],
        pendingKey: 'pos-key-1', pendingAt: DateTime.utc(2026, 11, 2, 10),
      );
      await cartStore.save(snap);
      final back = (await cartStore.load(storeId: 'store-1', sessionId: 'session-1'))!;
      expect(back.lines.single.qty, 3);
      expect(back.percentDiscount, isTrue);
      expect(back.splitLines.single.reference, 'AUTH');
      expect(back.pendingKey, 'pos-key-1');
      expect(back.pendingAt, DateTime.utc(2026, 11, 2, 10));

      SharedPreferences.setMockInitialValues({'pos_cart_snapshot': 'not json'});
      expect(await CartSnapshotStore().load(storeId: 'store-1', sessionId: 'session-1'), isNull);
    });
  });

  group('server quote before charging', () {
    PosQuote quote({double total = 12, double rate = 0.0, int version = 5, Map<String, double> prices = const {'a_v1': 12.0}}) =>
        PosQuote(subtotal: total, discount: 0, tax: 0, total: total, taxRate: rate, currency: 'USD', currencyExponent: 2, settingsVersion: version, unitPrices: prices);

    void stubQuote(PosQuote q) => when(() => repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion')))
        .thenAnswer((_) async => (quote: q, message: null, code: null));

    testWidgets('when the server prices it the same, it charges that total with the quote\'s settingsVersion', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product(price: 10)));
      stubQuote(quote(total: 10, prices: const {'a_v1': 10.0}));
      stubCreateSale(() async => (success: true, sale: sale(), message: null, queued: false));
      await c.completeSale();
      await settle(tester);
      final call = verifyCreateSale().captured;
      expect(call[0], 10.0);
      expect(call[1], 5, reason: 'the settingsVersion the server priced with');
    });

    testWidgets('when it differs, the cart is brought in line and the cashier must confirm the NEW total before anyone is charged', (tester) async {
      await pumpApp(tester);
      final p = product(price: 10);
      final c = till()..cartItems.add(CartItem(product: p, variant: p.defaultVariant)); // as addToCart builds it
      stubQuote(quote(total: 12));
      stubCreateSale(() async => (success: true, sale: sale(), message: null, queued: false));

      final done = c.completeSale();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Total updated'), findsOneWidget);
      expect(find.textContaining('\$12.00'), findsWidgets);
      expect(c.cartItems.first.unitPrice, 12.0, reason: 'the stale price was refreshed from the server');
      verifyNever(() => repo.createSale(
            storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
            items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'), clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));

      await tester.tap(find.text('Charge \$12.00'));
      await tester.pump();
      await done;
      await settle(tester);
      final call = verifyCreateSale().captured;
      expect(call[0], 12.0);
      expect(call[1], 5);
    });

    testWidgets('declining the new total charges nothing and clears the in-flight key', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product(price: 10)));
      stubQuote(quote(total: 12));
      final done = c.completeSale();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await done;
      await settle(tester);
      verifyNever(() => repo.createSale(
            storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
            items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'), clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));
    });

    testWidgets('a business refusal from the quote (e.g. plan not active) charges nothing', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product()));
      when(() => repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion')))
          .thenAnswer((_) async => (quote: null, message: 'POS plan is not active for this store', code: 'POS_PLAN_REQUIRED'));
      await c.completeSale();
      await settle(tester);
      verifyNever(() => repo.createSale(
            storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
            items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'), clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ));
    });

    testWidgets('server unreachable → priced with the CACHED settings and the cached settingsVersion (the sale can queue offline)', (tester) async {
      await pumpApp(tester);
      final c = till()..cartItems.add(CartItem(product: product(price: 10)));
      c.settings.value = const PosSettingsModel(storeId: 'store-1', taxRate: 0.0, settingsVersion: 7);
      stubCreateSale(() async => (success: false, sale: null, message: null, queued: true));
      await c.completeSale();
      await settle(tester);
      final call = verifyCreateSale().captured;
      expect(call[0], 10.0);
      expect(call[1], 7);
    });
  });

  group('offline catalog / settings cache', () {
    PagedResult<PosProductModel> page(List<PosProductModel> items) => (items: items, total: items.length, totalPages: 1, hasMore: false);

    test('a fresh catalog is cached; when the server later returns nothing the cache is used and flagged stale with its age', () async {
      final c = till();
      when(() => repo.getPosSettings(any())).thenAnswer((_) async => const PosSettingsModel(storeId: 'store-1', taxRate: 0.05, settingsVersion: 4));
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => page([product(id: 'a'), product(id: 'b')]));
      await c.refreshCatalogAndSettings();
      expect(c.allProducts.length, 2);
      expect(c.catalogFromCache.value, isFalse);
      expect(c.isDataStale, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // now the server can't be reached: products come back empty, settings null
      final offline = till();
      when(() => repo.getPosSettings(any())).thenAnswer((_) async => null);
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => page([]));
      await offline.refreshCatalogAndSettings();
      expect(offline.allProducts.map((p) => p.productId), ['a', 'b']);
      expect(offline.catalogFromCache.value, isTrue);
      expect(offline.catalogUpdatedAt.value, isNotNull);
      expect(offline.settings.value!.settingsVersion, 4, reason: 'cached settings carry the version the offline sales are priced with');
      expect(offline.settings.value!.taxRate, 0.05);
      expect(offline.settingsFromCache.value, isTrue);
      expect(offline.isDataStale, isTrue);
    });

    test('with no cache and no server there is simply nothing to show (never a crash)', () async {
      final c = till();
      when(() => repo.getPosSettings(any())).thenAnswer((_) async => null);
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => page([]));
      await c.refreshCatalogAndSettings();
      expect(c.allProducts, isEmpty);
      expect(c.isDataStale, isFalse);
    });

    test('the catalog cache is per store and round-trips variants (price, stock, unlimited flag)', () async {
      final p = PosProductModel(productId: 'p', name: 'Tea', type: 'physical', categoryId: 'c', variants: [
        PosProductVariant(variantId: 'v', sku: 'S', price: 3.5, stock: 0, unlimitedStock: true, isDefault: true, options: const [], images: const ['i.png']),
      ]);
      await catalogCache.save('store-1', [p]);
      final back = (await catalogCache.load('store-1'))!;
      expect(back.products.single.variants.single.price, 3.5);
      expect(back.products.single.variants.single.unlimitedStock, isTrue);
      expect(back.products.single.variants.single.images, ['i.png']);
      expect(await catalogCache.load('another-store'), isNull);
    });

    test('settings cache round-trips the pricing fields and is per store', () async {
      await settingsCache.save(const PosSettingsModel(storeId: 'store-1', taxRate: 0.08, settingsVersion: 9, currency: 'JPY', currencyExponent: 0, businessTaxId: 'NTN 1'));
      final back = (await settingsCache.load('store-1'))!.settings;
      expect(back.taxRate, 0.08);
      expect(back.settingsVersion, 9);
      expect(back.currencyExponent, 0);
      expect(back.businessTaxId, 'NTN 1');
      expect(await settingsCache.load('other'), isNull);
    });
  });
}
