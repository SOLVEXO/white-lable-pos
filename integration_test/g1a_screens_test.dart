// ignore_for_file: avoid_print
// G1a screenshots (NOT a regression test): the real app on a simulator with mocked repositories; prints `SHOT <name>` markers that
// tool/shoot.sh turns into real simulator screenshots. Original header follows:
// Phase 3, the real app on a simulator with the repository layer mocked (like pos_checkout_flow_test):
//  A) park a sale -> resume it from Held Sales -> split payment (card + cash) -> success view
//  B) the server quote changes the total -> "Total updated" confirm (inside completeSale) -> charged at the NEW total
// Seeds a signed-in till with a running shift, then jumps straight to the POS screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/controllers/pos_held_sales_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_products/controllers/pos_products_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart' show ProductTile;
import 'package:solvexo_pos/main.dart' as app;
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

class MockPosRepository extends Mock implements PosRepository {}

class MockInventoryRepository extends Mock implements InventoryRepository {}

class MockSellerRepository extends Mock implements SellerRepository {}

class MockPosSubscriptionRepository extends Mock implements PosSubscriptionRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(WidgetTester t, bool Function() ok, {Duration timeout = const Duration(seconds: 25), String what = 'condition'}) async {
    final end = DateTime.now().add(timeout);
    while (!ok()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what (route ${Get.currentRoute})');
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFor(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('G1a screenshots: five-tab shell per role, sell, design gallery', (tester) async {
    await AppPreferences.clearPreference();
    await AppPreferences.clearTokens();
    await AppPreferences.setPosSoundEffects(false);
    await AppPreferences.saveStoreId('store-1');
    await AppPreferences.setHasSeenOnboarding(true);

    app.main();
    await tester.pump();

    // ── fixtures ──────────────────────────────────────────────────────────────────────────────────────────────
    const product = PosProductModel(productId: 'prod-1', name: 'E2E Widget', type: 'physical', categoryId: 'cat-1', variants: [PosProductVariant(variantId: 'var-1', sku: 'SKU-1', price: 20.0, stock: 50, isDefault: true)]);
    PosSaleModel sale(String id, String number, String status, double total) => PosSaleModel(
          id: id,
          saleNumber: number,
          storeId: 'store-1',
          sessionId: 'session-1',
          registerId: 'register-1',
          employeeId: 'emp-1',
          items: [PosSaleItemModel(saleItemId: '$id-1', productId: 'prod-1', variantId: 'var-1', name: 'E2E Widget', sku: 'SKU-1', qty: 2, price: 20.0, lineTotal: 40.0)],
          discount: 0,
          tax: 0,
          subtotal: total,
          total: total,
          paymentMethod: 'cash',
          customerName: 'Walk-in',
          notes: '',
          status: status,
          createdAt: DateTime.now(),
        );
    final heldSale = sale('held-1', 'H-0001', 'held', 40.0);
    final paidSale = sale('sale-1', 'S-0042', 'completed', 40.0);
    final repricedSale = sale('sale-2', 'S-0043', 'completed', 25.0);

    final repo = MockPosRepository();
    final sellerRepo = MockSellerRepository();
    final subRepo = MockPosSubscriptionRepository();
    when(() => subRepo.getStatus(any())).thenAnswer((_) async => const PosSubscriptionStatusModel(status: PosSubscriptionStatusValue.active, enforced: true));
    when(() => sellerRepo.getStoreById(any())).thenAnswer((_) async => null);
    when(() => sellerRepo.getMyStores()).thenAnswer((_) async => []);
    when(() => repo.getPosSettings(any())).thenAnswer((_) async => const PosSettingsModel(storeId: 'store-1', taxRate: 0, currencySymbol: '\$'));
    when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'), categoryId: any(named: 'categoryId'))).thenAnswer((_) async => (items: [product], total: 1, totalPages: 1, hasMore: false));
    when(() => repo.getSessionReport(any())).thenAnswer((_) async => null);
    when(() => repo.getHeldSales(storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'))).thenAnswer((_) async => [heldSale]);
    when(() => repo.getSales(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          employeeId: any(named: 'employeeId'),
          paymentMethod: any(named: 'paymentMethod'),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          page: any(named: 'page'),
        )).thenAnswer((_) async => (items: <PosSaleModel>[], total: 0, totalPages: 1, hasMore: false));
    var quoteTotal = 40.0; // flipped to 25 for flow B
    when(() => repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion')))
        .thenAnswer((_) async => quoteTotal == 40.0
            ? (quote: null, message: null, code: null)
            : (quote: PosQuote(subtotal: quoteTotal, discount: 0, tax: 0, total: quoteTotal, taxRate: 0, currency: 'USD', currencyExponent: 2, settingsVersion: 7, unitPrices: {'var-1': 12.5}), message: null, code: null));
    final createCalls = <Map<Symbol, dynamic>>[];
    when(() => repo.createSale(
          storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), registerId: any(named: 'registerId'), employeeId: any(named: 'employeeId'),
          items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), clientTotal: any(named: 'clientTotal'),
          settingsVersion: any(named: 'settingsVersion'), clientCreatedAt: any(named: 'clientCreatedAt'), paymentMethod: any(named: 'paymentMethod'),
          payments: any(named: 'payments'), amountTendered: any(named: 'amountTendered'), paymentReference: any(named: 'paymentReference'),
          customerName: any(named: 'customerName'), customerId: any(named: 'customerId'), notes: any(named: 'notes'), status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        )).thenAnswer((inv) async {
      createCalls.add(Map.of(inv.namedArguments));
      final status = inv.namedArguments[#status] as String;
      if (status == 'held') return (success: true, sale: heldSale, message: null, queued: false);
      return (success: true, sale: quoteTotal == 40.0 ? paidSale : repricedSale, message: null, queued: false);
    });

    // pre-register the controllers with mocked repositories (the real ones would hit the real server with a fake token)
    // The new Home tab loads its numbers on shell entry: give it mocked repositories (a real one would send a seeded fake token to the server).
    final mockInventory = MockInventoryRepository();
    when(() => mockInventory.getLowStockSummary(any())).thenAnswer((_) async => null);
    when(() => mockInventory.getLowStockSummary(any())).thenAnswer((_) async => const LowStockSummary(count: 5, threshold: 10, items: []));
    when(() => repo.getSessionReport(any())).thenAnswer((_) async => PosSessionReportModel.fromJson({
          'session': {'_id': 'session-1', 'openedAt': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(), 'openingCash': 100, 'cashSales': 412.5, 'cardSales': 238.0},
          'summary': {'totalTransactions': 14, 'totalSales': 650.5, 'completedSales': 14, 'heldSales': 1, 'refundsCount': 1, 'byPaymentMethod': <String, dynamic>{}, 'cashFlow': <String, dynamic>{}},
        }));
    when(() => repo.getDailyReport(any())).thenAnswer((_) async => PosDailyReportModel.fromJson({
          'date': '2026-11-04', 'summary': {'totalTransactions': 126, 'netRevenue': 84260, 'avgTransactionValue': 669, 'totalRevenue': 84260},
        }));
    when(() => repo.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => PosRangeReportModel.fromJson({
          'from': '2026-10-29', 'to': '2026-11-04', 'summary': {'totalTransactions': 800, 'netRevenue': 428650, 'totalRevenue': 428650},
          'dailyBreakdown': [for (final e in [['2026-10-29', 42000.0], ['2026-10-30', 64000.0], ['2026-10-31', 51000.0], ['2026-11-01', 78000.0], ['2026-11-02', 57000.0], ['2026-11-03', 92000.0], ['2026-11-04', 84260.0]]) {'date': e[0], 'total': e[1]}],
        }));
    Get.lazyPut<PosHomeTabController>(() => PosHomeTabController(posRepository: repo, inventoryRepository: mockInventory), fenix: false);
    Get.lazyPut<PosHomeController>(() => PosHomeController(posRepository: repo), fenix: false);
    Get.lazyPut<PosHeldSalesController>(() => PosHeldSalesController(posRepository: repo), fenix: false);
    Get.lazyPut<PosOrdersController>(() => PosOrdersController(posRepository: repo), fenix: false);
    Get.lazyPut<PosProductsController>(() => PosProductsController(posRepository: repo), fenix: false);
    Get.lazyPut<PosSettingsController>(() => PosSettingsController(posRepository: repo, sellerRepository: sellerRepo, posSubscriptionRepository: subRepo), fenix: false);

    await pumpFor(tester, const Duration(seconds: 3));
    await pumpUntil(tester, () => Get.currentRoute != Routes.splashScreen, timeout: const Duration(seconds: 40), what: 'the splash to hand off');
    await pumpFor(tester, const Duration(seconds: 1));

    // sign in the till (seeded), then straight to the POS screen
    await AppPreferences.setTokens(accessToken: 'e2e-seed-token', refreshToken: 'e2e-seed-refresh');
    await AppPreferences.setUserRole('seller');
    await AppPreferences.saveStoreId('store-1');
    await AppPreferences.setHasSeenOnboarding(true);
    await AppPreferences.savePosEmployee(id: 'emp-1', name: 'E2E Manager', role: 'manager');
    await AppPreferences.savePosSession(sessionId: 'session-1', registerId: 'register-1', shiftId: 'shift-1');
    Get.offAllNamed(Routes.posHome);
    await pumpUntil(tester, () => Get.currentRoute == Routes.posHome, what: 'POS home');
    await pumpUntil(tester, () => Get.isRegistered<PosBottomNavController>(), what: 'the shell');
    Get.find<PosBottomNavController>().changeTab(PosBottomNavController.saleTab); // a manager lands on Home (G1a)
    await pumpFor(tester, const Duration(seconds: 6)); // let the "no internet" toast from the categories request come and go
    await pumpUntil(tester, () => find.byType(ProductTile).evaluate().isNotEmpty, what: 'the product grid');
    await pumpFor(tester, const Duration(seconds: 1));
    print('✅ On the sale screen');

    // ── the five-tab shell, per role ─────────────────────────────────────────────────────────────────────────
    final nav = Get.find<PosBottomNavController>();
    final homeTab = Get.find<PosHomeTabController>();
    Future<void> shot(String name) async {
      await pumpFor(tester, const Duration(milliseconds: 900));
      print('SHOT $name');
      await pumpFor(tester, const Duration(milliseconds: 1800));
    }

    nav.changeTab(PosBottomNavController.saleTab);
    await shot('sell');
    for (final role in ['manager', 'cashier']) {
      await AppPreferences.savePosEmployee(id: 'emp-1', name: role == 'manager' ? 'Mia Manager' : 'Cal Cashier', role: role);
      nav.changeTab(PosBottomNavController.homeTab);
      await homeTab.load();
      await shot('home_$role');
      nav.changeTab(PosBottomNavController.stockTab);
      await shot('stock_$role');
      nav.changeTab(PosBottomNavController.moreTab);
      await shot('more_$role');
      if (role == 'manager') {
        await tester.drag(find.byKey(const Key('moreHub')), const Offset(0, -520));
        await shot('more_manager_scrolled');
      }
    }

    // ── the design gallery ────────────────────────────────────────────────────────────────────────────────────
    Get.toNamed(Routes.designGallery);
    await pumpFor(tester, const Duration(seconds: 2));
    for (var i = 0; i < 4; i++) {
      await shot('gallery_$i');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -560));
    }
  });
}
