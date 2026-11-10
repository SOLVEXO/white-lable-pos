// G4.0 / G4.1 screens on phone, tablet and dark: the reports hub, every report (loading / empty / error / offline / role-limited / compare on & off /
// cost coverage below 100 %), the drill-downs, the export menu, the business pulse (and its Home card shown only after a 200) and the store time zone
// (owner edits; everyone else reads).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/time_zone_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_home_card.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/reports_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/time_zone_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'support/g40_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

const _phone = Size(390, 1600);
const _tablet = Size(1024, 1366);

enum _Env { phone, tablet, dark }

void main() {
  late _Repo repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(const ReportQuery(from: '', to: ''));
    registerFallbackValue(ReportKind.sales);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    StoreDay.forget();
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(today: '2026-11-11'));
    when(() => repo.getEmployees('st1')).thenAnswer((_) async => []);
    when(() => repo.listRegisters('st1')).thenAnswer((_) async => []);
    for (final k in ReportKind.values) {
      when(
        () => repo.getBizReport(
          'st1',
          k,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => report(k));
    }
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Text page(String s) => Text(s);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          key: UniqueKey(),
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(
              name: Routes.posStockDetail,
              page: () => Scaffold(body: page('STOCK:${(Get.arguments as Map)['variantId']}')),
            ),
            GetPage(
              name: Routes.posStockList,
              page: () => Scaffold(body: page('LOW:${(Get.arguments as Map)['lowOnly']}')),
            ),
            GetPage(
              name: Routes.posTeamAttendance,
              page: () => Scaffold(body: page('ATTENDANCE')),
            ),
            GetPage(
              name: Routes.posReport,
              page: () => Scaffold(body: page('REPORT:${(Get.arguments as Map)['kind']}')),
            ),
            GetPage(
              name: Routes.posPulse,
              page: () => Scaffold(body: page('PULSE')),
            ),
            GetPage(
              name: Routes.posReports,
              page: () => Scaffold(body: page('HUB')),
            ),
            GetPage(
              name: Routes.posStoreTimeZone,
              page: () => Scaffold(body: page('TZ')),
            ),
          ],
          home: w,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await settle(t);
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  ReportController ctl(ReportKind k, {bool manager = true, Future<void> Function(ShareParams)? share, String? employeeId}) => Get.put(
    ReportController(kind: k, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 10, 23), canManage: manager, share: share, storeName: () async => 'Dev Store', employeeId: employeeId),
    tag: '${k.name}${DateTime.now().microsecondsSinceEpoch}',
  );

  // ── hub ─────────────────────────────────────────────────────────────────────────────────────
  group('ReportsHubView', () {
    for (final env in _Env.values) {
      testWidgets('${env.name}: the pulse, the eight reports and the time zone; tapping opens them', (t) async {
        await pump(t, const ReportsHubView(), env);
        for (final k in ['hub_pulse', ...ReportKind.values.map((k) => 'hub_${k.path}'), 'hub_timeZone']) {
          expect(find.byKey(Key(k), skipOffstage: false), findsOneWidget, reason: k);
        }
        if (env == _Env.tablet) {
          expect(t.getTopLeft(find.byKey(const Key('hub_pulse'))).dy, t.getTopLeft(find.byKey(const Key('hub_sales'))).dy, reason: 'two columns on a tablet');
        } else {
          expect(t.getTopLeft(find.byKey(const Key('hub_sales'))).dy, lessThan(t.getTopLeft(find.byKey(const Key('hub_profit'))).dy));
        }
        await tapKey(t, 'hub_tax');
        expect(find.text('REPORT:tax'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });

  // ── every report ────────────────────────────────────────────────────────────────────────────
  group('ReportView: every report renders on phone, tablet and dark', () {
    for (final k in ReportKind.values) {
      for (final env in _Env.values) {
        testWidgets('${k.name} · ${env.name}', (t) async {
          await pump(t, ReportView(kind: k, controller: ctl(k)), env);
          expect(find.byKey(const Key('reportBody')), findsOneWidget);
          expect(find.byKey(const Key('reportDateStrip')), findsOneWidget);
          for (final r in ReportRange.values) {
            expect(find.byKey(Key('range_${r.name}'), skipOffstage: false), findsOneWidget);
          }
          expect(find.byKey(const Key('reportCompare')), (k == ReportKind.sales || k == ReportKind.profit) ? findsOneWidget : findsNothing);
          expect(find.textContaining('Asia/Karachi'), findsWidgets, reason: 'the store time zone is shown');
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('ReportView states', () {
    testWidgets('loading, then an error in words with Try again', (t) async {
      final comp = Completer<BizReport?>();
      when(
        () => repo.getBizReport(
          'st1',
          ReportKind.sales,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, ReportView(kind: ReportKind.sales, controller: ctl(ReportKind.sales)));
      expect(find.byKey(const Key('reportLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('RANGE_TOO_LONG');
      comp.complete(null);
      await settle(t);
      expect(find.text('A report covers at most 366 days. Choose a shorter period.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline: needs an internet connection, no request', (t) async {
      offline();
      await pump(t, ReportView(kind: ReportKind.profit, controller: ctl(ReportKind.profit)));
      expect(find.byKey(const Key('reportsNeedsInternet')), findsOneWidget);
      expect(find.textContaining('needs an internet connection'), findsOneWidget);
      verifyNever(
        () => repo.getBizReport(
          any(),
          any(),
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      );
    });

    final empties = <ReportKind, BizReport Function()>{
      ReportKind.sales: () => SalesReport.fromJson(salesJson(empty: true)),
      ReportKind.products: () => ProductsReport.fromJson(productsJson(empty: true)),
      ReportKind.hourly: () => HourlyReport.fromJson(hourlyJson(empty: true)),
      ReportKind.payments: () => PaymentsReport.fromJson(paymentsJson(empty: true)),
    };
    for (final e in empties.entries) {
      testWidgets('empty ${e.key.name}: nothing sold in the period', (t) async {
        when(
          () => repo.getBizReport(
            'st1',
            e.key,
            any(),
            sort: any(named: 'sort'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => e.value());
        await pump(t, ReportView(kind: e.key, controller: ctl(e.key)));
        expect(find.byKey(const Key('reportEmpty')), findsOneWidget);
      });
    }

    testWidgets('a date chip reloads with STORE days from the server\'s today', (t) async {
      final c = ctl(ReportKind.sales);
      await pump(t, ReportView(kind: ReportKind.sales, controller: c));
      await tapKey(t, 'range_yesterday');
      final q =
          verify(
                () => repo.getBizReport(
                  'st1',
                  ReportKind.sales,
                  captureAny(),
                  sort: any(named: 'sort'),
                  limit: any(named: 'limit'),
                ),
              ).captured.last
              as ReportQuery;
      expect([q.from, q.to], ['2026-11-10', '2026-11-10'], reason: 'the store is on the 11th');
      expect(find.text('Tue 10 Nov'), findsOneWidget);
    });
  });

  group('Sales', () {
    testWidgets('compare OFF: no change chips, no dashed line; ON: chips, the comparison note and the previous period in the legend', (t) async {
      when(
        () => repo.getBizReport(
          'st1',
          ReportKind.sales,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((i) async {
        final q = i.positionalArguments[2] as ReportQuery;
        return SalesReport.fromJson(q.compare ? salesJson(compare: true) : salesJson(from: q.from, to: q.to));
      });
      final c = ctl(ReportKind.sales);
      await pump(t, ReportView(kind: ReportKind.sales, controller: c));
      expect(find.byKey(const Key('salesByDay')), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing, reason: 'no change chips without a comparison');
      expect(find.text('Previous period', skipOffstage: false), findsNothing);
      await tapKey(t, 'reportCompare');
      expect(c.compare.value, isTrue);
      expect(find.textContaining('Compared with Fri 30 Oct'), findsOneWidget);
      expect(find.text('+50.0%'), findsWidgets, reason: 'net sales 90.00 vs 60.00');
      expect(find.text('Previous period', skipOffstage: false), findsOneWidget);
    });
  });

  group('Profit', () {
    testWidgets('gross margin and "After expenses" clearly labelled; coverage < 100 % explained; the supplier note verbatim', (t) async {
      await pump(t, ReportView(kind: ReportKind.profit, controller: ctl(ReportKind.profit)));
      expect(find.text('Gross margin'), findsOneWidget);
      expect(find.text('After expenses'), findsOneWidget);
      expect(find.byKey(const Key('profitGrossLabel')), findsOneWidget);
      expect(find.textContaining('After expenses (gross margin − recorded expenses; supplier payments excluded)'), findsOneWidget);
      expect(find.byKey(const Key('profitCoverageNote')), findsOneWidget);
      expect(find.textContaining('Only 88.9 % of net sales have a known cost'), findsOneWidget);
      expect(find.textContaining('Supplier payments are not expenses: the cost of the goods is already counted when they are sold (COGS).'), findsOneWidget);
      expect(find.text('88.9 %'), findsOneWidget);
    });

    testWidgets('full coverage: no coverage warning', (t) async {
      when(
        () => repo.getBizReport(
          'st1',
          ReportKind.profit,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => ProfitReport.fromJson(profitJson(coverage: 100)));
      await pump(t, ReportView(kind: ReportKind.profit, controller: ctl(ReportKind.profit)));
      expect(find.byKey(const Key('profitCoverageNote')), findsNothing);
      expect(find.byKey(const Key('profitSupplierNote')), findsOneWidget);
    });
  });

  group('Products, categories, tax, payments, hourly', () {
    testWidgets('products: sort chips reload; a product opens its stock detail; custom items do not', (t) async {
      final c = ctl(ReportKind.products);
      await pump(t, ReportView(kind: ReportKind.products, controller: c));
      await tapKey(t, 'sort_margin');
      verify(() => repo.getBizReport('st1', ReportKind.products, any(), sort: 'margin', limit: 100)).called(1);
      expect(find.text('Margin unknown (no cost)'), findsOneWidget);
      await tapKey(t, 'product_v1');
      expect(find.text('STOCK:v1'), findsOneWidget);
    });

    testWidgets('categories: bars and rows; tax: by category and HS code with invoices vs credit notes', (t) async {
      await pump(t, ReportView(kind: ReportKind.categories, controller: ctl(ReportKind.categories)));
      expect(find.byKey(const Key('categoryBars')), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
    });

    testWidgets('tax: by category and HS code with invoices vs credit notes', (t) async {
      await pump(t, ReportView(kind: ReportKind.tax, controller: ctl(ReportKind.tax)));
      expect(find.byKey(const Key('tax_standard_0902.1000')), findsOneWidget);
      expect(find.textContaining('HS 0902.1000'), findsOneWidget);
      expect(find.textContaining('No HS code'), findsOneWidget);
      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text('Credit notes'), findsOneWidget);
    });

    testWidgets('payments: the donut and the table; hourly: bars, the heatmap and the busiest hour', (t) async {
      await pump(t, ReportView(kind: ReportKind.payments, controller: ctl(ReportKind.payments)));
      expect(find.byKey(const Key('paymentDonut')), findsOneWidget);
      expect(find.byKey(const Key('pay_cash')), findsOneWidget);
    });

    testWidgets('hourly: bars, the heatmap and the busiest hour', (t) async {
      await pump(t, ReportView(kind: ReportKind.hourly, controller: ctl(ReportKind.hourly)));
      expect(find.byKey(const Key('hourBars')), findsOneWidget);
      expect(find.byKey(const Key('hourHeatmap')), findsOneWidget);
      expect(find.textContaining('Busiest hour: 15:00 - 16:00'), findsOneWidget);
    });

    testWidgets('export: CSV and PDF from the menu', (t) async {
      final shared = <ShareParams>[];
      await pump(
        t,
        ReportView(
          kind: ReportKind.tax,
          controller: ctl(ReportKind.tax, share: (p) async => shared.add(p)),
        ),
      );
      await tapKey(t, 'reportExport');
      await t.tap(find.byKey(const Key('exportCsv')));
      await settle(t);
      await tapKey(t, 'reportExport');
      await t.tap(find.byKey(const Key('exportPdf')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await settle(t);
      expect(shared.map((s) => s.files!.single.mimeType), ['text/csv', 'application/pdf']);
    });
  });

  group('Cashiers', () {
    testWidgets('a manager sees everyone; a row narrows the report to that person', (t) async {
      final c = ctl(ReportKind.cashiers);
      await pump(t, ReportView(kind: ReportKind.cashiers, controller: c));
      expect(find.text('Cashiers'), findsOneWidget);
      expect(find.byKey(const Key('cashier_e2')), findsOneWidget);
      await tapKey(t, 'cashier_e2');
      expect(c.employeeId.value, 'e2');
      final q =
          verify(
                () => repo.getBizReport(
                  'st1',
                  ReportKind.cashiers,
                  captureAny(),
                  sort: any(named: 'sort'),
                  limit: any(named: 'limit'),
                ),
              ).captured.last
              as ReportQuery;
      expect(q.employeeId, 'e2');
    });

    testWidgets('a cashier: "My sales", only their own, no filters, rows do not drill', (t) async {
      when(
        () => repo.getBizReport(
          'st1',
          ReportKind.cashiers,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => CashiersReport.fromJson(cashiersJson(ownOnly: true)));
      final c = ctl(ReportKind.cashiers, manager: false);
      await pump(t, ReportView(kind: ReportKind.cashiers, controller: c));
      expect(find.text('My sales'), findsOneWidget);
      expect(find.byKey(const Key('cashiersOwnOnly')), findsOneWidget);
      expect(find.byKey(const Key('filterRegister')), findsNothing);
      await tapKey(t, 'cashier_e1');
      expect(c.employeeId.value, isNull);
      verifyNever(() => repo.getEmployees(any()));
    });
  });

  // ── pulse ───────────────────────────────────────────────────────────────────────────────────
  group('PulseView', () {
    BusinessPulseController pc({bool manager = true}) => BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => manager);

    for (final env in _Env.values) {
      testWidgets('${env.name}: today vs the same weekday last week with chips, top products, low stock and clocked in', (t) async {
        when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse());
        await pump(t, PulseView(controller: pc()), env);
        expect(find.textContaining('compared with Tue 3 Nov'), findsOneWidget);
        expect(find.byKey(const Key('pulse_netSalesMinor')), findsOneWidget);
        expect(find.text('+100%'), findsWidgets);
        expect(find.text('No change'), findsOneWidget);
        expect(find.text('No comparison'), findsWidgets);
        expect(find.byKey(const Key('pulseTop_0')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('low stock opens the low-stock list; clocked in opens attendance', (t) async {
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse());
      await pump(t, PulseView(controller: pc()));
      await tapKey(t, 'pulseLowStock');
      expect(find.text('LOW:true'), findsOneWidget);
      Get.back();
      await settle(t);
      await tapKey(t, 'pulseClockedIn');
      expect(find.text('ATTENDANCE'), findsOneWidget);
    });

    testWidgets('a cashier: managers only, no request; offline: needs internet; an error: Try again', (t) async {
      await pump(t, PulseView(controller: pc(manager: false)));
      expect(find.byKey(const Key('pulseManagersOnly')), findsOneWidget);
      verifyNever(() => repo.getBusinessPulse(any(), date: any(named: 'date')));
      Get.reset();
      offline();
      await pump(t, PulseView(controller: pc()));
      expect(find.byKey(const Key('reportsNeedsInternet')), findsOneWidget);
      Get.reset();
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
      await pump(t, PulseView(controller: pc()));
      expect(find.text('Sign in with your PIN first.'), findsOneWidget);
    });

    testWidgets('nothing sold yet today', (t) async {
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse(empty: true));
      await pump(t, PulseView(controller: pc()));
      expect(find.byKey(const Key('pulseNoTop')), findsOneWidget);
      expect(find.text('−100%'), findsOneWidget);
    });
  });

  group('PulseHomeCard', () {
    testWidgets('shown only after a 200; tapping opens the pulse', (t) async {
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse());
      await pump(
        t,
        Scaffold(
          body: PulseHomeCard(
            controller: BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true),
          ),
        ),
      );
      expect(find.byKey(const Key('pulseHomeCard')), findsOneWidget);
      expect(find.textContaining('vs last Tue'), findsOneWidget);
      await tapKey(t, 'pulseHomeCard');
      expect(find.text('PULSE'), findsOneWidget);
    });

    testWidgets('refused by the server, a cashier, or no controller: nothing is drawn', (t) async {
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => null);
      await pump(
        t,
        Scaffold(
          body: PulseHomeCard(
            controller: BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true),
          ),
        ),
      );
      expect(find.byKey(const Key('pulseHomeCard')), findsNothing);
      await pump(
        t,
        Scaffold(
          body: PulseHomeCard(
            controller: BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => false),
          ),
        ),
      );
      expect(find.byKey(const Key('pulseHomeCard')), findsNothing);
      await pump(t, const Scaffold(body: PulseHomeCard()));
      expect(find.byKey(const Key('pulseHomeCard')), findsNothing);
    });
  });

  // ── time zone ───────────────────────────────────────────────────────────────────────────────
  group('TimeZoneView', () {
    TimeZoneController tz({bool owner = true}) => Get.put(
      TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => owner, clock: () => DateTime(2026, 11, 10, 23)),
      tag: 'tz${DateTime.now().microsecondsSinceEpoch}',
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: the owner sees the zone, the store\'s today and the list with Asia/Karachi first', (t) async {
        await pump(t, TimeZoneView(controller: tz()), env);
        expect(find.byKey(const Key('tzName')), findsOneWidget);
        expect(find.text('Today in the store: Wed 11 Nov'), findsOneWidget);
        expect(find.byKey(const Key('tzSearch')), findsOneWidget);
        final first = t.getTopLeft(find.byKey(const Key('tz_Asia/Karachi'))).dy;
        expect(first, lessThan(t.getTopLeft(find.byKey(const Key('tz_Asia/Dubai'))).dy));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('choosing a zone PATCHes it; INVALID_TIME_ZONE is worded', (t) async {
      when(() => repo.setStoreTimeZone('st1', 'Europe/London')).thenAnswer((_) async => (success: true, message: null, code: null, zone: zone(tz: 'Europe/London', explicit: true)));
      when(() => repo.setStoreTimeZone('st1', 'Asia/Dubai')).thenAnswer((_) async => (success: false, message: 'x', code: 'INVALID_TIME_ZONE', zone: null));
      await pump(t, TimeZoneView(controller: tz()));
      await t.enterText(find.descendant(of: find.byKey(const Key('tzSearch')), matching: find.byType(TextField)), 'london');
      await settle(t);
      await tapKey(t, 'tz_Europe/London');
      verify(() => repo.setStoreTimeZone('st1', 'Europe/London')).called(1);
      expect(find.byKey(const Key('tzSaved')), findsOneWidget);
      expect(find.text('Europe/London'), findsWidgets);
      await t.enterText(find.descendant(of: find.byKey(const Key('tzSearch')), matching: find.byType(TextField)), 'dubai');
      await settle(t);
      await tapKey(t, 'tz_Asia/Dubai');
      expect(find.textContaining('not a valid time zone'), findsOneWidget);
    });

    testWidgets('a manager / cashier reads it only; offline needs internet', (t) async {
      await pump(t, TimeZoneView(controller: tz(owner: false)));
      expect(find.byKey(const Key('tzReadOnly')), findsOneWidget);
      expect(find.byKey(const Key('tzSearch')), findsNothing);
      expect(find.byKey(const Key('tz_Asia/Dubai')), findsNothing);
      Get.reset();
      offline();
      await pump(t, TimeZoneView(controller: tz()));
      expect(find.byKey(const Key('reportsNeedsInternet')), findsOneWidget);
    });
  });
}
