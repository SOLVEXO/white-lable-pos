// Shared scaffolding for the Phase 3 sale-screen widget tests: a PosHomeController wired to a mocked PosRepository, the
// real sale screen mounted in a GetMaterialApp (themed light or dark, at a chosen size), and small fixtures.
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/category/models/product_model.dart'
    show VariantOption;
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/views/pos_home_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

class MockPosRepository extends Mock implements PosRepository {}

class MockCategoryRepository extends Mock implements CategoryRepository {}

typedef SaleResult = ({
  bool success,
  PosSaleModel? sale,
  String? message,
  bool queued,
});

PosProductModel product(
  String id, {
  double price = 10,
  int stock = 20,
  bool unlimited = false,
  String category = 'c1',
  String? name,
}) => PosProductModel(
  productId: id,
  name: name ?? 'Product $id',
  type: 'physical',
  categoryId: category,
  variants: [
    PosProductVariant(
      variantId: '${id}_v1',
      sku: 'SKU-$id',
      price: price,
      stock: stock,
      unlimitedStock: unlimited,
      isDefault: true,
    ),
  ],
);

PosProductModel multiVariant(String id) => PosProductModel(
  productId: id,
  name: 'Shirt $id',
  type: 'physical',
  categoryId: 'c1',
  variants: [
    PosProductVariant(
      variantId: '${id}_s',
      sku: 'S-$id',
      price: 20,
      stock: 5,
      isDefault: true,
      options: const [VariantOption(name: 'Size', value: 'S')],
    ),
    PosProductVariant(
      variantId: '${id}_m',
      sku: 'M-$id',
      price: 22,
      stock: 5,
      isDefault: false,
      options: const [VariantOption(name: 'Size', value: 'M')],
    ),
  ],
);

PosSaleModel sale({
  String number = 'S-0001',
  String status = 'completed',
  double total = 10,
  List<PosSaleItemModel> items = const [],
  String payment = 'card',
}) => PosSaleModel(
  id: 'sale-$number',
  saleNumber: number,
  storeId: 'store-1',
  sessionId: 'session-1',
  registerId: 'r',
  employeeId: 'e',
  items: items,
  discount: 0,
  tax: 0,
  subtotal: total,
  total: total,
  paymentMethod: payment,
  customerName: 'Walk-in',
  notes: '',
  status: status,
  createdAt: DateTime(2026, 1, 1),
);

class SaleHarness {
  final repo = MockPosRepository();
  final cats = MockCategoryRepository();
  late PosHomeController c;
  List<PosProductModel> products = [
    product('a'),
    product('b', price: 5),
    product('c', price: 7.5),
  ];

  static void setUpAllShared() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  }

  /// The named arguments of every createSale call, in order.
  final calls = <Map<Symbol, dynamic>>[];

  void stubCreateSale(Future<SaleResult> Function(Invocation inv) f) {
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
    ).thenAnswer((inv) {
      calls.add(Map.of(inv.namedArguments));
      return f(inv);
    });
  }

  VerificationResult verifyCreateSale({int times = 1}) => verify(
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
  );

  void stubQuote(
    ({PosQuote? quote, String? message, String? code}) Function() f,
  ) {
    when(
      () => repo.quoteSale(
        storeId: any(named: 'storeId'),
        items: any(named: 'items'),
        discountType: any(named: 'discountType'),
        discountValue: any(named: 'discountValue'),
        settingsVersion: any(named: 'settingsVersion'),
      ),
    ).thenAnswer((_) async => f());
  }

  /// Wires the mocks and registers a PosHomeController (no UI).
  void putController({
    bool manager = false,
    bool loading = false,
    double taxRate = 0,
    PosPaymentsRepository? payments,
    PendingQrStore? qrStore,
  }) {
    SoundUtil.enabled = false;
    SharedPreferences.setMockInitialValues({
      'pos_sound_effects': false,
      'store_id': 'store-1',
      'pos_session_id': 'session-1',
      'pos_register_id': 'r',
      'pos_employee_id': 'e',
      'pos_employee_role': manager ? 'manager' : 'cashier',
    });
    when(
      () => repo.getProducts(
        any(),
        page: any(named: 'page'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async {
      if (loading) {
        await Completer<void>().future; // never answers (no timer to leak)
      }
      return (
        items: products,
        total: products.length,
        totalPages: 1,
        hasMore: false,
      );
    });
    when(() => repo.getPosSettings(any())).thenAnswer(
      (_) async => PosSettingsModel(storeId: 'store-1', taxRate: taxRate),
    );
    when(
      () => repo.searchProducts(
        storeId: any(named: 'storeId'),
        q: any(named: 'q'),
      ),
    ).thenAnswer((_) async => products);
    stubQuote(
      () => (quote: null, message: null, code: null),
    ); // server unreachable → price locally
    when(() => cats.getCategories()).thenAnswer((_) async => null);
    c = PosHomeController(posRepository: repo, categoryRepository: cats, paymentsRepository: payments, pendingQrStore: qrStore);
    Get.put<PosHomeController>(c);
  }

  /// Wires the mocks, creates the controller and mounts the sale screen.
  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(390, 844),
    ThemeData? theme,
    bool manager = false,
    bool loading = false,
    Widget? home,
    double taxRate = 0,
    PosPaymentsRepository? payments,
    PendingQrStore? qrStore,
  }) async {
    putController(manager: manager, loading: loading, taxRate: taxRate, payments: payments, qrStore: qrStore);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(Get.reset);
    await t.pumpWidget(
      GetMaterialApp(
        theme: theme ?? AppTheme.light,
        // the real route name: the keyboard-wedge scanner only listens while Get.currentRoute is the POS screen
        initialRoute: Routes.posHome,
        getPages: [
          GetPage(name: Routes.posHome, page: () => home ?? PosHomeView()),
        ],
      ),
    );
    await settle(t);
  }

  /// Lets the async boot (prefs, products, settings) and entry animations finish.
  Future<void> settle(WidgetTester t, {int frames = 6}) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Puts [qty] of [p] in the cart exactly as tapping the tile would.
  void addLine(PosProductModel p, {int qty = 1}) {
    c.addToCart(p);
    final line = c.cartItems.firstWhere(
      (i) => i.product.productId == p.productId,
    );
    line.quantity.value = qty;
    c.cartItems.refresh();
  }
}
