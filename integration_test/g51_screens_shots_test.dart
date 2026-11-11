// Screenshot pass for the G5.1 screens on the iOS simulator — mocked repositories, real rendering, light AND dark (phone): About, Help, Hardware check,
// clocking someone else (pick + PIN), a staff profile, the stock list by location, a supplier's products supplied.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/about_help_views.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_stock_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_profile_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/on_behalf_clock_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/staff_profile_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/g36_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

class _Printer extends Mock implements ThermalPrinterService {}

class _Queue extends PendingTeamSyncService {
  _Queue() : super(hasCredentials: () => false);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

PosEmployeeModel emp(String id, String name, String role) => PosEmployeeModel(id: id, storeId: 'st1', sellerId: 's', name: name, email: '$id@shop.pk', role: role, shiftIds: const [], status: 'active', createdAt: DateTime(2026));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;

    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('G5.1 phone ($tn)', (t) async {
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'PKR', exponent: 2);
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);

      await show(t, const AboutView(storeIdOverride: '6ae9a2e26106e636cc7cb4bb', receiptBaseOverride: 'https://api.solvexo.store/r/s/karachi-mart/'));
      await shot(t, 'g51_01_about', tn);
      await show(t, const HelpView());
      await t.tap(find.text('Offline'));
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'g51_02_help', tn);
      final pr = _Printer();
      when(() => pr.hasSavedPrinter).thenReturn(true);
      when(() => pr.savedPrinterName).thenReturn('XP-80C'.obs);
      when(() => pr.paperMm).thenReturn(80.obs);
      when(() => pr.printTest()).thenAnswer((_) async => null);
      await show(t, HardwareCheckView(printer: pr));
      await t.tap(find.byKey(const Key('hwTestPrint')));
      await t.enterText(find.byKey(const Key('hwScanBox')), '4006381333931');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await shot(t, 'g51_03_hardware_check', tn);

      // clocking someone else: pick, then the member's PIN
      final clock = TeamClockController(repository: repo, cache: testTeamCache(), queue: _Queue(), storeId: 'st1', employeeIdProvider: () async => 'e1', employeeNameProvider: () async => 'Bilal', employeeTokenProvider: () async => 't');
      final members = [emp('e2', 'Sana Tariq', 'cashier'), emp('e3', 'Imran Ali', 'manager'), emp('e4', 'Zara Khan', 'cashier')];
      await show(t, Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: OnBehalfClockSheet(controller: clock, repository: repo, members: members)))));
      await shot(t, 'g51_04_clock_someone_pick', tn);
      await t.tap(find.byKey(const Key('onBehalf_e2')));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'g51_05_clock_someone_pin', tn);

      when(() => repo.getStaffProfile('st1', 'e2')).thenAnswer(
        (_) async => StaffProfile.fromJson({
          'employeeId': 'e2', 'name': 'Sana Tariq', 'email': 'sana@shop.pk', 'role': 'cashier', 'lastLoginAt': '2026-11-11T04:02:00Z', 'state': {'clockedIn': true, 'since': '2026-11-11T04:05:00Z'},
          'currency': 'PKR', 'currencyExponent': 2,
          'sales': {'today': {'sales': 23, 'totalMinor': 4815000}, 'last7Days': {'sales': 141, 'totalMinor': 29870000}, 'last30Days': {'sales': 602, 'totalMinor': 127450000}},
        }),
      );
      await show(t, StaffProfileView(employeeId: 'e2', repository: repo, storeId: 'st1'));
      await shot(t, 'g51_06_staff_profile', tn);

      when(() => repo.getInventoryStock('st1', search: any(named: 'search'), filter: any(named: 'filter'), page: any(named: 'page'), limit: any(named: 'limit'), locationId: any(named: 'locationId'))).thenAnswer(
        (i) async => InvPage<InvRow>(
          items: [
            for (final (v, n, s, at) in [('v1', 'Basmati rice 5kg', 40, 12), ('v2', 'Cooking oil 1L', 64, 20), ('v3', 'Tea 950g', 18, 0)])
              InvRow(variantId: v, productId: 'p$v', productName: n, sku: v.toUpperCase(), stock: s, locationStock: i.namedArguments[#locationId] == null ? null : at, out: at == 0),
          ],
          total: 3,
          page: 1,
          hasMore: false,
          cur: const InvCur('PKR', 2),
        ),
      );
      final inv = InvStockListController(repository: repo, storeId: 'st1', locations: (_) async => [StoreLocationModel(id: 'l1', storeId: 'st1', sellerId: 's', name: 'Tariq Road', status: 'active', createdAt: DateTime(2026)), StoreLocationModel(id: 'l2', storeId: 'st1', sellerId: 's', name: 'Back store', status: 'active', createdAt: DateTime(2026))]);
      Get.put(inv, tag: 'inv_$tn');
      await show(t, InvStockListView(controller: inv, role: 'manager'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('invLoc_l2')));
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'g51_07_stock_by_location', tn);

      when(() => repo.getSupplier('st1', 's1')).thenAnswer(
        (_) async => SupplierProfile.fromJson({
          'currency': 'PKR', 'currencyExponent': 2,
          'supplier': {'id': 's1', 'name': 'Rice traders', 'phone': '0300 1234567', 'status': 'active'},
          'aging': {},
          'orders': [], 'receipts': [],
          'productsSupplied': [
            {'variantId': 'v1', 'name': 'Basmati rice 5kg', 'sku': 'RICE5', 'orderedQty': 120, 'receivedQty': 100, 'orders': 6, 'lastOrderedAt': '2026-11-08T06:00:00Z', 'lastUnitCostMinor': 142000},
            {'variantId': 'v4', 'name': 'Sella rice 10kg', 'sku': 'SELLA10', 'orderedQty': 40, 'receivedQty': 40, 'orders': 2, 'lastOrderedAt': '2026-10-30T06:00:00Z', 'lastUnitCostMinor': 268000},
          ],
        }),
      );
      when(() => repo.getSupplierLedger(any(), any())).thenAnswer((_) async => null);
      final sp = SupplierProfileController(supplierId: 's1', repository: repo, storeId: 'st1');
      Get.put(sp, tag: 's1_$tn');
      await show(t, SupplierProfileView(supplierId: 's1', controller: sp));
      await t.pump(const Duration(milliseconds: 400));
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await shot(t, 'g51_08_supplier_products_supplied', tn);
    });
  }
}
