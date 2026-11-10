// Screenshot pass for the G3.6 team screens (clock, attendance, record, correction, roster, shift, report, Needs attention) on the iOS simulator, light AND dark.
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g36_screens_shots_test.dart <outdir> <suffix>
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/views/pos_needs_attention_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/attendance_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/correction_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/record_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/roster_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/shift_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/attendance_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/clock_home_card.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/clock_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/correction_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/record_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/roster_view.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/shift_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_report_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/fake_payments.dart';
import '../test/support/g36_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

class _Sync extends Mock implements PendingSaleSyncService {}

class _Queue extends PendingTeamSyncService {
  _Queue()
    : super(
        posRepository: _Repo(),
        localStore: PendingTeamLocalStore(dbPath: 'unused.db'),
      );
  void setRows(List<PendingClockRecord> rows) {
    items.assignAll(rows);
    pendingCount.value = rows.where((r) => r.isPending).length;
    failedCount.value = rows.where((r) => r.isFailed).length;
  }

  @override
  Future<PendingClockRecord> enqueue({
    required String storeId,
    required String requestId,
    required String action,
    required DateTime deviceAt,
    required String employeeId,
    String? note,
    String? employeeToken,
  }) async {
    final r = PendingClockRecord(seq: items.length + 1, id: requestId, action: action, deviceAt: deviceAt, status: 'pending', createdAt: deviceAt, storeId: storeId, employeeId: employeeId);
    items.add(r);
    return r;
  }

  @override
  Future<void> refreshCounts() async {}
  @override
  Future<void> syncNow({bool ignoreBackoff = false}) async {}
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

PendingClockRecord _row(String id, {String action = 'clock_in', String status = 'pending', String? message}) => PendingClockRecord(
  seq: 1,
  id: id,
  action: action,
  deviceAt: DateTime(2026, 11, 9, 9, 2),
  status: status,
  createdAt: DateTime(2026, 11, 9, 9, 2),
  storeId: 'st1',
  employeeId: 'e1',
  errorMessage: message,
  errorCode: status == 'failed' ? 'EMPLOYEE_REQUIRED' : null,
);

/// Registers an OFFLINE connectivity service while the app below it is being built (a replaced GetMaterialApp resets GetX when it is disposed, so a
/// service registered before the swap would be gone).
class _Offline extends StatefulWidget {
  const _Offline({required this.child});
  final Widget child;
  @override
  State<_Offline> createState() => _OfflineState();
}

class _OfflineState extends State<_Offline> {
  @override
  void initState() {
    super.initState();
    Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 11, 15);

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

    Future<void> show(WidgetTester t, Widget w, {bool offline = false}) async {
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: offline ? _Offline(child: w) : w,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
    }

    _Repo fresh({bool manager = false}) {
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1', if (manager) 'pos_employee_role': 'manager'});
      Money.configure(currency: 'USD', exponent: 2);
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          shifts: [
            shift(start: DateTime(2026, 11, 11, 17), end: DateTime(2026, 11, 11, 23)),
            shift(id: 'sh3', start: DateTime(2026, 11, 12, 9), end: DateTime(2026, 11, 12, 17), location: 'l1'),
          ],
        ),
      );
      when(
        () => repo.getAttendanceRecords(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer(
        (_) async => [
          record(),
          record(id: 'b', name: 'Ali', corrected: true),
          record(id: 'o', name: 'Bo', noOut: true, flags: ['missing_clock_out']),
          record(id: 'v', name: 'Cy', status: 'voided'),
        ],
      );
      when(
        () => repo.getRoster(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer(
        (_) async => [
          shift(location: 'l1', note: 'opening'),
          shift(id: 'sh2', employeeId: 'e2', name: 'Ali', start: DateTime(2026, 11, 11, 13), end: DateTime(2026, 11, 11, 21)),
          shift(id: 'sh4', employeeId: 'e1', start: DateTime(2026, 11, 13, 9), end: DateTime(2026, 11, 13, 17)),
        ],
      );
      when(
        () => repo.getTeamReport(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) async => report());
      when(
        () => repo.getAttendanceRecordDetail(
          'st1',
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
        ),
      ).thenAnswer((_) async => recordDetail());
      when(() => repo.getEmployees('st1')).thenAnswer((_) async => [employee('e1', 'Sam'), employee('e2', 'Ali')]);
      return repo;
    }

    TeamClockController clockCtl(_Repo repo, {_Queue? queue, bool cached = false}) => Get.put(
      TeamClockController(
        repository: repo,
        cache: testTeamCache(),
        queue: queue ?? _Queue(),
        storeId: 'st1',
        employeeIdProvider: () async => 'e1',
        employeeNameProvider: () async => 'Sam',
        employeeTokenProvider: () async => 'tok',
        requestIdFactory: () => 'req-1',
        clock: () => DateTime(2026, 11, 11, 15),
      ),
    );

    Future<void> sheet(WidgetTester t, void Function() open, {bool offline = false}) async {
      await show(t, const Scaffold(body: SizedBox.shrink()), offline: offline);
      open();
      await t.pump(const Duration(milliseconds: 900));
    }

    testWidgets('G3.6 clock ($tn)', (t) async {
      var repo = fresh();
      await show(t, TeamClockView(controller: clockCtl(repo)));
      await shot(t, 'g36_01_clock_not_clocked_in', tn);

      repo = fresh();
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          clockedIn: true,
          shifts: [shift(start: DateTime(2026, 11, 11, 9), end: DateTime(2026, 11, 11, 17))],
        ),
      );
      await show(t, TeamClockView(controller: clockCtl(repo)));
      await shot(t, 'g36_02_clock_clocked_in', tn);

      repo = fresh();
      final q = _Queue();
      await show(t, TeamClockView(controller: clockCtl(repo, queue: q)), offline: true);
      await t.tap(find.byKey(const Key('clock_clock_in')));
      await t.pump();
      await shot(t, 'g36_03_clock_offline_waiting_to_sync', tn);

      repo = fresh();
      await show(
        t,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [ClockHomeCard(controller: clockCtl(repo))],
          ),
        ),
      );
      await shot(t, 'g36_04_home_clock_card', tn);
    });

    testWidgets('G3.6 attendance ($tn)', (t) async {
      var repo = fresh(manager: true);
      final c = Get.put(AttendanceController(repository: repo, storeId: 'st1', clock: () => now));
      await show(t, AttendanceView(controller: c));
      await shot(t, 'g36_05_attendance_manager', tn);

      repo = fresh();
      await show(
        t,
        AttendanceRecordView(
          record: record(corrected: true),
          canCorrect: true,
          detailController: Get.put(RecordDetailController(employeeId: 'e1', recordId: 'rec1', repository: repo, storeId: 'st1')),
        ),
      );
      await shot(t, 'g36_06_record_detail_corrected', tn);

      repo = fresh();
      final corr = CorrectionController(record: record(noOut: true), repository: repo, storeId: 'st1', clock: () => now);
      await sheet(t, () => CorrectionSheet.open(record(noOut: true), controller: corr));
      corr.clockOutAt.value = DateTime(2026, 11, 9, 17);
      await t.pump();
      await shot(t, 'g36_07_correction_reason_required', tn);
    });

    testWidgets('G3.6 roster and shifts ($tn)', (t) async {
      var repo = fresh(manager: true);
      Widget roster(_Repo r, {bool manager = false}) {
        final rc = Get.put(
          RosterController(repository: r, cache: testTeamCache(), storeId: 'st1', employeeIdProvider: () async => 'e1', clock: () => now, locationNames: () async => {'l1': 'Main shop'}),
        );
        rc.canManageHint.value = manager;
        return RosterView(controller: rc);
      }

      await show(t, roster(repo, manager: true));
      await shot(t, 'g36_08_roster_manager', tn);

      repo = fresh();
      await show(t, roster(repo));
      await shot(t, 'g36_09_roster_cashier_read_only', tn);

      repo = fresh();
      final cache = testTeamCache();
      await cache.saveRoster('st1', '2026-11-09', [shift(), shift(id: 'sh2', employeeId: 'e2', name: 'Ali')]);
      await show(
        t,
        RosterView(
          controller: Get.put(RosterController(repository: repo, cache: cache, storeId: 'st1', employeeIdProvider: () async => 'e1', clock: () => now)),
        ),
        offline: true,
      );
      await shot(t, 'g36_10_roster_offline_last_synced', tn);

      repo = fresh();
      final sc = ShiftController(
        existing: null,
        presetDay: DateTime(2026, 11, 9),
        repository: repo,
        storeId: 'st1',
        people: [employee('e1', 'Sam'), employee('e2', 'Ali')],
        locations: {'l1': 'Main shop'},
      );
      await sheet(t, () => ShiftSheet.open(controller: sc));
      sc.employeeId.value = 'e1';
      sc.start.value = const TimeOfDay(hour: 8, minute: 0);
      sc.end.value = const TimeOfDay(hour: 18, minute: 0);
      await t.pump();
      when(
        () => repo.createRosterShift(
          'st1',
          employeeId: any(named: 'employeeId'),
          startAt: any(named: 'startAt'),
          endAt: any(named: 'endAt'),
          locationId: any(named: 'locationId'),
          note: any(named: 'note'),
        ),
      ).thenAnswer(
        (_) async => (
          success: false,
          message: 'x',
          code: 'ROSTER_OVERLAP',
          extra: {'conflictStartAt': DateTime(2026, 11, 9, 7).toUtc().toIso8601String(), 'conflictEndAt': DateTime(2026, 11, 9, 12).toUtc().toIso8601String()},
          shift: null,
        ),
      );
      await sc.submit();
      await t.pump();
      await shot(t, 'g36_11_shift_sheet_overlap', tn);
    });

    testWidgets('G3.6 report and needs attention ($tn)', (t) async {
      var repo = fresh(manager: true);
      await show(
        t,
        TeamReportView(
          controller: Get.put(TeamReportController(repository: repo, storeId: 'st1', clock: () => now, tzOffsetMinutes: () => -300)),
        ),
      );
      await shot(t, 'g36_12_report', tn);

      repo = fresh(manager: true);
      final q = _Queue()
        ..setRows([_row('w1'), _row('f1', action: 'clock_out', status: 'failed', message: 'Sign in with your PIN first. Attendance belongs to a team member, not to the owner account.')]);
      final sync = _Sync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => repo.getSalesNeedingReview(any())).thenAnswer((_) async => []);
      when(() => repo.getAttendanceAnomalies('st1')).thenAnswer((_) async => [anomaly(), anomaly(kind: 'late_sync', recordId: null, eventId: 'ev2', name: 'Bo')]);
      final na = PosNeedsAttentionController(syncService: sync, posRepository: repo, paymentsRepository: FakePaymentsRepo(), teamQueue: q);
      Get.put<PosNeedsAttentionController>(na);
      await show(t, PosNeedsAttentionView(controller: na));
      await shot(t, 'g36_13_needs_attention_attendance', tn);
    });
  }
}
