// Screenshot pass for the G4.0 / G4.1 screens (reports hub, business pulse + its Home card, the eight reports, the store time zone) on the iOS
// simulator — real rendering, real fonts, mocked repositories, light AND dark. Phone: every screen ("G4 phone"); tablet: the hub and the sales report
// ("G4 tablet", two columns).
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/time_zone_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_home_card.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/reports_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/time_zone_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

import '../test/support/g40_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(const ReportQuery(from: '', to: ''));
  registerFallbackValue(ReportKind.sales);

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
          builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: theme, home: w),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
    }

    _Repo fresh() {
      Get.reset();
      StoreDay.forget();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(today: '2026-11-08'));
      when(() => repo.getEmployees('st1')).thenAnswer((_) async => []);
      when(() => repo.listRegisters('st1')).thenAnswer((_) async => []);
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse());
      when(
        () => repo.getBizReport(
          'st1',
          any(),
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((i) async {
        final k = i.positionalArguments[1] as ReportKind;
        final q = i.positionalArguments[2] as ReportQuery;
        if (k == ReportKind.sales) {
          return SalesReport.fromJson(q.compare ? _salesWeek(compare: true) : _salesWeek(from: q.from, to: q.to, scale: q.from.startsWith('2026-10') ? 0.7 : 1));
        }
        return report(k);
      });
      return repo;
    }

    ReportController ctl(_Repo repo, ReportKind k, {bool manager = true, bool compare = false}) {
      final c = Get.put(
        ReportController(kind: k, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 8, 15), canManage: manager),
        tag: '${k.name}_$tn',
      );
      if (compare) c.compare.value = true;
      return c;
    }

    Future<void> shootReport(WidgetTester t, _Repo repo, ReportKind k, String name, {bool manager = true, bool compare = false}) async {
      await show(
        t,
        ReportView(
          kind: k,
          controller: ctl(repo, k, manager: manager, compare: compare),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
      await shot(t, name, tn);
    }

    testWidgets('G4 phone hub, pulse, home card, time zone ($tn)', (t) async {
      fresh();
      await show(t, const ReportsHubView());
      await shot(t, 'g40_01_reports_hub', tn);

      var repo = fresh();
      await show(
        t,
        PulseView(
          controller: BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true),
        ),
      );
      await shot(t, 'g40_02_business_pulse', tn);

      repo = fresh();
      await show(
        t,
        Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PulseHomeCard(
                  controller: BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true),
                ),
              ],
            ),
          ),
        ),
      );
      await shot(t, 'g40_03_home_pulse_card', tn);

      repo = fresh();
      await show(
        t,
        TimeZoneView(
          controller: Get.put(
            TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => true),
            tag: 'tz_$tn',
          ),
        ),
      );
      await shot(t, 'g40_14_time_zone_owner', tn);

      repo = fresh();
      await show(
        t,
        TimeZoneView(
          controller: Get.put(
            TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => false),
            tag: 'tz2_$tn',
          ),
        ),
      );
      await shot(t, 'g40_15_time_zone_read_only', tn);
    });

    testWidgets('G4 phone reports ($tn)', (t) async {
      await shootReport(t, fresh(), ReportKind.sales, 'g40_04_sales_compare', compare: true);
      await shootReport(t, fresh(), ReportKind.profit, 'g40_05_profit_coverage');
      await shootReport(t, fresh(), ReportKind.products, 'g40_06_products');
      await shootReport(t, fresh(), ReportKind.categories, 'g40_07_categories');
      await shootReport(t, fresh(), ReportKind.tax, 'g40_08_tax');
      await shootReport(t, fresh(), ReportKind.payments, 'g40_09_payment_mix');
      await shootReport(t, fresh(), ReportKind.cashiers, 'g40_10_cashiers');
      final repo = fresh();
      when(
        () => repo.getBizReport(
          'st1',
          ReportKind.cashiers,
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => CashiersReport.fromJson(cashiersJson(ownOnly: true)));
      await shootReport(t, repo, ReportKind.cashiers, 'g40_11_my_sales_cashier', manager: false);
      await shootReport(t, fresh(), ReportKind.hourly, 'g40_12_hourly');
    });

    testWidgets('G4 tablet hub and sales ($tn)', (t) async {
      fresh();
      await show(t, const ReportsHubView());
      await shot(t, 'g40_t01_reports_hub', tn);
      await shootReport(t, fresh(), ReportKind.sales, 'g40_t02_sales_compare', compare: true);
      await shootReport(t, fresh(), ReportKind.hourly, 'g40_t03_hourly');
    });
  }
}

/// a week of sales with a shape (so the line and its dashed previous week are readable)
Map<String, dynamic> _salesWeek({bool compare = false, String from = '2026-11-02', String to = '2026-11-08', double scale = 1}) {
  final j = salesJson(compare: compare, from: from, to: to);
  final start = parseDayKey(from)!;
  const shape = [42000, 38500, 51000, 47250, 63800, 72100, 55400];
  j['byDay'] = [
    for (var i = 0; i < 7; i++) {'day': dayKey(DateTime(start.year, start.month, start.day + i)), 'transactions': 20 + i * 3, 'totalMinor': (shape[i] * 100 * scale).round()},
  ];
  j['period'] = {'from': from, 'to': to, 'days': 7};
  // totals that agree with the days (net = Σ days; gross incl. 18% tax)
  int sum(double k) => [for (final v in shape) (v * 100 * k).round()].fold(0, (a, b) => a + b);
  j['totals'] = salesTotalsJson(tx: 203, net: sum(scale), gross: (sum(scale) * 1.18).round());
  if (compare) {
    final prevStart = DateTime(2026, 10, 26);
    j['previous'] = {
      'period': {'from': '2026-10-26', 'to': '2026-11-01'},
      'totals': salesTotalsJson(tx: 142, net: sum(0.7), gross: (sum(0.7) * 1.18).round()),
      // the previous period's days come with the report (the dashed line)
      'byDay': [
        for (var i = 0; i < 7; i++) {'day': dayKey(DateTime(prevStart.year, prevStart.month, prevStart.day + i)), 'transactions': 14 + i * 2, 'totalMinor': (shape[i] * 70 * scale).round()},
      ],
    };
  }
  return j;
}
