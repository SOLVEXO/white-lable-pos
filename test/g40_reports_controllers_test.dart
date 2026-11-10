// G4.0 / G4.1 controllers: the report periods are STORE days built from the server's `today` (not the device's date), compare on / off, filters,
// product sort, the previous period's days for the dashed line, offline (no request), refusals in words, CSV / PDF export; the pulse (a cashier never
// asks; 200 → shown; refused → hidden); the time zone (owner PATCH, others read only, INVALID_TIME_ZONE in words, search).
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/time_zone_controller.dart';

import 'support/g40_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

void main() {
  late _Repo repo;
  final device = DateTime(2026, 11, 10, 23, 30); // the device thinks it is still the 10th …

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
    when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(today: '2026-11-11')); // … but in the store it is the 11th
    when(() => repo.getEmployees('st1')).thenAnswer((_) async => []);
    when(() => repo.listRegisters('st1')).thenAnswer((_) async => []);
  });

  Future<void> pause([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

  void stub(ReportKind k, BizReport? r) => when(
    () => repo.getBizReport(
      'st1',
      k,
      any(),
      sort: any(named: 'sort'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => r);
  ReportQuery lastQuery(ReportKind k) =>
      verify(
            () => repo.getBizReport(
              'st1',
              k,
              captureAny(),
              sort: any(named: 'sort'),
              limit: any(named: 'limit'),
            ),
          ).captured.last
          as ReportQuery;

  ReportController make(ReportKind k, {bool manager = true, Future<void> Function(ShareParams)? share, String? employeeId}) =>
      ReportController(kind: k, repository: repo, storeId: 'st1', clock: () => device, canManage: manager, share: share, storeName: () async => 'Dev Store', employeeId: employeeId);

  group('ReportController', () {
    test('the default period (last 7 days) ends on the STORE\'s today from the time-zone endpoint, not the device date', () async {
      stub(ReportKind.sales, report(ReportKind.sales));
      final c = make(ReportKind.sales)..onInit();
      await pause();
      final q = lastQuery(ReportKind.sales);
      expect([q.from, q.to, q.compare], ['2026-11-05', '2026-11-11', false]);
      expect(c.report.value, isA<SalesReport>());
      c.onClose();
    });

    test('the device date is used only when the zone cannot be read', () async {
      when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => null);
      stub(ReportKind.tax, report(ReportKind.tax));
      final c = make(ReportKind.tax)..onInit();
      await pause();
      expect(lastQuery(ReportKind.tax).to, '2026-11-10');
      c.onClose();
    });

    test('ranges, custom dates, filters; compare only where the server offers it', () async {
      stub(ReportKind.payments, report(ReportKind.payments));
      final c = make(ReportKind.payments)..onInit();
      await pause();
      c.setRange(ReportRange.yesterday);
      await pause();
      final y = lastQuery(ReportKind.payments);
      expect([y.from, y.to], ['2026-11-10', '2026-11-10']);
      c.setCustom(DateTime(2026, 10, 1), DateTime(2026, 10, 15));
      await pause();
      final cu = lastQuery(ReportKind.payments);
      expect([cu.from, cu.to], ['2026-10-01', '2026-10-15']);
      c.setRegister('r1');
      c.setEmployee('e2');
      c.setCompare(true);
      await pause();
      final q = lastQuery(ReportKind.payments);
      expect([q.registerId, q.employeeId, q.compare], ['r1', 'e2', false], reason: 'payments have no previous-period block');
      expect(c.supportsCompare, isFalse);
      c.onClose();
    });

    test('sales with compare ON: compare=previous, the previous period\'s days come with the report (no second request); OFF: none', () async {
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
        return q.compare ? SalesReport.fromJson(salesJson(compare: true)) : SalesReport.fromJson(salesJson(from: q.from, to: q.to));
      });
      final c = make(ReportKind.sales)..onInit();
      await pause();
      expect(c.previousByDay, isEmpty);
      c.setCompare(true);
      await pause();
      final calls = verify(
        () => repo.getBizReport(
          'st1',
          ReportKind.sales,
          captureAny(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      ).captured.cast<ReportQuery>();
      expect(calls.map((q) => q.compare), [false, true], reason: 'one request per load: the previous days are in the compared report');
      expect(c.previousByDay.map((d) => d.day), ['2026-10-30', '2026-10-31', '2026-11-01']);
      c.setCompare(false);
      await pause();
      expect(c.previousByDay, isEmpty);
      c.onClose();
    });

    test('products: the sort goes to the server with a limit; other reports send none', () async {
      stub(ReportKind.products, report(ReportKind.products));
      final c = make(ReportKind.products)..onInit();
      await pause();
      c.setSort('margin');
      await pause();
      verify(() => repo.getBizReport('st1', ReportKind.products, any(), sort: 'margin', limit: 100)).called(1);
      c.onClose();
    });

    test('a refusal is in words; offline makes no request', () async {
      stub(ReportKind.cashiers, null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = make(ReportKind.cashiers, manager: false)..onInit();
      await pause();
      expect(c.error.value, 'Your role is not allowed to see this.');
      c.onClose();
      Get.reset();
      clearInteractions(repo);
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final d = make(ReportKind.cashiers)..onInit();
      await pause();
      verifyNever(
        () => repo.getBizReport(
          any(),
          any(),
          any(),
          sort: any(named: 'sort'),
          limit: any(named: 'limit'),
        ),
      );
      expect(d.loading.value, isFalse);
      d.onClose();
    });

    test('a cashier: no filters are loaded; the cashier drill-down opens filtered to one employee', () async {
      stub(ReportKind.cashiers, report(ReportKind.cashiers));
      final c = make(ReportKind.cashiers, manager: false)..onInit();
      await pause();
      verifyNever(() => repo.getEmployees(any()));
      c.onClose();
      final d = make(ReportKind.cashiers, employeeId: 'e2')..onInit();
      await pause();
      expect(lastQuery(ReportKind.cashiers).employeeId, 'e2');
      d.onClose();
    });

    test('export: CSV and PDF go to the share sheet with the period in the name', () async {
      stub(ReportKind.payments, report(ReportKind.payments));
      final shared = <ShareParams>[];
      final c = make(ReportKind.payments, share: (p) async => shared.add(p))..onInit();
      await pause();
      await c.shareCsv();
      await c.sharePdf();
      expect(shared.map((s) => s.files!.single.mimeType), ['text/csv', 'application/pdf']);
      expect(shared.first.fileNameOverrides, ['payments-2026-11-02-to-2026-11-08.csv']);
      expect(shared.last.fileNameOverrides, ['payments-2026-11-02-to-2026-11-08.pdf']);
      expect(String.fromCharCodes(await shared.first.files!.single.readAsBytes()).split('\n').first, 'Method,Payments,Paid,Refunded,Net,Share %');
      expect(shared.last.subject, 'Payment mix report 2026-11-02 to 2026-11-08');
      c.onClose();
    });
  });

  group('BusinessPulseController', () {
    test('a cashier never asks', () async {
      final c = BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => false);
      await c.load();
      verifyNever(() => repo.getBusinessPulse(any(), date: any(named: 'date')));
      expect(c.allowed.value, isFalse);
    });

    test('200 → allowed with the figures; a refusal → hidden with the words', () async {
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => pulse());
      final c = BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true);
      await c.load();
      expect([c.allowed.value, c.pulse.value!.today.netSalesMinor], [true, 2000]);
      when(() => repo.getBusinessPulse('st1', date: any(named: 'date'))).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final d = BusinessPulseController(repository: repo, storeId: 'st1', canManage: () async => true);
      await d.load();
      expect([d.allowed.value, d.error.value], [false, 'Your role is not allowed to see this.']);
    });
  });

  group('TimeZoneController', () {
    test('reads the zone and remembers today\'s store date for the reports', () async {
      final c = TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => false, clock: () => device)..onInit();
      await pause();
      expect([c.zone.value!.timeZone, c.canEdit.value, StoreDay.cached?.today], ['Asia/Karachi', false, '2026-11-11']);
      expect(await c.choose('Europe/London'), isFalse, reason: 'only the owner');
      verifyNever(() => repo.setStoreTimeZone(any(), any()));
      c.onClose();
    });

    test('the owner changes it; INVALID_TIME_ZONE and a refusal are worded', () async {
      when(
        () => repo.setStoreTimeZone('st1', 'Europe/London'),
      ).thenAnswer((_) async => (success: true, message: null, code: null, zone: zone(tz: 'Europe/London', explicit: true, today: '2026-11-10')));
      when(() => repo.setStoreTimeZone('st1', 'Asia/Dubai')).thenAnswer((_) async => (success: false, message: 'bad', code: 'INVALID_TIME_ZONE', zone: null));
      when(() => repo.setStoreTimeZone('st1', 'UTC')).thenAnswer((_) async => (success: false, message: 'no', code: 'POS_ACTION_FORBIDDEN', zone: null));
      final c = TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => true, clock: () => device)..onInit();
      await pause();
      expect(await c.choose('Europe/London'), isTrue);
      expect([c.zone.value!.timeZone, StoreDay.cached?.timeZone], ['Europe/London', 'Europe/London']);
      expect(c.saved.value, contains('Europe/London'));
      expect(await c.choose('Asia/Dubai'), isFalse);
      expect(c.saveError.value, contains('not a valid time zone'));
      expect(await c.choose('UTC'), isFalse);
      expect(c.saveError.value, 'Your role is not allowed to see this.');
      c.onClose();
    });

    test('the list: Asia/Karachi first; search narrows it; the current zone is always offered', () async {
      when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(tz: 'America/Lima'));
      final c = TimeZoneController(repository: repo, storeId: 'st1', isOwner: () async => true, clock: () => device)..onInit();
      await pause();
      expect(c.zones.first, 'Asia/Karachi');
      expect(c.zones, contains('America/Lima'));
      c.search.value = 'lon';
      expect(c.zones, ['Europe/London']);
      c.search.value = 'kuala lumpur';
      expect(c.zones, ['Asia/Kuala_Lumpur']);
      c.onClose();
    });
  });
}
