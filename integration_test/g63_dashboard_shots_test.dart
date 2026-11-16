// G6.3 dashboard screenshots on the iOS simulator — mocked repositories, real rendering and fonts, light AND dark. The Home tab inside the real
// shell (bottom bar on a phone, rail on a tablet) in every state the brief names: owner with the register open and alerts, cashier, register
// closed, text scale 1.3, offline, and an older backend (release #2 features hidden). Run once per device (phone, tablet):
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g63_dashboard_shots_test.dart docs/pos-blueprint/g6_3_screenshots/<before|after>/<phone|tablet> x
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/data/services/server_capabilities.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/dashboard_alerts_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/fake_payments.dart';
import '../test/support/g36_fixtures.dart';
import '../test/support/sale_harness.dart';

class _Inv extends Mock implements InventoryRepository {}

class _Queue extends PendingTeamSyncService {
  _Queue() : super(hasCredentials: () => false);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

final _opened = DateTime.now().subtract(const Duration(hours: 3, minutes: 12)).toUtc().toIso8601String();

Map<String, dynamic> _session() => {
      'session': {'_id': 'session-1', 'storeId': 'st1', 'registerId': 'r1', 'employeeId': 'e1', 'openedAt': _opened, 'openingCash': 10000, 'status': 'open', 'cashSales': 31250, 'cardSales': 18400, 'currency': 'PKR', 'currencyExponent': 2},
      'summary': {'totalTransactions': 42, 'totalSales': 52890, 'completedSales': 41, 'heldSales': 1, 'refundsCount': 1, 'refundsTotal': 650, 'cashFlow': {'openingCash': 10000, 'cashSales': 31250, 'expectedCash': 41250}},
    };

Map<String, dynamic> _daily() => {
      'date': 'today',
      'summary': {'totalRevenue': 86120, 'netRevenue': 84260, 'totalTransactions': 126, 'avgTransactionValue': 669, 'refundsTotal': 1860, 'refundsCount': 3},
    };

Map<String, dynamic> _week() {
  final now = DateTime.now();
  const shape = [61200, 58400, 70300, 66800, 79100, 90250, 84260];
  return {
    'from': '', 'to': '',
    'summary': {'netRevenue': shape.fold<int>(0, (a, b) => a + b), 'totalTransactions': 812},
    'dailyBreakdown': [for (var i = 0; i < 7; i++) {'date': now.subtract(Duration(days: 6 - i)).toIso8601String().split('T').first, 'total': shape[i]}],
  };
}

Map<String, dynamic> _dash({String role = 'owner', bool shift = false}) => {
      'role': role,
      'scope': shift ? 'shift' : 'store',
      'currency': 'PKR',
      'currencyExponent': 2,
      'summary': {'totalRevenue': 86120, 'netRevenue': 84260, 'totalTransactions': 126, 'avgTransactionValue': 669, 'refundsTotal': 1860, 'refundsCount': 3},
      'byPaymentMethod': {'cash': {'count': 71, 'total': 46100}, 'card': {'count': 44, 'total': 30760}, 'other': {'count': 0, 'total': 0}, 'raast_qr': {'count': 11, 'total': 7400}},
      'topProducts': [
        {'productId': 'p1', 'name': 'Basmati rice 5kg', 'qty': 18, 'revenue': 25560},
        {'productId': 'p2', 'name': 'Cooking oil 1L', 'qty': 31, 'revenue': 17050},
        {'productId': 'p3', 'name': 'Tea 950g', 'qty': 12, 'revenue': 13200},
      ],
      'lowStock': shift ? null : {'count': 8, 'items': [{'name': 'Sugar 1kg', 'stock': 2}, {'name': 'Milk 1L', 'stock': 4}]},
      'shifts': [
        {'sessionId': 'session-1', 'employeeName': 'Sana Tariq', 'openedAt': _opened, 'totalSales': 52890, 'totalTransactions': 42},
      ],
      'needsAttention': shift ? null : {'salesNeedingReview': 1, 'digitalPayments': 1, 'total': 2},
      if (!shift) 'expiring': {'expiredLots': 1, 'expiringIn7Days': 2, 'expiringIn30Days': 5},
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 10; i++) {
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

    Future<void> home(
      WidgetTester t, {
      required PosAccess access,
      bool open = true,
      bool online = true,
      bool older = false,
      double textScale = 1,
      bool clockedIn = true,
    }) async {
      Get.reset();
      ServerCapabilities.resetForTest();
      if (older) ServerCapabilities.releaseTwo.value = false;
      final role = access == PosAccess.cashier ? 'cashier' : 'manager';
      SharedPreferences.setMockInitialValues({
        'store_id': 'st1',
        if (open) 'pos_session_id': 'session-1',
        'pos_employee_id': 'e1',
        'pos_employee_name': access == PosAccess.cashier ? 'Sana Tariq' : 'Atiq Rehman',
        'pos_employee_role': role,
      });
      await AppPreferences.warmCache();
      Money.configure(currency: 'PKR', exponent: 2);
      Get.lazyPut<PosSettingsController>(() => PosSettingsController()); // only for "Close shift" to show; never built here
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = online);
      final pos = MockPosRepository();
      final inv = _Inv();
      final pay = FakePaymentsRepo();
      when(() => pos.lastErrorCode).thenReturn(null);
      when(() => pos.getSessionReport(any())).thenAnswer((_) async => online && open ? PosSessionReportModel.fromJson(_session()) : null);
      when(() => pos.getDailyReport(any())).thenAnswer((_) async => online ? PosDailyReportModel.fromJson(_daily()) : null);
      when(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => online ? PosRangeReportModel.fromJson(_week()) : null);
      when(() => pos.getDashboard(any())).thenAnswer((_) async => online ? _dash(role: access == PosAccess.cashier ? 'cashier' : access.name, shift: access == PosAccess.cashier) : null);
      when(() => pos.getFiscalIssues(any())).thenAnswer((_) async => online
          ? [for (final n in ['INV-000231', 'INV-000236']) FiscalIssue.fromJson({'documentType': 'invoice', 'documentId': n, 'documentNumber': n, 'status': 'failed', 'attempts': 20, 'retryable': true})]
          : null);
      when(() => pos.getExpenses(any(), status: any(named: 'status'), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => online
          ? ExpenseList.fromJson({'currency': 'PKR', 'currencyExponent': 2, 'expenses': [{'id': 'x1', 'number': 'EXP-0019', 'category': 'utilities', 'amountMinor': 450000, 'status': 'recorded'}]})
          : null);
      when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => online ? const LowStockSummary(count: 8, threshold: 5, items: []) : null);
      pay.kyb = const PosKybStatus(state: PosKybState.verified, digitalPaymentsEnabled: true);
      if (online && access != PosAccess.cashier) {
        pay.attentionItems.add(PosAttentionItem(intentId: 'pi-1', reason: PosAttentionReason.paidAfterExpiry, amountMinor: 150000, currency: 'PKR', currencyExponent: 2, confirmedAt: DateTime.now()));
      }
      final cache = testTeamCache();
      await cache.saveMe('st1', me(clockedIn: clockedIn, since: DateTime.now().subtract(const Duration(hours: 3, minutes: 20))));
      when(() => pos.getTeamMe(any())).thenAnswer((_) async => online ? me(clockedIn: clockedIn, since: DateTime.now().subtract(const Duration(hours: 3, minutes: 20))) : null);
      when(() => pos.getAttendanceRecords(any(), from: any(named: 'from'), to: any(named: 'to'), employeeId: any(named: 'employeeId'))).thenAnswer((_) async => const []);
      when(() => pos.getAttendanceAnomalies(any())).thenAnswer((_) async => const []);
      Get.put<TeamClockController>(TeamClockController(repository: pos, cache: cache, queue: _Queue(), storeId: 'st1', employeeIdProvider: () async => 'e1', employeeNameProvider: () async => 'Atiq', employeeTokenProvider: () async => 't'));
      Get.put<DashboardAlertsController>(DashboardAlertsController(repository: pos, access: () async => access, storeId: () async => 'st1'));
      final c = PosHomeTabController(posRepository: pos, inventoryRepository: inv, paymentsRepository: pay, accessOverride: access);
      Get.put<PosHomeTabController>(c);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
            home: AppShell(
              destinations: const [
                AppDestination(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
                AppDestination(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale_rounded, label: 'Sell'),
                AppDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Orders'),
                AppDestination(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded, label: 'Stock'),
                AppDestination(icon: Icons.menu_rounded, selectedIcon: Icons.menu_open_rounded, label: 'More'),
              ],
              currentIndex: 0,
              onDestinationSelected: (_) {},
              railHeader: (_) => const BrandLogo(size: 40),
              body: PosHomeTabView(controller: c),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 800));
    }

    testWidgets('G6.3 dashboard ($tn)', (t) async {
      await home(t, access: PosAccess.owner);
      await shot(t, 'g63_dash_01_owner_open', tn);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await shot(t, 'g63_dash_02_owner_open_scrolled', tn);
      await home(t, access: PosAccess.cashier, clockedIn: false);
      await shot(t, 'g63_dash_03_cashier_open', tn);
      await home(t, access: PosAccess.manager, open: false);
      await shot(t, 'g63_dash_04_manager_register_closed', tn);
      await home(t, access: PosAccess.owner, textScale: 1.3);
      await shot(t, 'g63_dash_05_owner_text_1_3', tn);
      await home(t, access: PosAccess.manager, online: false);
      await shot(t, 'g63_dash_06_offline', tn);
      await home(t, access: PosAccess.owner, older: true);
      await shot(t, 'g63_dash_07_older_backend', tn);
    });
  }
}
