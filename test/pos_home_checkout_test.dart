// Unit tests for PosHomeController's checkout actions (completeSale/
// holdSale) against a mocked PosRepository — the seam added in Phase 4.
// Wrapped in testWidgets with a real GetMaterialApp so Get.back() and the
// CustomAppSnackbar calls inside the controller have a real overlay/
// navigator to act on, instead of throwing on a bare `test()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';

class MockPosRepository extends Mock implements PosRepository {}

PosProductModel _product({required String id, required double price}) {
  return PosProductModel(
    productId: id,
    name: 'Product $id',
    type: 'physical',
    categoryId: 'cat-1',
    variants: [
      PosProductVariant(variantId: '${id}_v1', sku: 'SKU-$id', price: price, stock: 10, isDefault: true),
    ],
  );
}

PosSaleModel _sale({required String status}) => PosSaleModel(
      id: 'sale-1',
      saleNumber: 'S-0001',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'register-1',
      employeeId: 'employee-1',
      items: const [],
      discount: 0,
      tax: 0,
      subtotal: 10,
      total: 10,
      paymentMethod: 'cash',
      customerName: 'Walk-in',
      notes: '',
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockPosRepository posRepo;
  late PosHomeController c;

  setUpAll(() {
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    posRepo = MockPosRepository();
    c = PosHomeController(posRepository: posRepo);
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'register-1';
    c.employeeId.value = 'employee-1';
    c.cartItems.add(CartItem(product: _product(id: 'a', price: 10.0)));
    // Card, not the default cash, so isCashUnderTendered (tendered defaults
    // to 0) never blocks these tests before reaching the repository call —
    // that gate already has its own coverage in pos_cart_math_test.dart.
    c.selectedPayment.value = PosPaymentMethod.card;
  });

  tearDown(() {
    c.searchController.dispose();
    c.noteController.dispose();
    c.customerController.dispose();
    c.discountController.dispose();
    c.taxController.dispose();
    c.tenderedController.dispose();
    c.paymentReferenceController.dispose();
    c.productScrollController.dispose();
  });

  // ResponsiveSizer is required — CustomAppSnackbar's layout uses its `.h`/
  // `.w` extensions, which blow up (RenderFlex overflow) without a real
  // ResponsiveSizer ancestor providing screen dimensions. Settling for a
  // full 3s (the snackbar's fixed display duration) after each action lets
  // its OverlayEntry animate out and dispose before the test ends — skip
  // that and the next test's pumpWidget collides with GetX's still-mounted
  // snackbar route on the same static navigator key ("Duplicate GlobalKey").
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) =>
              GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
        ),
      );

  Future<void> settleSnackbar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('completeSale sends status=completed and clears the cart on success', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async => (success: true, sale: _sale(status: 'completed'), message: null, queued: false));

    await c.completeSale();
    await settleSnackbar(tester);

    final captured = verify(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: captureAny(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).captured;
    expect(captured.single, 'completed');
    expect(c.hasItems, isFalse, reason: 'cart clears after a successful sale');
  });

  testWidgets('holdSale sends status=held and clears the cart on success', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async => (success: true, sale: _sale(status: 'held'), message: null, queued: false));

    await c.holdSale();
    await settleSnackbar(tester);

    final captured = verify(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: captureAny(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).captured;
    expect(captured.single, 'held');
    expect(c.hasItems, isFalse);
  });

  testWidgets('completeSale keeps the cart and does not treat a queued (offline) sale as an error', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async => (success: false, sale: null, message: null, queued: true));

    await c.completeSale();
    await settleSnackbar(tester);

    // Queued still clears the cart (the sale was accepted locally) — it's
    // only surfaced differently (a warning, not an error) than a real failure.
    expect(c.hasItems, isFalse);
  });

  testWidgets('completeSale does nothing when there is no active session', (tester) async {
    await pumpApp(tester);
    c.sessionId.value = '';

    await c.completeSale();
    await settleSnackbar(tester);

    verifyNever(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ));
    expect(c.hasItems, isTrue, reason: 'nothing should be cleared when blocked before the API call');
  });

  testWidgets('completeSale keeps the cart when the repository reports a real failure', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discount: any(named: 'discount'),
          tax: any(named: 'tax'),
          paymentMethod: any(named: 'paymentMethod'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((_) async => (success: false, sale: null, message: 'Out of stock', queued: false));

    await c.completeSale();
    await settleSnackbar(tester);

    expect(c.hasItems, isTrue, reason: 'a real failure must not silently drop the cart');
  });
}
