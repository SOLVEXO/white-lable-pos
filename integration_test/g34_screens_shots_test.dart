// Screenshot pass for the G3.4 supply screens on the iOS simulator (real rendering, real fonts, mocked repositories), light AND dark in one run.
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g34_screens_shots_test.dart <outdir> <suffix>
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/pay_supplier_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/payables_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_ledger_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/pay_supplier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/payables_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_form_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/receive_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_ledger_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_profile_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_return_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/g34_fixtures.dart';
import '../test/support/sale_harness.dart';

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
      return repo;
    }

    Future<void> sheet(WidgetTester t, Future<Object?> Function() open) async {
      await show(t, const Scaffold(body: SizedBox.shrink()));
      open();
      await t.pump(const Duration(milliseconds: 900));
    }

    final lotOrder = po(
      status: 'partially_received',
      editable: false,
      items: [
        poLineJson(received: 4, damaged: 1, trackLots: true, name: 'Dev Yogurt 500g (lots)'),
        poLineJson(id: 'li2', variantId: 'v2', name: 'Dev Mocha Syrup', ordered: 12, received: 12, unitCostMinor: 1200),
        poLineJson(id: 'li3', variantId: 'v3', name: 'Dev Oat Milk 1L', ordered: 6, unitCostMinor: 480),
      ],
    );
    PurchaseOrder cashierOrder() => po(
      costs: false,
      items: [
        poLineJson(costs: false, trackLots: true, name: 'Dev Yogurt 500g (lots)'),
        poLineJson(id: 'li3', variantId: 'v3', name: 'Dev Oat Milk 1L', ordered: 6, costs: false),
      ],
    );

    testWidgets('G3.4 suppliers ($tn)', (t) async {
      var repo = fresh();
      when(() => repo.getSuppliers('st1')).thenAnswer(
        (_) async => supplierList([supplier(), supplier(id: 's2', name: 'Fresh Farms Dairy', balance: 120000, open: 1), supplier(id: 's3', name: 'Paper & Packaging Co', balance: 0, open: 0)]),
      );
      await show(
        t,
        SupplierListView(
          controller: Get.put(SupplierListController(repository: repo, storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_01_suppliers_list', tn);

      repo = fresh();
      when(() => repo.getSupplier('st1', 's1')).thenAnswer((_) async => supplierProfile());
      await show(
        t,
        SupplierProfileView(
          supplierId: 's1',
          controller: Get.put(
            SupplierProfileController(supplierId: 's1', repository: repo, storeId: 'st1'),
            tag: 's1',
          ),
        ),
      );
      await shot(t, 'g34_02_supplier_profile_aging', tn);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(t, 'g34_02b_supplier_profile_orders_receipts', tn);
    });

    testWidgets('G3.4 purchase orders ($tn)', (t) async {
      var repo = fresh();
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer(
        (_) async => poList([
          poJson(),
          poJson(id: 'po2', number: 'PO-000002', status: 'draft'),
          poJson(id: 'po3', number: 'PO-000003', status: 'partially_received', editable: false, supplierName: 'Fresh Farms Dairy'),
          poJson(id: 'po4', number: 'PO-000004', status: 'received', editable: false),
        ]),
      );
      await show(
        t,
        PoListView(
          controller: Get.put(PoListController(repository: repo, cache: testSupplyCache(), storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_03_po_list_status_chips', tn);

      repo = fresh();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: lotOrder, cur: usd));
      await show(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: Get.put(
            PoDetailController(orderId: 'po1', repository: repo, storeId: 'st1'),
            tag: 'po1',
          ),
        ),
      );
      await shot(t, 'g34_04_po_detail_partially_received_manager', tn);

      repo = fresh();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: cashierOrder(), cur: usd));
      await show(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: Get.put(
            PoDetailController(orderId: 'po1', repository: repo, storeId: 'st1'),
            tag: 'po1',
          ),
        ),
      );
      await shot(t, 'g34_05_po_detail_cashier_no_money', tn);

      repo = fresh();
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson(costs: false)]));
      await show(
        t,
        PoListView(
          controller: Get.put(PoListController(repository: repo, cache: testSupplyCache(), storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_05b_po_list_cashier_no_money', tn);

      repo = fresh();
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()]));
      final form = Get.put(
        PoFormController(repository: repo, storeId: 'st1'),
        tag: 'po_new',
      );
      await show(t, PoFormView(controller: form));
      form.pickSupplier(supplier());
      form.addProduct(invRow(name: 'Dev Yogurt 500g (lots)'));
      form.addProduct(invRow(id: 'v3', name: 'Dev Oat Milk 1L', costMinor: 480));
      form.lines.last.qty.value = 6;
      form.expectedAt.value = DateTime(2026, 11, 20);
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'g34_06_new_po_form', tn);
    });

    testWidgets('G3.4 receiving ($tn)', (t) async {
      var repo = fresh();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: cashierOrder(), cur: usd));
      var recv = Get.put(
        ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1'),
        tag: 'recv_po1',
      );
      await show(t, ReceiveView(orderId: 'po1', controller: recv));
      recv.lines[0].good.value = 8;
      recv.lines[0].damaged.value = 2;
      recv.lines[0].expiry.value = DateTime(2027, 3, 9);
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.descendant(of: find.byKey(const Key('recvLot_li1')), matching: find.byType(TextField)), 'LOT-2611-A');
      recv.lines[1].good.value = 6;
      await shot(t, 'g34_07_receive_lot_tracked_line_filled', tn);

      repo = fresh();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: cashierOrder(), cur: usd));
      recv = Get.put(
        ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1'),
        tag: 'recv_po1',
      );
      await show(t, ReceiveView(orderId: 'po1', controller: recv));
      recv.result.value = ReceiveResult.fromJson({'currency': 'USD', 'currencyExponent': 2, 'receipt': receiptJson(costs: false, lot: 'LOT-2611-A'), 'order': null, 'duplicate': false});
      await shot(t, 'g34_08_receipt_success_cashier', tn);

      final rc = receipt(lot: 'LOT-2611-A');
      final ret = SupplierReturnController(receipt: rc, repository: repo, storeId: 'st1')..onInit();
      ret.lines.single.qty.value = 3;
      ret.lines.single.fromDamaged.value = true;
      ret.reason.value = 'damaged';
      await sheet(t, () => SupplierReturnSheet.open(controller: ret));
      await shot(t, 'g34_09_supplier_return_sheet', tn);

      final done = SupplierReturnController(receipt: rc, repository: repo, storeId: 'st1')..onInit();
      done.result.value = SupplierReturnResult(id: 'x', returnNumber: 'SR-000001', supplierName: 'Dev Supplies', reason: 'damaged', creditMinor: 750, cur: usd);
      await sheet(t, () => SupplierReturnSheet.open(controller: done));
      await shot(t, 'g34_09b_supplier_return_credit', tn);
    });

    testWidgets('G3.4 payables and paying ($tn)', (t) async {
      var repo = fresh();
      when(() => repo.getPayables('st1')).thenAnswer((_) async => payables());
      await show(
        t,
        PayablesView(
          controller: Get.put(PayablesController(repository: repo, storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_10_payables', tn);

      repo = fresh();
      when(() => repo.getSupplierLedger('st1', 's1')).thenAnswer((_) async => ledger());
      await show(
        t,
        SupplierLedgerView(
          supplierId: 's1',
          controller: Get.put(
            SupplierLedgerController(supplierId: 's1', repository: repo, storeId: 'st1'),
            tag: 's1',
          ),
        ),
      );
      await shot(t, 'g34_11_supplier_ledger', tn);

      final cash = PaySupplierController(supplierId: 's1', exponent: 2, balanceMinor: 5000, repository: repo, storeId: 'st1', sessionIdProvider: () async => 'sess1')..onInit();
      await t.pump(const Duration(milliseconds: 100));
      await sheet(t, () => PaySupplierSheet.open(supplierId: 's1', exponent: 2, currencyCode: 'USD', balanceMinor: 5000, controller: cash));
      await shot(t, 'g34_12_pay_supplier_cash', tn);
      await t.enterText(find.descendant(of: find.byKey(const Key('paAmount')), matching: find.byType(TextField)), '25.00');
      await shot(t, 'g34_12b_pay_supplier_cash_amount_typed', tn);

      final noShift = PaySupplierController(supplierId: 's1', exponent: 2, balanceMinor: 5000, repository: repo, storeId: 'st1', sessionIdProvider: () async => null)..onInit();
      await sheet(t, () => PaySupplierSheet.open(supplierId: 's1', exponent: 2, currencyCode: 'USD', balanceMinor: 5000, controller: noShift));
      await shot(t, 'g34_13_pay_supplier_open_a_shift', tn);
    });

    testWidgets('G3.4 offline ($tn)', (t) async {
      var repo = fresh();
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      await show(
        t,
        SupplierListView(
          controller: Get.put(SupplierListController(repository: repo, storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_14_offline_needs_internet', tn);

      repo = fresh();
      final cache = testSupplyCache();
      await cache.save('st1', poList([poJson(), poJson(id: 'po3', number: 'PO-000003', status: 'partially_received', editable: false, supplierName: 'Fresh Farms Dairy')]));
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      await show(
        t,
        PoListView(
          controller: Get.put(PoListController(repository: repo, cache: cache, storeId: 'st1')),
        ),
      );
      await shot(t, 'g34_15_offline_cached_po_list_read_only', tn);
    });
  }
}
