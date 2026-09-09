// ignore_for_file: avoid_print
// End-to-end pass for the core POS checkout flow: PIN login -> open register
// -> add item to cart -> apply discount+tax -> complete a cash sale -> the
// sale appears in Orders. No staging environment is available, so the
// repository layer is mocked (PosRepository, SellerRepository) exactly like
// the buyer app's integration_test/guest_mode_e2e_test.dart — everything
// else (real navigation, real widget tree, real AppPreferences/secure
// storage on the simulator) is exercised for real.
//
// ── Why this test starts at PIN login, not the seller login screen ─────────
// AppPages.initialRoute is Routes.posLogin (the seller's own account
// login) — reaching PIN login for real would mean driving seller
// email/password login, store selection, and "Open POS Terminal" first.
// PosAccessMiddleware (see lib/app/middleware/auth_middleware.dart) gates
// every POS route with a synchronous, in-memory check of
// AppPreferences.cachedToken/cachedRole (warmed at boot) — nothing checks
// how the seller got logged in. So this test seeds a fake seller
// token+role+storeId directly via AppPreferences *before* app.main() runs,
// then jumps straight to Routes.posPinLogin with Get.offAllNamed once boot
// completes — the same "skip the parts of the flow that aren't what this
// test is about" approach the buyer app's test uses for onboarding/auth.
//
// ── Why controllers are pre-registered with Get.lazyPut, not Get.put ───────
// PosPinLoginView/PosOpenRegisterView do `final c = Get.find();` (the
// binding's own Get.lazyPut registers the real controller); PosHomeView/
// PosOrdersView do `final c = Get.put(RealController());` directly in the
// view itself. Either way, GetX's permanent-instance rule (see the buyer
// app test's header comment) means: whichever registration for a given
// type happens FIRST and is `permanent: true` wins, and every later
// put/lazyPut for that type becomes a no-op returning the existing
// instance. So registering our mocked controllers via Get.lazyPut, right
// after boot, before any navigation, ensures the real bindings' own
// put/lazyPut calls (whichever happens later, when each screen is actually
// visited) just return ours instead.
// Using `lazyPut` (not `put`) here specifically matters for
// PosOpenRegisterController: it reads `Get.arguments['employee']` as a
// field *inside onInit*, which only has a real value once
// PosPinLoginController actually navigates there with `arguments: {...}`.
// `Get.put()` would construct (and run onInit) immediately, before that
// navigation happens, crashing on a null Get.arguments. `Get.lazyPut()`
// only registers a builder — actual construction is deferred to the first
// `Get.find()`, which naturally happens when the Open Register screen is
// actually built, by which point Get.arguments is already correct.
//
// ── A genuine, unresolved fragility this test surfaces — diagnosed in
// full, not routed around (this is currently a FAILING test; see below) ───
// main.dart's boot sequence has this fire-and-forget block:
//   if ((AppPreferences.cachedToken ?? '').isNotEmpty) {
//     unawaited(AuthRepository().getProfile().then(...));
//   }
// `AuthRepository()` is constructed fresh, inline, in main.dart itself —
// not behind any Get.find()/DI seam — so there is no way to inject a mock
// into this specific call. Since this test must seed a non-empty token for
// PosAccessMiddleware to allow navigation past posLogin, this background
// call *always* fires against the real backend with a fake token, which
// *always* gets a real 401 (confirmed by running this test repeatedly).
// Traced the full consequence chain:
//   1. ~500-1000ms after boot, that 401 reaches DioService's onError
//      interceptor (lib/app/network/dio_service.dart), which — because the
//      request had requiresAuth: true — calls
//      `await AppPreferences.clearPreference()` (a full local-session wipe:
//      token, role, AND storeId) followed by `onForceLogout?.call()`.
//   2. `onForceLogout` (wired in main.dart) is
//      `Get.offAllNamed(Routes.posLogin)` — unconditional, whenever the
//      current route isn't already posLogin.
//   3. This fires regardless of what this test has done in the meantime:
//      confirmed by instrumenting the boot-settle window in 500ms steps —
//      at t=500ms the app is legitimately on /seller/stores with our
//      seeded storeId intact (the SellerStoresController mock below
//      prevents ITS OWN cascade); by t=1000ms the route has been yanked
//      back to /pos/login and storeId is null, wiped by step 1.
// This is the same class of problem as the skill's "networking clients
// created fresh per call, not injected" gotcha (#3) — DI-based mocking is a
// dead end for this specific call. The one-line fix would be giving
// main.dart's AuthRepository the same optional-constructor seam every
// controller already has (`AuthRepository({AuthRepository? ...})`-style is
// N/A here since it'd need a module-level override hook instead, e.g. a
// settable `AuthRepository Function() authRepositoryFactory` main.dart
// reads instead of constructing directly) — genuinely out of this task's
// scope (touching main.dart's boot sequence, not a test file). Until that
// exists, this test is written and internally consistent, but will fail at
// the `expect(pinController.selectedRegister...)` line below once the
// force-logout fires — see the session report for the exact run output.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_product_card.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transaction_card.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'package:solvexo_pos/main.dart' as app;

class MockPosRepository extends Mock implements PosRepository {}

class MockSellerRepository extends Mock implements SellerRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  // Looping small pumps rather than one big tester.pump(Duration) — see
  // guest_mode_e2e_test.dart's identical note on this hanging against a
  // real (non-fake-async) integration_test binding once real I/O is
  // in flight.
  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    final end = DateTime.now().add(total);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('PIN login -> open register -> add item, discount+tax -> cash checkout -> appears in Orders',
      (tester) async {
    // ── Seed local state PosAccessMiddleware checks synchronously ──────────
    await AppPreferences.setTokens(accessToken: 'e2e-seed-token', refreshToken: 'e2e-seed-refresh');
    await AppPreferences.setUserRole('seller');
    await AppPreferences.saveStoreId('store-1');

    app.main();
    await tester.pump();

    // ── Fixtures ─────────────────────────────────────────────────────────
    final employee = PosEmployeeModel(
      id: 'emp-1',
      storeId: 'store-1',
      sellerId: 'seller-1',
      name: 'E2E Manager',
      email: 'manager@example.com',
      // manager, not cashier — so the discount field (manager-only, see
      // PosHomeController.isDiscountBlocked) is actually usable below.
      role: 'manager',
      shiftIds: const ['shift-1'],
      status: 'active',
      createdAt: DateTime.now(),
    );
    const register = StoreRegister(id: 'register-1', name: 'Front Counter', defaultFloatCash: 0, status: 'active');
    final store = StoreModel(
      id: 'store-1',
      sellerId: 'seller-1',
      name: 'E2E Test Store',
      slug: 'e2e-test-store',
      logo: '',
      categoryId: 'cat-1',
      description: '',
      sellerType: 'individual',
      productTypes: const [],
      enabledTools: const [],
      plan: 'free',
      aiCredits: 0,
      status: 'active',
      isDelete: false,
      registers: const [register],
      shifts: const [],
      sellerName: 'E2E Seller',
      sellerEmail: 'seller@example.com',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final product = PosProductModel(
      productId: 'prod-1',
      name: 'E2E Widget',
      type: 'physical',
      categoryId: 'cat-1',
      variants: const [
        PosProductVariant(variantId: 'var-1', sku: 'SKU-1', price: 20.0, stock: 10, isDefault: true),
      ],
    );
    final session = PosSessionModel(
      id: 'session-1',
      storeId: 'store-1',
      registerId: 'register-1',
      employeeId: 'emp-1',
      shiftId: 'shift-1',
      openedAt: DateTime.now(),
      openingCash: 100,
      expectedCash: 100,
      cashDifference: 0,
      cashSales: 0,
      cardSales: 0,
      otherSales: 0,
      totalSales: 0,
      totalTransactions: 0,
      totalRefunds: 0,
      status: 'open',
      cashAdjustments: const [],
    );
    // subtotal 20.00, flat discount 2.00, 5% tax on the post-discount
    // amount ((20-2)*0.05=0.90) -> total 18.90. Fixed rather than captured
    // from the real createSale call's arguments, so the same fixture can
    // back both the checkout response and the later Orders-list response.
    final completedSale = PosSaleModel(
      id: 'sale-1',
      saleNumber: 'S-0001',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'register-1',
      employeeId: 'emp-1',
      items: [
        const PosSaleItemModel(productId: 'prod-1', name: 'E2E Widget', qty: 1, price: 20.0, lineTotal: 20.0),
      ],
      discount: 2.0,
      tax: 0.90,
      subtotal: 20.0,
      total: 18.90,
      paymentMethod: 'cash',
      customerName: 'Walk-in',
      notes: '',
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final mockPosRepo = MockPosRepository();
    final mockSellerRepo = MockSellerRepository();

    when(() => mockSellerRepo.getStoreById(any())).thenAnswer((_) async => store);
    // PosLoginController._restoreSession() unconditionally does
    // Get.offAllNamed(Routes.sellerStores) at boot whenever a token exists
    // (see the header comment) — SellerStoresController then really calls
    // getMyStores(); with a fake token that's a real 401, and an empty
    // result sends it to Routes.sellerOnboarding, which — as observed while
    // building this test — wipes the very storeId this test seeded (which
    // is what PosPinLoginController's mocked _loadStore() needs to find our
    // register). Stubbing getMyStores() to return our one store avoids that
    // cascade instead of trying to out-race it with navigation timing.
    when(() => mockSellerRepo.getMyStores()).thenAnswer((_) async => [store]);
    when(() => mockPosRepo.getPosSettings(any())).thenAnswer(
      (_) async => const PosSettingsModel(storeId: 'store-1', taxRate: 0, currencySymbol: '\$'),
    );
    when(() => mockPosRepo.getProducts(any(),
        page: any(named: 'page'), limit: any(named: 'limit'), categoryId: any(named: 'categoryId'))).thenAnswer(
        (_) async => (items: [product], total: 1, totalPages: 1, hasMore: false));
    when(() => mockPosRepo.pinLogin(
          storeId: any(named: 'storeId'),
          email: any(named: 'email'),
          pin: any(named: 'pin'),
        )).thenAnswer(
        (_) async => (success: true, employee: employee, activeSession: null, employeeToken: 'e2e-emp-token', message: null));
    when(() => mockPosRepo.getActiveSession(storeId: any(named: 'storeId'), registerId: any(named: 'registerId')))
        .thenAnswer((_) async => null);
    when(() => mockPosRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        )).thenAnswer((_) async => (success: true, session: session, message: null));
    when(() => mockPosRepo.createSale(
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
        )).thenAnswer((_) async => (success: true, sale: completedSale, message: null, queued: false));
    when(() => mockPosRepo.getSales(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          employeeId: any(named: 'employeeId'),
          paymentMethod: any(named: 'paymentMethod'),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          page: any(named: 'page'),
        )).thenAnswer((_) async => (items: [completedSale], total: 1, totalPages: 1, hasMore: false));

    // ── Pre-register mocked controllers (see header comment on why
    // lazyPut, not put, and why this must happen before any navigation) ────
    // SellerStoresController is included here for the getMyStores() cascade
    // reason above, even though this test never visits /seller/stores
    // itself — the *natural* boot flow (PosLoginController._restoreSession)
    // visits it automatically because we've seeded a token.
    Get.lazyPut<SellerStoresController>(
      () => SellerStoresController(sellerRepository: mockSellerRepo),
      fenix: false,
    );
    Get.lazyPut<PosPinLoginController>(
      () => PosPinLoginController(posRepository: mockPosRepo, sellerRepository: mockSellerRepo),
      fenix: false,
    );
    Get.lazyPut<PosOpenRegisterController>(
      () => PosOpenRegisterController(posRepository: mockPosRepo),
      fenix: false,
    );
    Get.lazyPut<PosHomeController>(() => PosHomeController(posRepository: mockPosRepo), fenix: false);
    Get.lazyPut<PosOrdersController>(() => PosOrdersController(posRepository: mockPosRepo), fenix: false);

    // ── Jump straight to PIN login (see header comment) ─────────────────────
    await pumpFor(tester, const Duration(seconds: 3)); // let boot (Firebase/BrandingService/etc) settle
    Get.offAllNamed(Routes.posPinLogin);
    await pumpUntil(tester, () => Get.currentRoute == Routes.posPinLogin);
    final pinController = Get.find<PosPinLoginController>();
    await pumpUntil(tester, () => !pinController.isLoadingStore.value);
    print('✅ Landed on PIN login with the mocked register auto-selected');
    expect(pinController.selectedRegister.value?['id'], 'register-1');

    // ── PIN login ────────────────────────────────────────────────────────
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == pinController.emailController),
      'manager@example.com',
    );
    await tester.pump(const Duration(milliseconds: 200));
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit).first);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await pumpUntil(tester, () => Get.currentRoute == Routes.posOpenRegister, timeout: const Duration(seconds: 15));
    print('✅ PIN login succeeded, landed on Open Register (no active session yet)');

    // ── Open register ────────────────────────────────────────────────────
    final openRegisterController = Get.find<PosOpenRegisterController>();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == openRegisterController.openingCashController),
      '100',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Open Register & Start Shift'));
    await pumpUntil(tester, () => Get.currentRoute == Routes.posHome, timeout: const Duration(seconds: 15));
    print('✅ Register opened, landed on POS Home');

    // ── Add item to cart ─────────────────────────────────────────────────
    final homeController = Get.find<PosHomeController>();
    await pumpUntil(tester, () => find.byType(PosProductCard).evaluate().isNotEmpty);
    await tester.tap(find.byType(PosProductCard).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(homeController.hasItems, isTrue, reason: 'tapping the product card should add it to the cart');
    expect(homeController.subtotal, 20.0);
    print('✅ Added E2E Widget (\$20.00) to the cart');

    // ── Open the cart sheet, apply discount + tax, verify the math ──────────
    await tester.tap(find.text('View Cart'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == homeController.discountController),
      '2',
    );
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == homeController.taxController),
      '5',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(homeController.discountValue, 2.0, reason: 'flat \$2 discount');
    expect(homeController.taxValue, closeTo(0.90, 0.001), reason: '5% tax on the post-discount \$18');
    expect(homeController.total, closeTo(18.90, 0.001));
    print('✅ Discount (\$2.00 flat) + tax (5%) applied; total correctly \$18.90');

    // ── Cash payment (cash is the default selectedPayment) ───────────────
    await tester.enterText(
      find.byWidgetPredicate((w) => w is TextFormField && w.controller == homeController.tenderedController),
      '20',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(homeController.canCharge, isTrue);

    // ── Complete the sale ────────────────────────────────────────────────
    await tester.tap(find.textContaining('Charge'));
    await pumpFor(tester, const Duration(seconds: 2));
    verify(() => mockPosRepo.createSale(
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
        )).called(1);
    expect(homeController.hasItems, isFalse, reason: 'cart clears after a successful sale');
    print('✅ Cash sale completed, cart cleared');

    // ── Navigate to Orders, confirm the sale appears ────────────────────────
    Get.find<PosBottomNavController>().changeTab(1); // Orders tab
    await pumpFor(tester, const Duration(seconds: 1));
    final ordersController = Get.find<PosOrdersController>();
    await pumpUntil(tester, () => !ordersController.isLoading.value);
    expect(find.byType(PosTransactionCard), findsWidgets, reason: 'the just-completed sale should appear in Orders');
    expect(find.text('S-0001'), findsOneWidget);
    print('✅ Completed sale (S-0001) appears in Orders');
  });
}
