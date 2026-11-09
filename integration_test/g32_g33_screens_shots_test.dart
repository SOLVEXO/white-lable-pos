// Screenshot pass for the G3.2 / G3.3 screens on the iOS simulator (real rendering, real fonts, mocked repositories), light AND dark in one run.
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g32_g33_screens_shots_test.dart <outdir> <suffix>
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_picker_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_profile_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/payment_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_stock_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_complete_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/g33_returns_test.dart' show creditSale;
import '../test/support/g3_fixtures.dart';
import '../test/support/inventory_fixtures.dart';
import '../test/support/sale_harness.dart';

PosProductModel _yogurt() => PosProductModel(
  productId: 'p',
  name: 'Dev Yogurt (lots)',
  type: 'physical',
  categoryId: 'c',
  variants: [PosProductVariant(variantId: 'p_v', sku: 'DEV-YOGURT', price: 4, stock: 12, isDefault: true)],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;

    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: w),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
    }

    MockPosRepository fresh() {
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'USD', exponent: 2);
      final repo = MockPosRepository();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.lastErrorReasons).thenReturn(const []);
      when(() => repo.getCustomerProfile(any(), any())).thenAnswer((_) async => null);
      when(
        () => repo.getCustomerConfig(any()),
      ).thenAnswer((_) async => const CustomerConfig(cur: usd, storeCreditTenderEnabled: true, loyalty: LoyaltyRules(enabled: true, earnSpendMinor: 1000, redeemMinorPerPoint: 50)));
      return repo;
    }

    PosHomeController home(MockPosRepository repo, {int qty = 6}) {
      final c = PosHomeController(posRepository: repo, approval: ({required String reason, repository}) async => null);
      c.storeId.value = 'st1';
      c.sessionId.value = 'se';
      final p = _yogurt();
      final item = CartItem(product: p, variant: p.variants.first, qty: qty);
      item.lotPreviewLive.value = true;
      item.lotPreview.value = LotPreview(
        variantId: 'p_v',
        trackLots: true,
        qty: qty,
        shortBy: qty > 6 ? 2 : 0,
        expiredUnits: 4,
        allocations: const [
          LotAllocation(lotId: 'a', lotNumber: 'LOT-SOON', take: 5, daysLeft: 3),
          LotAllocation(lotId: 'b', lotNumber: 'LOT-LATER', take: 1, daysLeft: 25),
        ],
        asOf: DateTime.now(),
      );
      c.cartItems.add(item);
      return c;
    }

    testWidgets('G3.2 cart + expiring ($tn)', (t) async {
      var repo = fresh();
      var c = home(repo);
      await show(
        t,
        Scaffold(
          body: SafeArea(child: CartPanel(c: c)),
        ),
      );
      await shot(t, 'g32_01_cart_lot_expiring_badge', tn);

      repo = fresh();
      c = home(repo, qty: 8);
      await show(
        t,
        Scaffold(
          body: SafeArea(child: CartPanel(c: c)),
        ),
      );
      await shot(t, 'g32_02_cart_sell_expired_action', tn);
      c.approveSellExpired(c.cartItems.first); // opens the manager PIN sheet
      await t.pump(const Duration(milliseconds: 800));
      await shot(t, 'g32_03_expired_manager_approval_sheet', tn);

      repo = fresh();
      when(
        () => repo.getInventoryStock(
          any(),
          search: any(named: 'search'),
          filter: any(named: 'filter'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => rowsPage([
          InvRow.fromJson({
            ...rowJson(id: 'y', name: 'Dev Yogurt (lots)', stock: 12, trackLots: true),
            'expiredUnits': 4,
            'nextExpiryAt': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
          }),
          InvRow.fromJson({...rowJson(id: 'm', name: 'Fresh milk 1L', stock: 9, trackLots: true), 'expiredUnits': 0, 'nextExpiryAt': DateTime.now().add(const Duration(days: 20)).toIso8601String()}),
        ]),
      );
      await show(
        t,
        InvStockListView(
          controller: Get.put(
            InvStockListController(repository: repo, storeId: 's1', initialFilter: 'expiring'),
            tag: 'shot',
          ),
        ),
      );
      await shot(t, 'g32_04_stock_expiring_chip_rows', tn);
    });

    testWidgets('G3.3 customers ($tn)', (t) async {
      var repo = fresh();
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer(
        (_) async => customerPage([
          customer(),
          customer(id: 'c2', name: 'Amina Khan', phone: '03004445555', credit: 0, points: 120, tier: 'silver'),
          customer(id: 'c3', name: 'Walk-in regular', phone: null, credit: 550, points: 0, tier: null),
        ]),
      );
      await show(
        t,
        CustomerListView(
          controller: Get.put(CustomerListController(repository: repo, cache: testCustomerCache(), storeId: 'st1')),
        ),
      );
      await shot(t, 'g33_01_customers_list', tn);

      repo = fresh();
      SharedPreferences.setMockInitialValues({'store_id': 'st1', 'pos_employee_role': 'manager'});
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile(lifetime: 123400));
      when(() => repo.getCustomerCredit('st1', 'c1')).thenAnswer(
        (_) async => CreditLedgerPage(
          enabled: true,
          cur: usd,
          items: [
            creditEntry(),
            creditEntry(id: 'e2', amount: -500, balance: 1500, type: 'spend'),
          ],
        ),
      );
      await show(
        t,
        CustomerProfileView(
          customerId: 'c1',
          controller: Get.put(
            CustomerProfileController(customerId: 'c1', repository: repo, cache: testCustomerCache(), storeId: 'st1'),
            tag: 'm',
          ),
        ),
      );
      await shot(t, 'g33_02_profile_manager', tn);

      repo = fresh();
      when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile());
      await show(
        t,
        CustomerProfileView(
          customerId: 'c1',
          controller: Get.put(
            CustomerProfileController(customerId: 'c1', repository: repo, cache: testCustomerCache(), storeId: 'st1'),
            tag: 'c',
          ),
        ),
      );
      await shot(t, 'g33_03_profile_cashier', tn);

      await show(t, const Scaffold(body: SizedBox.shrink()));
      CustomerFormSheet.open();
      await t.pump(const Duration(milliseconds: 800));
      await shot(t, 'g33_04_add_customer_sheet', tn);

      repo = fresh();
      when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer(), customer(id: 'c2', name: 'Amina Khan', phone: '03004445555', credit: 0, points: 120)]));
      await show(t, const Scaffold(body: SizedBox.shrink()));
      CustomerPickerSheet.open();
      await t.pump(const Duration(milliseconds: 900));
      await shot(t, 'g33_05_picker_with_add_customer', tn);
    });

    testWidgets('G3.3 payment, success, returns ($tn)', (t) async {
      var repo = fresh();
      var c = home(repo, qty: 5);
      c.cartItems.first.lotPreview.value = null;
      c.saleCustomer.attach(customer(), usd);
      await c.saleCustomer.refresh();
      c.setRedeemPoints(10);
      await show(t, const Scaffold(body: SizedBox.shrink()));
      PaymentSheet.open(c);
      await t.pump(const Duration(milliseconds: 900));
      await shot(t, 'g33_06_payment_store_credit_and_points', tn);

      repo = fresh();
      c = home(repo);
      c.lastOutcome.value = SaleOutcome.completed;
      c.lastSale.value = PosSaleModel.fromJson({
        '_id': 's1',
        'saleNumber': 'S-1',
        'storeId': 'st1',
        'sessionId': 'se',
        'registerId': 'r',
        'employeeId': 'e',
        'items': [],
        'discount': 5.0,
        'tax': 0,
        'subtotal': 20.0,
        'total': 15.0,
        'paymentMethod': 'split',
        'customerName': 'Dev',
        'notes': '',
        'status': 'completed',
        'createdAt': '2026-11-09T10:00:00.000Z',
        'currency': 'USD',
        'currencyExponent': 2,
        'payments': [
          {'method': 'store_credit', 'amount': 8.0},
          {'method': 'cash', 'amount': 7.0},
        ],
        'loyalty': {'earnedPoints': 1, 'redeemedPoints': 10, 'redeemValueMinor': 500},
      });
      await show(t, SaleSuccessView(c: c, repository: repo));
      await shot(t, 'g33_07_sale_success_with_points', tn);

      repo = fresh();
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => creditSale());
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => profile(credit: 2500));
      final r = PosReturnController(repository: repo, saleId: 'sale-1');
      Get.put(r);
      await show(t, PosReturnView(controller: r));
      r.setQty('i1', 1);
      r.setRefundTo('store_credit');
      await shot(t, 'g33_08_return_refund_to_choice', tn);

      final done = PosReturnController(repository: repo, saleId: 'sale-1');
      done.sale.value = creditSale();
      done.resultAmount = 5;
      done.resultCreditText.value = '\$5.00';
      done.resultBalanceText.value = '\$25.00';
      done.result.value = {'number': 'CN-000001'};
      done.resultInstructions.assignAll(["Add \$5.00 to the customer's store credit"]);
      await show(t, PosReturnCompleteView(c: done));
      await shot(t, 'g33_09_return_done_to_store_credit', tn);
    });
  }
}
