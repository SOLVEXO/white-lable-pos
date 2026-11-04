// PosHomeController.lastOutcome / lastReceipt: the read-only result of the most recent Charge, used by the sale-success
// view. Reset to null at the very start of completeSale(); set only where the success / queued toast fires; a failure,
// a decline or an early return leaves them null (so the success view can never show for a failed sale).
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/utils/sound_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockPosRepository extends Mock implements PosRepository {}

typedef SaleResult = ({
  bool success,
  PosSaleModel? sale,
  String? message,
  bool queued,
});

PosProductModel _product() => PosProductModel(
  productId: 'a',
  name: 'Latte',
  type: 'physical',
  categoryId: 'c',
  variants: [
    PosProductVariant(
      variantId: 'a_v1',
      sku: 'SKU-a',
      price: 10,
      stock: 10,
      isDefault: true,
    ),
  ],
);

PosSaleModel _sale() => PosSaleModel(
  id: 'sale-1',
  saleNumber: 'S-0001',
  storeId: 'store-1',
  sessionId: 'session-1',
  registerId: 'r',
  employeeId: 'e',
  items: const [],
  discount: 0,
  tax: 0,
  subtotal: 10,
  total: 10,
  paymentMethod: 'card',
  customerName: 'Walk-in',
  notes: '',
  status: 'completed',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late MockPosRepository repo;
  late PosHomeController c;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SoundUtil.enabled = false;
    SharedPreferences.setMockInitialValues({'pos_sound_effects': false});
    repo = MockPosRepository();
    when(
      () => repo.quoteSale(
        storeId: any(named: 'storeId'),
        items: any(named: 'items'),
        discountType: any(named: 'discountType'),
        discountValue: any(named: 'discountValue'),
        settingsVersion: any(named: 'settingsVersion'),
      ),
    ).thenAnswer((_) async => (quote: null, message: null, code: null));
    c = PosHomeController(posRepository: repo);
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'r';
    c.employeeId.value = 'e';
    c.selectedPayment.value = PosPaymentMethod.card; // pays the total exactly
    c.cartItems.add(CartItem(product: _product()));
  });

  tearDown(() {
    Get.reset(); // a registered PendingSaleSyncService (closed store) must not leak into the next test
    for (final t in [
      c.searchController,
      c.noteController,
      c.customerController,
      c.discountController,
      c.tenderedController,
      c.paymentReferenceController,
    ]) {
      t.dispose();
    }
    c.productScrollController.dispose();
  });

  Future<void> pumpApp(WidgetTester t) => t.pumpWidget(
    ResponsiveSizer(
      builder: (_, __, ___) =>
          GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
    ),
  );
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 4));
    }
  }

  void stubCreateSale(Future<SaleResult> Function(Invocation) f) {
    when(
      () => repo.createSale(
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
      ),
    ).thenAnswer((inv) => f(inv));
  }

  testWidgets('starts null', (t) async {
    expect(c.lastOutcome.value, isNull);
    expect(c.lastReceipt.value, isNull);
  });

  testWidgets(
    'a completed sale sets lastOutcome = completed and the server receipt',
    (t) async {
      await pumpApp(t);
      stubCreateSale(
        (_) async =>
            (success: true, sale: _sale(), message: null, queued: false),
      );
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.completed);
      expect(c.lastReceipt.value, isNotNull);
      expect(c.lastReceipt.value!.receiptNumber, 'S-0001');
      expect(c.hasItems, isFalse);
    },
  );

  testWidgets(
    'a queued (offline) sale sets queuedOffline and the provisional OFF- receipt',
    (t) async {
      await pumpApp(t);
      // real file I/O must run outside the fake-async zone
    final tmp = (await t.runAsync(() => Directory.systemTemp.createTemp('pos_outcome_')))!;
    final store = PendingSaleLocalStore(
      dbPath: '${tmp.path}/q.db',
      cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 9))),
    );
    final sync = PendingSaleSyncService(
      posRepository: repo,
      localStore: store,
      currentStoreId: () async => 'store-1',
      currentDeviceId: () async => 'dev-AAAAAA',
      persistLastSync: false,
    );
    Get.put<PendingSaleSyncService>(sync);
      // the repository queues the sale under the checkout's idempotency key, exactly as PosRepository.createSale does
      stubCreateSale((inv) async {
        final key = inv.namedArguments[#idempotencyKey] as String;
        await store.enqueue(key, {
          'storeId': 'store-1',
          'sessionId': 'session-1',
          'items': [],
          'clientTotal': 10.0,
          'clientCreatedAt': '2026-11-02T10:00:00.000Z',
          'idempotencyKey': key,
        }, deviceShort: 'AAAAAA');
        return (success: false, sale: null, message: null, queued: true);
      });
      await t.runAsync(() async {
        await c.completeSale();
      });
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.queuedOffline);
      expect(c.lastReceipt.value, isNotNull);
      expect(c.lastReceipt.value!.receiptNumber, startsWith('OFF-'));
      expect(c.hasItems, isFalse);
      await t.runAsync(() async {
        await store.close();
        await tmp.delete(recursive: true);
      });
    },
  );

  testWidgets(
    'a queued sale whose receipt could not be built still reports queuedOffline (receipt null)',
    (t) async {
      await pumpApp(
        t,
      ); // no PendingSaleSyncService registered → no provisional receipt
      stubCreateSale(
        (_) async => (success: false, sale: null, message: null, queued: true),
      );
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.queuedOffline);
      expect(c.lastReceipt.value, isNull);
    },
  );

  testWidgets('a failed sale leaves both null and keeps the cart', (t) async {
    await pumpApp(t);
    stubCreateSale(
      (_) async => (
        success: false,
        sale: null,
        message: 'Insufficient stock',
        queued: false,
      ),
    );
    await c.completeSale();
    await settle(t);
    expect(c.lastOutcome.value, isNull);
    expect(c.lastReceipt.value, isNull);
    expect(c.hasItems, isTrue);
  });

  testWidgets(
    'an unanswered charge (no response at all) leaves both null too',
    (t) async {
      await pumpApp(t);
      stubCreateSale(
        (_) async => (success: false, sale: null, message: null, queued: false),
      );
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, isNull);
      expect(c.lastReceipt.value, isNull);
    },
  );

  testWidgets(
    'a second Charge resets the previous result at the very start — even if it fails or returns early',
    (t) async {
      await pumpApp(t);
      stubCreateSale(
        (_) async =>
            (success: true, sale: _sale(), message: null, queued: false),
      );
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.completed);

      // second sale fails → the old "completed" must not linger
      c.cartItems.add(CartItem(product: _product()));
      c.selectedPayment.value = PosPaymentMethod.card; // clearSale() put it back to cash
      stubCreateSale(
        (_) async => (
          success: false,
          sale: null,
          message: 'Insufficient stock',
          queued: false,
        ),
      );
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, isNull);
      expect(c.lastReceipt.value, isNull);

      // …and an early return (empty cart) also clears it
      c.selectedPayment.value = PosPaymentMethod.card;
      stubCreateSale(
        (_) async =>
            (success: true, sale: _sale(), message: null, queued: false),
      );
      await c.completeSale(); // succeeds (cart still has the line)
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.completed);
      await c
          .completeSale(); // cart is now empty → returns at the guard, after resetting
      expect(c.lastOutcome.value, isNull);
      expect(c.lastReceipt.value, isNull);
    },
  );
}
