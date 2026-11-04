// Swipe-to-remove Undo: restores the exact line at its position, merges if re-added, and is dropped when the cart is
// cleared, a sale is charged or held, a held sale is resumed, the window passes, or invalidate() is called.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

class MockPosRepository extends Mock implements PosRepository {}

typedef SaleResult = ({
  bool success,
  PosSaleModel? sale,
  String? message,
  bool queued,
});

PosProductModel _product(String id, double price) => PosProductModel(
  productId: id,
  name: 'Product $id',
  type: 'physical',
  categoryId: 'c',
  variants: [
    PosProductVariant(
      variantId: '${id}_v1',
      sku: 'SKU-$id',
      price: price,
      stock: 20,
      isDefault: true,
    ),
  ],
);

PosSaleModel _sale(String status, {List<PosSaleItemModel> items = const []}) =>
    PosSaleModel(
      id: 's',
      saleNumber: 'S-1',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'r',
      employeeId: 'e',
      items: items,
      discount: 0,
      tax: 0,
      subtotal: 10,
      total: 10,
      paymentMethod: 'card',
      customerName: 'Walk-in',
      notes: '',
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockPosRepository repo;
  late PosHomeController c;
  late CartRemovalUndo undo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
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
    c.selectedPayment.value = PosPaymentMethod.card;
    // lines exactly as addToCart builds them (with the default variant), so cart keys match a re-add
    CartItem line(String id, double price, int qty) {
      final p = _product(id, price);
      return CartItem(product: p, variant: p.defaultVariant, qty: qty);
    }

    c.cartItems.addAll([line('a', 10, 2), line('b', 5, 3), line('c', 7, 1)]);
    undo = CartRemovalUndo.of(c, showToast: false);
  });

  tearDown(() {
    undo.dispose();
    Get.reset();
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

  void stubCreateSale(SaleResult r) {
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
    ).thenAnswer((_) async => r);
  }

  testWidgets(
    'Undo restores the exact line (same item: product, variant, price, quantity) at its old position',
    (t) async {
      final b = c.cartItems[1];
      undo.remove(b);
      expect(c.cartItems.map((i) => i.product.productId), ['a', 'c']);
      expect(undo.undo(), isTrue);
      expect(c.cartItems.map((i) => i.product.productId), ['a', 'b', 'c']);
      expect(identical(c.cartItems[1], b), isTrue);
      expect(c.cartItems[1].quantity.value, 3);
      expect(c.cartItems[1].unitPrice, 5);
      expect(undo.canUndo, isFalse, reason: 'one undo per removal');
    },
  );

  testWidgets(
    'removing the LAST line leaves an empty cart that Undo can refill',
    (t) async {
      c.cartItems.removeWhere((i) => i.product.productId != 'a');
      undo.remove(c.cartItems.single);
      expect(c.cartItems, isEmpty);
      expect(undo.undo(), isTrue);
      expect(c.cartItems.single.product.productId, 'a');
    },
  );

  testWidgets(
    'if the product was added again meanwhile, the quantity is merged into that line (no duplicate line)',
    (t) async {
      final b = c.cartItems[1]; // qty 3
      undo.remove(b);
      c.addToCart(_product('b', 5)); // cashier re-scans it: new line, qty 1
      expect(
        c.cartItems
            .where((i) => i.product.productId == 'b')
            .single
            .quantity
            .value,
        1,
      );
      expect(undo.undo(), isTrue);
      final lines = c.cartItems
          .where((i) => i.product.productId == 'b')
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single.quantity.value, 4, reason: '1 re-added + 3 restored');
    },
  );

  testWidgets('the Undo window closes after ~4 s', (t) async {
    await pumpApp(t);
    undo.remove(c.cartItems[0]);
    await t.pump(const Duration(milliseconds: 3900));
    expect(undo.canUndo, isTrue);
    await t.pump(const Duration(milliseconds: 300));
    expect(undo.canUndo, isFalse);
    expect(undo.undo(), isFalse);
    expect(c.cartItems.length, 2);
  });

  testWidgets('clearing the cart invalidates the Undo', (t) async {
    undo.remove(c.cartItems[0]);
    c.clearSale();
    expect(undo.canUndo, isFalse);
    expect(undo.undo(), isFalse);
    expect(c.cartItems, isEmpty);
  });

  testWidgets(
    'charging the sale invalidates the Undo (and nothing is restored into the next sale)',
    (t) async {
      await pumpApp(t);
      stubCreateSale((
        success: true,
        sale: _sale('completed'),
        message: null,
        queued: false,
      ));
      undo.remove(c.cartItems[0]);
      await c.completeSale();
      await settle(t);
      expect(c.lastOutcome.value, SaleOutcome.completed);
      expect(undo.canUndo, isFalse);
      expect(undo.undo(), isFalse);
      expect(c.cartItems, isEmpty);
    },
  );

  testWidgets('holding the sale invalidates the Undo', (t) async {
    await pumpApp(t);
    stubCreateSale((
      success: true,
      sale: _sale('held'),
      message: null,
      queued: false,
    ));
    undo.remove(c.cartItems[0]);
    await c.holdSale();
    await settle(t);
    expect(undo.canUndo, isFalse);
    expect(c.cartItems, isEmpty);
  });

  testWidgets('resuming a held sale invalidates the Undo', (t) async {
    undo.remove(c.cartItems[0]);
    c.resumeHeldSale(
      _sale(
        'held',
        items: [
          PosSaleItemModel(
            saleItemId: 'i',
            productId: 'z',
            name: 'Z',
            sku: 'Z',
            price: 3,
            qty: 1,
            lineTotal: 3,
          ),
        ],
      ),
    );
    expect(undo.canUndo, isFalse);
    expect(undo.undo(), isFalse);
    expect(c.cartItems.map((i) => i.product.productId), ['z']);
  });

  testWidgets('a failed charge does NOT invalidate it (the cart is untouched)', (
    t,
  ) async {
    await pumpApp(t);
    stubCreateSale((
      success: false,
      sale: null,
      message: 'Insufficient stock',
      queued: false,
    ));
    undo.remove(c.cartItems[0]);
    await c.completeSale();
    await settle(t);
    // the window (4 s) has long passed in this test — what matters is the cart was not cleared:
    expect(c.cartItems.length, 2);
  });

  testWidgets(
    'invalidate() drops it explicitly (held-sales button, start of a charge / hold)',
    (t) async {
      undo.remove(c.cartItems[0]);
      undo.invalidate();
      expect(undo.canUndo, isFalse);
    },
  );

  testWidgets(
    'a second removal replaces the first: only the most recent can be undone',
    (t) async {
      final a = c.cartItems[0];
      undo.remove(a);
      final b = c.cartItems[0]; // b is now first
      undo.remove(b);
      expect(undo.undo(), isTrue);
      expect(c.cartItems.map((i) => i.product.productId), ['b', 'c']);
      expect(c.cartItems.any((i) => identical(i, a)), isFalse);
      expect(undo.undo(), isFalse);
    },
  );
}
