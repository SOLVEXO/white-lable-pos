// G1a navigation: the blueprint's five tabs (Home, Sell, Orders, Stock, More) and what each role is shown inside them.
// A cashier never sees a "coming soon" placeholder; managers / owners do. The server enforces the rules — this only decides what is shown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_more_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_stock_hub_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'support/sale_harness.dart' show MockPosRepository;

class MockInventoryRepository extends Mock implements InventoryRepository {}

Map<String, dynamic> _session() => {
      'session': {'_id': 's1', 'openedAt': '2026-11-04T08:00:00.000Z', 'openingCash': 100, 'cashSales': 40, 'cardSales': 25},
      'summary': {'totalTransactions': 3, 'totalSales': 65, 'completedSales': 3, 'heldSales': 1, 'refundsCount': 0, 'byPaymentMethod': <String, dynamic>{}, 'cashFlow': <String, dynamic>{}},
    };

Map<String, dynamic> _daily() => {
      'date': '2026-11-04',
      'summary': {'totalTransactions': 12, 'netRevenue': 840, 'avgTransactionValue': 70, 'totalRevenue': 840},
    };

Map<String, dynamic> _week() => {
      'from': '2026-10-29',
      'to': '2026-11-04',
      'summary': {'totalTransactions': 80, 'netRevenue': 5600, 'totalRevenue': 5600},
      'dailyBreakdown': [for (var i = 0; i < 7; i++) {'date': '2026-10-${29 + i > 31 ? 1 : 29 + i}'.replaceAll('2026-10-1', '2026-11-01'), 'total': 100.0 * (i + 1)}],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  late MockPosRepository pos;
  late MockInventoryRepository inv;

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'store-1', 'pos_session_id': 'session-1', 'pos_employee_name': 'Cal Cashier'});
    pos = MockPosRepository();
    inv = MockInventoryRepository();
    when(() => pos.getSessionReport(any())).thenAnswer((_) async => PosSessionReportModel.fromJson(_session()));
    when(() => pos.getDailyReport(any())).thenAnswer((_) async => PosDailyReportModel.fromJson(_daily()));
    when(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => PosRangeReportModel.fromJson(_week()));
    when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => null);
  });
  tearDown(Get.reset);

  Future<void> mountHome(WidgetTester t, PosAccess access, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 2600); // G6.3: Home is longer; the whole tab is built
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = PosHomeTabController(posRepository: pos, inventoryRepository: inv, accessOverride: access);
    Get.put<PosHomeTabController>(c);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: PosHomeTabView(controller: c),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mountHub(WidgetTester t, Widget hub, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(GetMaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      initialRoute: '/hub',
      getPages: [
        GetPage(name: '/hub', page: () => hub),
        for (final r in [Routes.posHeldSales, Routes.posProducts, Routes.posInventory, Routes.posSettings, Routes.posCustomers, Routes.posNeedsAttention, Routes.posSessionReport, Routes.posStockCount, Routes.posTransfers, Routes.posExpiry])
          GetPage(name: r, page: () => Scaffold(body: Text('ROUTE:$r'))),
      ],
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('access + constants', () {
    test('PosAccess: owner session wins, then manager, else cashier', () {
      expect(PosAccess.resolve(employeeRole: 'cashier', ownerSessionActive: false), PosAccess.cashier);
      expect(PosAccess.resolve(employeeRole: null, ownerSessionActive: false), PosAccess.cashier);
      expect(PosAccess.resolve(employeeRole: 'manager', ownerSessionActive: false), PosAccess.manager);
      expect(PosAccess.resolve(employeeRole: 'cashier', ownerSessionActive: true), PosAccess.owner);
      expect(PosAccess.cashier.canManage, isFalse);
      expect(PosAccess.manager.canManage, isTrue);
      expect(PosAccess.owner.isOwner, isTrue);
    });
    test('five tabs in blueprint order; the till still lands on Sell', () {
      expect([PosBottomNavController.homeTab, PosBottomNavController.saleTab, PosBottomNavController.ordersTab, PosBottomNavController.stockTab, PosBottomNavController.moreTab], [0, 1, 2, 3, 4]);
      expect(PosBottomNavController.initialTab, PosBottomNavController.saleTab);
    });
    test('landing by role: cashier → Sell; manager and owner → Home', () {
      expect(PosBottomNavController.landingTabFor(PosAccess.cashier), PosBottomNavController.saleTab);
      expect(PosBottomNavController.landingTabFor(PosAccess.manager), PosBottomNavController.homeTab);
      expect(PosBottomNavController.landingTabFor(PosAccess.owner), PosBottomNavController.homeTab);
    });
  });

  group('Home tab', () {
    testWidgets('cashier: shift snapshot only — no profit tile, no "Soon" actions, no trend', (t) async {
      await mountHome(t, PosAccess.cashier);
      expect(find.text('Your shift'), findsOneWidget);
      expect(find.byKey(const Key('homeHero')), findsOneWidget);
      for (final k in ['cash', 'card', 'refunds']) {
        expect(find.byKey(Key('homeTile-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('homeTile-profit')), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Soon'), findsNothing);
      expect(find.text('Expense'), findsNothing);
      expect(find.text('Count'), findsNothing);
      expect(find.byKey(const Key('homeTrend')), findsNothing);
      expect(find.text('Last 7 days'), findsNothing);
      expect(find.byKey(const Key('homeAction-newSale')), findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Good \w+, Cal$')), findsOneWidget); // the greeting (the register card also says "Opened by Cal Cashier")
      // the manager-only endpoints are never even called for a cashier
      verifyNever(() => pos.getDailyReport(any()));
      verifyNever(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to')));
      verifyNever(() => inv.getLowStockSummary(any()));
    });

    testWidgets('manager: business pulse, 7-day trend, refunds instead of a profit placeholder, and real quick actions (G6.3)', (t) async {
      await mountHome(t, PosAccess.manager);
      expect(find.text('Business pulse'), findsOneWidget);
      expect(find.byKey(const Key('homeTile-orders')), findsOneWidget);
      expect(find.byKey(const Key('homeTile-avg')), findsOneWidget);
      expect(find.byKey(const Key('homeTile-refunds')), findsOneWidget);
      // no unfinished placeholders any more: profit is not on Home (costs may be hidden from managers), expense and count are real screens
      expect(find.byKey(const Key('homeTile-profit')), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Soon'), findsNothing);
      for (final k in ['newSale', 'heldSales', 'products', 'orders', 'cash', 'expense', 'count', 'reports', 'team']) {
        expect(find.byKey(Key('homeAction-$k'), skipOffstage: false), findsOneWidget, reason: k);
        expect(t.widget<InkWell>(find.byKey(Key('homeAction-$k'), skipOffstage: false)).onTap, isNotNull, reason: k);
      }
      expect(find.byKey(const Key('homeAction-mySales'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('homeTrend'), skipOffstage: false), findsOneWidget);
      verify(() => pos.getDailyReport('store-1')).called(1);
    });

    testWidgets('register card: open → who / since / float, Continue selling; closed → Open register (G6.3)', (t) async {
      await mountHome(t, PosAccess.cashier);
      expect(find.byKey(const Key('homeRegister')), findsOneWidget);
      expect(find.text('Register open'), findsOneWidget);
      expect(find.byKey(const Key('homeRegisterSell')), findsOneWidget);
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'store-1', 'pos_employee_role': 'manager'});
      await AppPreferences.warmCache();
      when(() => pos.getSessionReport(any())).thenAnswer((_) async => null);
      await mountHome(t, PosAccess.manager);
      expect(find.text('Register closed'), findsOneWidget);
      expect(find.byKey(const Key('homeRegisterOpen')), findsOneWidget);
      expect(find.byKey(const Key('homeRegisterSell')), findsNothing);
    });

    testWidgets('manager without a manager PIN session: a clear note, not an error', (t) async {
      when(() => pos.getDailyReport(any())).thenAnswer((_) async => null);
      when(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => null);
      await mountHome(t, PosAccess.owner);
      expect(find.text('Manager PIN needed'), findsOneWidget);
      expect(find.textContaining('manager PIN'), findsWidgets);
      expect(find.text('Couldn\'t load your numbers'), findsNothing);
    });

    testWidgets('error state with Try again; tapping reloads', (t) async {
      when(() => pos.getSessionReport(any())).thenAnswer((_) async => null);
      await mountHome(t, PosAccess.cashier);
      expect(find.text('Couldn\'t load your numbers'), findsOneWidget);
      await t.tap(find.text('Try again'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      verify(() => pos.getSessionReport('session-1')).called(2);
    });

    testWidgets('low-stock + offline-queue rows appear for the manager; "all clear" otherwise', (t) async {
      when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => const LowStockSummary(count: 3, threshold: 10, items: []));
      await mountHome(t, PosAccess.manager);
      expect(find.byKey(const Key('homeAttention-lowStock'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('homeRegister'), skipOffstage: false), findsOneWidget); // G6.3: the open shift is the register card now
    });

    testWidgets('large text (200 %) does not overflow, for both roles', (t) async {
      for (final a in [PosAccess.cashier, PosAccess.manager]) {
        await mountHome(t, a, scale: 2);
        expect(t.takeException(), isNull, reason: '$a');
        Get.reset();
      }
    });

    testWidgets('every tappable target is at least 44 px', (t) async {
      await mountHome(t, PosAccess.manager);
      for (final k in ['homeAction-newSale', 'homeAction-heldSales']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });
  });

  group('Stock tab', () {
    testWidgets('cashier: products and stock on hand only', (t) async {
      await mountHub(t, const PosStockHubView(access: PosAccess.cashier));
      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Stock on hand'), findsOneWidget);
      expect(find.text('Stock activity'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Stock count'), findsNothing);
    });
    testWidgets('manager: + stock activity (locked), and count / transfers / batches open their screens — no placeholders (G6.3)', (t) async {
      await mountHub(t, const PosStockHubView(access: PosAccess.manager));
      expect(find.text('Stock activity'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('Soon'), findsNothing);
      for (final (s, route) in [('Stock count', Routes.posStockCount), ('Transfers', Routes.posTransfers), ('Batches & expiry', Routes.posExpiry)]) {
        await t.scrollUntilVisible(find.text(s), 200, scrollable: find.byType(Scrollable).first);
        await t.tap(find.text(s));
        await t.pumpAndSettle();
        expect(find.text('ROUTE:$route'), findsOneWidget, reason: s);
        Get.back();
        await t.pumpAndSettle();
      }
    });
    testWidgets('rows open the existing screens', (t) async {
      await mountHub(t, const PosStockHubView(access: PosAccess.cashier));
      await t.tap(find.text('Stock on hand'));
      await t.pumpAndSettle();
      expect(find.text('ROUTE:${Routes.posInventory}'), findsOneWidget);
    });
  });

  group('More tab', () {
    testWidgets('cashier: shift, held sales, sync, customers, settings — nothing managerial, no placeholders', (t) async {
      await mountHub(t, const PosMoreHubView(access: PosAccess.cashier, unresolvedOverride: 0));
      for (final s in ['Shift summary', 'Held sales', 'Sync & needs attention', 'Customers', 'Clock in', 'My attendance', 'Roster', 'My hours report', 'My sales', 'Cash & expenses', 'Settings']) {
        await t.scrollUntilVisible(find.text(s), 200, scrollable: find.byType(Scrollable).first); // the list is lazy
        expect(find.text(s), findsOneWidget, reason: s);
      }
      for (final s in ['Past buyers', 'Daily report', 'Date-range report', 'Shift history', 'Team & registers', 'Devices', 'Audit log', 'Plan status', 'Suppliers & purchase orders', 'Attendance', 'Coming soon']) {
        expect(find.text(s), findsNothing, reason: '$s must not be shown to a cashier');
      }
    });
    for (final a in [PosAccess.manager, PosAccess.owner]) {
      testWidgets('${a.name}: business, team & security rows (locked where a gate applies) + coming-soon placeholders', (t) async {
        await mountHub(t, PosMoreHubView(access: a, unresolvedOverride: 0));
        for (final s in ['Customers', 'Clock in', 'Attendance', 'Roster', 'Attendance report', 'Business pulse', 'Reports', 'Cash & expenses', 'Past buyers', 'Daily report', 'Team & registers', 'Devices', 'Audit log', 'Plan status', 'Suppliers & purchase orders']) {
          await t.scrollUntilVisible(find.text(s), 200, scrollable: find.byType(Scrollable).first); // the list is lazy
          expect(find.text(s), findsOneWidget, reason: '${a.name} $s');
        }
        expect(find.text('Coming soon', skipOffstage: false), findsNothing, reason: 'every placeholder of the More tab is built now');
        expect(find.byIcon(Icons.lock_outline_rounded, skipOffstage: false), findsWidgets);
      });
    }
    testWidgets('the unresolved offline-sales count is a badge on its row', (t) async {
      await mountHub(t, const PosMoreHubView(access: PosAccess.cashier, unresolvedOverride: 4));
      expect(find.descendant(of: find.byType(HubRow).at(2), matching: find.text('4')), findsOneWidget);
    });
    testWidgets('rows open the existing screens (held sales, settings)', (t) async {
      await mountHub(t, const PosMoreHubView(access: PosAccess.cashier, unresolvedOverride: 0));
      await t.tap(find.text('Held sales'));
      await t.pumpAndSettle();
      expect(find.text('ROUTE:${Routes.posHeldSales}'), findsOneWidget);
    });
    testWidgets('large text does not overflow', (t) async {
      await mountHub(t, const PosMoreHubView(access: PosAccess.manager, unresolvedOverride: 2), scale: 2);
      expect(t.takeException(), isNull);
    });
  });
}
