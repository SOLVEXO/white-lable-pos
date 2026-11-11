// Screenshot pass for the G4.8 screens on the iOS simulator — mocked repositories, real rendering, light AND dark (phone): the security screen with
// the two new switches, "costs hidden" on the profit report / inventory / payables, the receipt designer (only the logo not printed), CSV import
// from a file, the price-book editor in store days, and the manager-PIN prompt for a reprint.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/csv_import_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/price_books_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_overview_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/payables_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/payables_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/g40_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(const ReportQuery(from: '', to: ''));
  registerFallbackValue(ReportKind.profit);

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
      await t.pumpWidget(const SizedBox()); // a second GetMaterialApp in one test needs an empty frame first
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    _Repo fresh() {
      Get.reset();
      StoreDay.forget();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'PKR', exponent: 2);
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(today: '2026-11-11'));
      when(() => repo.getEmployees('st1')).thenAnswer((_) async => []);
      when(() => repo.listRegisters('st1')).thenAnswer((_) async => []);
      return repo;
    }

    T put<T>(T c) => Get.put(c, tag: '${T}_${DateTime.now().microsecondsSinceEpoch}');

    testWidgets('G4.8 phone ($tn)', (t) async {
      // security: the two new switches (owner edits)
      var repo = fresh();
      when(() => repo.getStoreSettings('st1')).thenAnswer(
        (_) async => StoreSettings.fromJson({
          'receipt': {'showQr': true, 'showBarcode': true, 'showLoyaltyBalance': true, 'defaultPaperWidth': 80, 'footer': 'Exchange within 7 days with receipt', 'promoText': '10% off on Fridays'},
          'security': {'autoLockMinutes': 5, 'lockOnBackground': true, 'requirePinForReprint': true, 'hideCostsFromManagers': true},
          'profile': {'businessName': 'Karachi Mart', 'businessAddress': 'Shop 12, Tariq Road, Karachi', 'businessTaxId': '7654321-0'},
          'timeZone': 'Asia/Karachi',
          'canEdit': true,
        }),
      );
      final st = put(StoreSettingsController(repository: repo, storeId: 'st1', applyLock: (_, __) async {}));
      await show(t, SecuritySettingsView(controller: st));
      await t.drag(find.byType(ListView).first, const Offset(0, -400));
      await shot(t, 'g48_01_security_reprint_costs', tn);
      await show(t, ReceiptDesignerView(controller: st));
      await t.drag(find.byType(ListView).first, const Offset(0, -900));
      await shot(t, 'g48_02_receipt_designer_switches', tn);

      // costs hidden: profit report, inventory overview, payables
      repo = fresh();
      final j = profitJson()..['costsHidden'] = true;
      (j['totals'] as Map).removeWhere((k, _) => ['costOfGoodsSoldMinor', 'grossMarginMinor', 'marginPercent', 'afterExpensesMinor', 'costCoveragePercent', 'costUnknownNetMinor', 'supplierPaymentsMinor', 'supplierPaymentsNote'].contains(k));
      when(() => repo.getBizReport('st1', any(), any(), sort: any(named: 'sort'), limit: any(named: 'limit'))).thenAnswer((_) async => parseBizReport(ReportKind.profit, j));
      await show(t, ReportView(kind: ReportKind.profit, controller: put(ReportController(kind: ReportKind.profit, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 11, 12), canManage: true, storeName: () async => 'Karachi Mart'))));
      await shot(t, 'g48_03_profit_costs_hidden', tn);
      when(() => repo.getInventoryOverview(any())).thenAnswer(
        (_) async => InvOverview.fromJson({'role': 'manager', 'skuCount': 148, 'lowStockCount': 6, 'outOfStockCount': 2, 'expiredLots': 1, 'expiringIn7Days': 3, 'expiringIn30Days': 7, 'currency': 'PKR', 'currencyExponent': 2, 'costsHidden': true}),
      );
      await show(t, InvOverviewView(controller: Get.put(InvOverviewController(repository: repo, storeId: 'st1'))));
      await shot(t, 'g48_04_inventory_costs_hidden', tn);
      when(() => repo.getPayables('st1')).thenAnswer(
        (_) async => Payables.fromJson({
          'currency': 'PKR',
          'currencyExponent': 2,
          'costsHidden': true,
          'totals': {},
          'suppliers': [
            for (final (i, n) in [(1, 'Rice traders'), (2, 'Dairy fresh'), (3, 'Karachi oil mills')]) {'supplierId': 's$i', 'supplierName': n},
          ],
        }),
      );
      await show(t, PayablesView(controller: put(PayablesController(repository: repo, storeId: 'st1'))));
      await shot(t, 'g48_05_payables_costs_hidden', tn);

      // CSV import from a file
      repo = fresh();
      final imp = put(CsvImportController(repository: repo, storeId: 'st1', filePicker: () async => (name: 'products-november.csv', text: 'name,price,sku\nBasmati rice 5kg,1500,RICE5\nCooking oil 1L,620,OIL1\n', rows: 2)));
      await show(t, CsvImportView(controller: imp));
      await t.tap(find.byKey(const Key('importPick')));
      await shot(t, 'g48_06_csv_import_from_file', tn);

      // price book editor in store days
      repo = fresh();
      when(() => repo.getPriceBooks('st1')).thenAnswer(
        (_) async => PriceBooks.fromJson({
          'currency': 'PKR',
          'currencyExponent': 2,
          'books': [
            {'id': 'eid', 'name': 'Eid offer', 'active': true, 'inForce': false, 'validFromUtc': '2027-03-28T19:00:00Z', 'validToUtc': '2027-04-02T19:00:00Z', 'validFromDay': '2027-03-29', 'validToDay': '2027-04-02', 'timeZone': 'Asia/Karachi', 'entries': []},
          ],
        }),
      );
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => (items: <PosProductModel>[], total: 0, totalPages: 1, hasMore: false));
      final books = put(PriceBooksController(repository: repo, storeId: 'st1', clock: () => DateTime.utc(2026, 11, 11, 12)));
      await show(t, PriceBooksView(controller: books));
      await shot(t, 'g48_07_price_books_store_days', tn);

      // a cashier's reprint in a store that requires a manager PIN
      repo = fresh();
      await show(t, Scaffold(body: Align(alignment: Alignment.bottomCenter, child: ManagerApprovalSheet(reason: 'This store needs a manager to approve reprints.', repository: repo))));
      await shot(t, 'g48_08_reprint_manager_pin', tn);
    });
  }
}
