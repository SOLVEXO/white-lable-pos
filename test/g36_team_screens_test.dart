// G3.6 team screens on phone, tablet and dark: the clock (with its offline queue), the Home card, attendance, records, corrections (a reason is required),
// anomalies in Needs attention, the roster (conflicts, offline copy), shifts and the report; every state (loading, empty, error, needs-internet / read-only).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
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
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';

import 'support/fake_payments.dart';
import 'support/g36_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

class _Sync extends Mock implements PendingSaleSyncService {}

/// A queue that keeps events in memory and records what it is asked to do.
class _Queue extends PendingTeamSyncService {
  _Queue()
    : super(
        posRepository: _Repo(),
        localStore: PendingTeamLocalStore(dbPath: 'unused.db'),
      );
  final retried = <String>[];
  final dismissed = <String>[];
  int syncs = 0;

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
  Future<void> syncNow({bool ignoreBackoff = false}) async => syncs++;
  @override
  Future<void> retry(String id) async => retried.add(id);
  @override
  Future<void> dismiss(String id) async => dismissed.add(id);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) => syncs++;
}

PendingClockRecord clockRow(String id, {String action = 'clock_in', String status = 'pending', String? message, int attempts = 0, String employee = 'e1'}) => PendingClockRecord(
  seq: 1,
  id: id,
  action: action,
  deviceAt: DateTime(2026, 11, 9, 9, 2),
  status: status,
  createdAt: DateTime(2026, 11, 9, 9, 2),
  storeId: 'st1',
  employeeId: employee,
  errorMessage: message,
  errorCode: status == 'failed' ? 'EMPLOYEE_REQUIRED' : null,
  attempts: attempts,
);

const _phone = Size(390, 1500);
const _tablet = Size(834, 1194);

enum _Env { phone, tablet, dark }

void main() {
  late _Repo repo;
  var clock = DateTime(2026, 11, 9, 9, 2);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    clock = DateTime(2026, 11, 9, 9, 2);
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me());
    when(
      () => repo.getAttendanceRecordDetail(
        'st1',
        employeeId: any(named: 'employeeId'),
        recordId: any(named: 'recordId'),
      ),
    ).thenAnswer((_) async => recordDetail());
    when(
      () => repo.getAttendanceRecords(
        'st1',
        from: any(named: 'from'),
        to: any(named: 'to'),
        employeeId: any(named: 'employeeId'),
      ),
    ).thenAnswer((_) async => <AttendanceRecord>[]);
  });

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(
              name: Routes.posTeamRecord,
              page: () => Scaffold(body: Text('RECORD:${((Get.arguments as Map)['record'] as AttendanceRecord).recordId}')),
            ),
            GetPage(
              name: Routes.posTeamClock,
              page: () => const Scaffold(body: Text('CLOCK SCREEN')),
            ),
          ],
          home: w,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  TeamClockController clockCtl({String? employee = 'e1', _Queue? queue, dynamic cache}) {
    return Get.put(
      TeamClockController(
        repository: repo,
        cache: cache ?? testTeamCache(),
        queue: queue ?? _Queue(),
        storeId: 'st1',
        employeeIdProvider: () async => employee,
        employeeNameProvider: () async => 'Sam',
        employeeTokenProvider: () async => 'tok',
        requestIdFactory: () => 'req-1',
        clock: () => clock,
      ),
    );
  }

  void stubClock(({bool success, String? message, String? code, bool retryable, ClockResult? result}) r) {
    when(
      () => repo.teamClock(
        any(),
        action: any(named: 'action'),
        requestId: any(named: 'requestId'),
        deviceAt: any(named: 'deviceAt'),
        note: any(named: 'note'),
        employeeToken: any(named: 'employeeToken'),
      ),
    ).thenAnswer((_) async => r);
  }

  RecordDetailController detailCtl() => Get.put(
    RecordDetailController(employeeId: 'e1', recordId: 'rec1', repository: repo, storeId: 'st1'),
    tag: 'd${DateTime.now().microsecondsSinceEpoch}',
  );

  // ── clock ─────────────────────────────────────────────────────────────────────────────────────
  group('TeamClockView', () {
    for (final env in _Env.values) {
      testWidgets('${env.name}: not clocked in: a big Clock in button, who is clocking in, today and my next shifts', (t) async {
        when(
          () => repo.getAttendanceRecords(
            'st1',
            from: any(named: 'from'),
            to: any(named: 'to'),
            employeeId: any(named: 'employeeId'),
          ),
        ).thenAnswer((_) async => [record(noOut: true)]);
        await pump(t, TeamClockView(controller: clockCtl()), env);
        expect(find.text('Clocking in as Sam'), findsOneWidget);
        expect(find.text('Not clocked in'), findsOneWidget);
        expect(find.byKey(const Key('clock_clock_in')), findsOneWidget);
        expect(find.byKey(const Key('clock_clock_out')), findsNothing);
        expect(find.byKey(const Key('todayRec_rec1')), findsOneWidget);
        expect(find.text('09:00 - 17:00'), findsOneWidget, reason: 'my next shift');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('clocked in: Clock out is the big button with Start break; on a break: End break with Clock out', (t) async {
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true));
      await pump(t, TeamClockView(controller: clockCtl()));
      expect(find.text('Clocked in since 09:02'), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_out')), findsOneWidget);
      expect(find.byKey(const Key('clock_break_start')), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_in')), findsNothing);
      Get.reset();
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true, onBreak: true));
      await pump(t, TeamClockView(controller: clockCtl()));
      expect(find.byKey(const Key('clock_break_end')), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_out')), findsOneWidget);
      expect(find.byKey(const Key('clock_break_start')), findsNothing);
    });

    testWidgets('tapping Clock in sends the request and the screen follows the server\'s answer', (t) async {
      final c = clockCtl();
      await pump(t, TeamClockView(controller: c));
      Map<Symbol, dynamic>? sent;
      when(
        () => repo.teamClock(
          any(),
          action: any(named: 'action'),
          requestId: any(named: 'requestId'),
          deviceAt: any(named: 'deviceAt'),
          note: any(named: 'note'),
          employeeToken: any(named: 'employeeToken'),
        ),
      ).thenAnswer((i) async {
        sent = i.namedArguments;
        return (success: true, message: null, code: null, retryable: false, result: clockResult());
      });
      await tapKey(t, 'clock_clock_in');
      expect(sent![#action], 'clock_in');
      expect(sent![#requestId], 'req-1');
      expect(find.byKey(const Key('clockNotice')), findsOneWidget);
      expect(find.text('Clocked in since 09:02'), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_out')), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown in words', (t) async {
      final c = clockCtl();
      await pump(t, TeamClockView(controller: c));
      stubClock((success: false, message: 'x', code: 'ALREADY_CLOCKED_IN', retryable: false, result: null));
      await tapKey(t, 'clock_clock_in');
      expect(find.byKey(const Key('clockError')), findsOneWidget);
      expect(find.text('You are already clocked in.'), findsOneWidget);
    });

    testWidgets('OFFLINE: the banner, taps are accepted and queued ("Waiting to sync · N"), and the buttons follow the queue', (t) async {
      offline();
      final q = _Queue();
      final c = clockCtl(queue: q);
      await pump(t, TeamClockView(controller: c));
      expect(find.byKey(const Key('clockOffline')), findsOneWidget);
      await tapKey(t, 'clock_clock_in');
      expect(find.text('Waiting to sync · 1'), findsOneWidget);
      expect(find.byKey(const Key('waiting_req-1')), findsOneWidget);
      expect(find.text('Clocked in at 09:02'), findsOneWidget, reason: 'the waiting list says what was tapped and when');
      expect(find.byKey(const Key('clock_clock_out')), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_in')), findsNothing);
      expect(q.items.single.action, 'clock_in');
      verifyNever(
        () => repo.teamClock(
          any(),
          action: any(named: 'action'),
          requestId: any(named: 'requestId'),
          deviceAt: any(named: 'deviceAt'),
          note: any(named: 'note'),
          employeeToken: any(named: 'employeeToken'),
        ),
      );
    });

    testWidgets('offline, with the remembered state shown as "As of"', (t) async {
      final cache = testTeamCache();
      await cache.saveMe('st1', me(clockedIn: true));
      offline();
      await pump(t, TeamClockView(controller: clockCtl(cache: cache)));
      expect(find.text('Clocked in since 09:02'), findsOneWidget);
      expect(find.textContaining('As of'), findsOneWidget);
    });

    testWidgets('no PIN-signed-in person: asks for the PIN, no buttons', (t) async {
      await pump(t, TeamClockView(controller: clockCtl(employee: null)));
      expect(find.byKey(const Key('teamNeedsPin')), findsOneWidget);
      expect(find.byKey(const Key('clock_clock_in')), findsNothing);
    });

    testWidgets('loading / error with Try again', (t) async {
      final comp = Completer<TeamMe?>();
      when(() => repo.getTeamMe('st1')).thenAnswer((_) => comp.future);
      await pump(t, TeamClockView(controller: clockCtl()));
      expect(find.byKey(const Key('teamLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Sign in with your PIN first.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('empty: no punches and no shifts', (t) async {
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(shifts: const []));
      await pump(t, TeamClockView(controller: clockCtl()));
      expect(find.byKey(const Key('clockNoToday')), findsOneWidget);
      expect(find.byKey(const Key('clockNoShifts')), findsOneWidget);
    });
  });

  group('ClockHomeCard', () {
    testWidgets('shows the next shift today or tomorrow with its times and a "Clock in" chip; tapping opens the clock', (t) async {
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          shifts: [shift(start: DateTime(2026, 11, 9, 14), end: DateTime(2026, 11, 9, 22))],
        ),
      );
      await pump(t, Scaffold(body: ClockHomeCard(controller: clockCtl())));
      expect(find.text('Next shift today: 14:00 - 22:00'), findsOneWidget);
      expect(find.text('Clock in'), findsOneWidget);
      await tapKey(t, 'clockHomeCard');
      expect(find.text('CLOCK SCREEN'), findsOneWidget);
    });

    testWidgets('tomorrow\'s shift; clocked in and on a break read as such; no shift soon says so', (t) async {
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          clockedIn: true,
          shifts: [shift(start: DateTime(2026, 11, 10, 9), end: DateTime(2026, 11, 10, 17))],
        ),
      );
      await pump(t, Scaffold(body: ClockHomeCard(controller: clockCtl())));
      expect(find.text('Next shift tomorrow: 09:00 - 17:00'), findsOneWidget);
      expect(find.text('Clocked in'), findsOneWidget);
      Get.reset();
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true, onBreak: true, shifts: const []));
      await pump(t, Scaffold(body: ClockHomeCard(controller: clockCtl())));
      expect(find.text('On a break'), findsOneWidget);
      expect(find.text('No shift today or tomorrow'), findsOneWidget);
    });

    testWidgets('without a PIN-signed-in person, or without a registered controller, nothing is drawn', (t) async {
      await pump(t, Scaffold(body: ClockHomeCard(controller: clockCtl(employee: null))));
      expect(find.byKey(const Key('clockHomeCard')), findsNothing);
      Get.reset();
      await pump(t, const Scaffold(body: ClockHomeCard()));
      expect(find.byKey(const Key('clockHomeCard')), findsNothing);
    });
  });

  // ── attendance ────────────────────────────────────────────────────────────────────────────────
  group('AttendanceView', () {
    AttendanceController put({bool manager = false}) {
      SharedPreferences.setMockInitialValues({'store_id': 'st1', if (manager) 'pos_employee_role': 'manager'});
      return Get.put(AttendanceController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15)))..canManageHint.value = manager;
    }

    void stubRecords(List<AttendanceRecord> l) => when(
      () => repo.getAttendanceRecords(
        'st1',
        from: any(named: 'from'),
        to: any(named: 'to'),
        employeeId: any(named: 'employeeId'),
      ),
    ).thenAnswer((_) async => l);

    for (final env in _Env.values) {
      testWidgets('${env.name}: period and status chips, the hours, and every record with its badges (open / closed / voided / corrected / flags)', (t) async {
        stubRecords([
          record(),
          record(id: 'b', name: 'Ali', corrected: true),
          record(id: 'o', noOut: true, flags: ['missing_clock_out']),
          record(id: 'v', status: 'voided'),
        ]);
        await pump(t, AttendanceView(controller: put(manager: true)), env);
        for (final k in [
          'attPeriod_today',
          'attPeriod_week',
          'attPeriod_month',
          'attFilter_all',
          'attFilter_open',
          'attFilter_closed',
          'attFilter_voided',
          'attFilter_corrected',
          'attFilter_flagged',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('Worked 15:30 · breaks 1:30'), findsOneWidget, reason: 'voided never counts: two closed records of 7:45 each');
        expect(find.text('Corrected'), findsWidgets);
        expect(find.text('Missing clock-out'), findsOneWidget);
        expect(find.text('Open'), findsWidgets);
        expect(find.text('Voided'), findsWidgets);
        expect(find.byKey(const Key('attHours_rec1')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a filter chip narrows the list; a chip reloads with its period', (t) async {
      stubRecords([record(), record(id: 'o', noOut: true)]);
      await pump(t, AttendanceView(controller: put(manager: true)));
      await tapKey(t, 'attFilter_open');
      expect(find.byKey(const Key('att_o')), findsOneWidget);
      expect(find.byKey(const Key('att_rec1')), findsNothing);
      await tapKey(t, 'attPeriod_today');
      verify(() => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10), employeeId: null)).called(1);
    });

    testWidgets('a cashier sees only what the server sent (their own), without names, and no person picker', (t) async {
      stubRecords([record()]);
      await pump(t, AttendanceView(controller: put()));
      expect(find.byKey(const Key('att_rec1')), findsOneWidget);
      expect(find.text('Sam'), findsNothing);
      expect(find.byKey(const Key('attPerson')), findsNothing);
    });

    testWidgets('a manager gets a person picker that reloads for that person', (t) async {
      when(() => repo.getEmployees('st1')).thenAnswer((_) async => [employee('e1', 'Sam'), employee('e2', 'Ali')]);
      stubRecords([record()]);
      final c = put(manager: true);
      c.onInit();
      await pump(t, AttendanceView(controller: c));
      c.canManageHint.value = true;
      await t.pump();
      await tapKey(t, 'attPerson');
      await t.tap(find.byKey(const Key('attPerson_e2')));
      await t.pumpAndSettle();
      verify(
        () => repo.getAttendanceRecords(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: 'e2',
        ),
      ).called(1);
    });

    testWidgets('tapping a record opens it', (t) async {
      stubRecords([record()]);
      await pump(t, AttendanceView(controller: put(manager: true)));
      await tapKey(t, 'att_rec1');
      expect(find.text('RECORD:rec1'), findsOneWidget);
    });

    testWidgets('empty / loading / error / offline', (t) async {
      stubRecords([]);
      await pump(t, AttendanceView(controller: put()));
      expect(find.text('No attendance'), findsOneWidget);
      Get.reset();
      final comp = Completer<List<AttendanceRecord>?>();
      when(
        () => repo.getAttendanceRecords(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, AttendanceView(controller: put()));
      expect(find.byKey(const Key('teamLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
      Get.reset();
      offline();
      await pump(t, AttendanceView(controller: put()));
      expect(find.byKey(const Key('teamNeedsInternet')), findsOneWidget);
    });
  });

  group('AttendanceRecordView and CorrectionSheet', () {
    testWidgets('the record: in / out, hours, breaks, flags and the Corrected note; a manager gets Correct, a cashier does not', (t) async {
      await pump(
        t,
        AttendanceRecordView(
          record: record(corrected: true, flags: ['late_sync']),
          canCorrect: true,
          detailController: detailCtl(),
        ),
      );
      expect(find.text('09:02'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
      expect(find.text('7:45'), findsOneWidget);
      expect(find.byKey(const Key('recBreak_0')), findsOneWidget);
      expect(find.byKey(const Key('recCorrectedNote')), findsOneWidget);
      expect(find.text('Synced late'), findsWidgets);
      expect(find.byKey(const Key('recCorrect')), findsOneWidget);
      Get.reset();
      await pump(t, AttendanceRecordView(record: record(), canCorrect: false, detailController: detailCtl()));
      expect(find.byKey(const Key('recCorrect')), findsNothing);
      expect(find.byKey(const Key('recNoBreaks')), findsNothing);
    });

    testWidgets('a voided record cannot be corrected again', (t) async {
      await pump(
        t,
        AttendanceRecordView(
          record: record(status: 'voided'),
          canCorrect: true,
          detailController: detailCtl(),
        ),
      );
      expect(find.byKey(const Key('recCorrect')), findsNothing);
    });

    CorrectionController corr(AttendanceRecord r) => CorrectionController(record: r, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 20));
    Future<CorrectionController> mount(WidgetTester t, CorrectionController c, [_Env env = _Env.phone]) async {
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: CorrectionSheet(controller: c)),
        ),
        env,
      );
      return c;
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: the sheet needs a REASON; with a change and a reason it can be saved', (t) async {
        final c = await mount(t, corr(record(noOut: true)), env);
        expect(find.text('Add clock-out'), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('corrSave'))).onPressed, isNull);
        c.clockOutAt.value = DateTime(2026, 11, 9, 17);
        await t.pump();
        expect(t.widget<AppButton>(find.byKey(const Key('corrSave'))).onPressed, isNull, reason: 'a change but no reason');
        await t.enterText(find.descendant(of: find.byKey(const Key('corrReason')), matching: find.byType(TextField)), 'forgot to clock out');
        await t.pump();
        expect(t.widget<AppButton>(find.byKey(const Key('corrSave'))).onPressed, isNotNull);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('voiding changes the button; saving sends only the reason and voided; the corrected record comes back', (t) async {
      final c = await mount(t, corr(record()));
      await t.tap(find.byKey(const Key('corrVoid')));
      await t.pump();
      expect(find.text('Void record'), findsOneWidget);
      await t.enterText(find.descendant(of: find.byKey(const Key('corrReason')), matching: find.byType(TextField)), 'duplicate');
      await t.pump();
      Map<Symbol, dynamic>? sent;
      when(
        () => repo.correctAttendance(
          'st1',
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
          reason: any(named: 'reason'),
          clockInAt: any(named: 'clockInAt'),
          clockOutAt: any(named: 'clockOutAt'),
          voided: any(named: 'voided'),
        ),
      ).thenAnswer((i) async {
        sent = i.namedArguments;
        return (success: true, message: null, code: null, record: record(status: 'voided', corrected: true));
      });
      await tapKey(t, 'corrSave');
      expect([sent![#voided], sent![#reason], sent![#clockInAt], sent![#clockOutAt]], [true, 'duplicate', null, null]);
      expect(c.busy.value, isFalse);
    });

    testWidgets('a server refusal stays on the sheet in words; offline says Needs internet and disables save', (t) async {
      final c = await mount(t, corr(record(noOut: true)));
      c.clockOutAt.value = DateTime(2026, 11, 9, 17);
      c.reason.value = 'x';
      when(
        () => repo.correctAttendance(
          'st1',
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
          reason: any(named: 'reason'),
          clockInAt: any(named: 'clockInAt'),
          clockOutAt: any(named: 'clockOutAt'),
          voided: any(named: 'voided'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'RECORD_NOT_FOUND', record: null));
      await t.pump();
      await tapKey(t, 'corrSave');
      expect(find.byKey(const Key('corrError')), findsOneWidget);
      expect(find.text('That attendance record was not found.'), findsOneWidget);
      Get.reset();
      offline();
      final d = await mount(t, corr(record(noOut: true)));
      d.clockOutAt.value = DateTime(2026, 11, 9, 17);
      d.reason.value = 'x';
      await t.pump();
      expect(find.byKey(const Key('corrOffline')), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('corrSave'))).onPressed, isNull);
    });
  });

  group('AttendanceRecordView history: punches and corrections', () {
    for (final env in _Env.values) {
      testWidgets('${env.name}: every punch with its effective time, device vs server time when they differ, flags in words, and who corrected what and why', (t) async {
        await pump(t, AttendanceRecordView(record: record(corrected: true), canCorrect: false, detailController: detailCtl()), env);
        expect(find.text('Punches'), findsOneWidget);
        expect(find.text('Clocked in · 09:02'), findsOneWidget);
        expect(find.text('Break started · 12:00'), findsOneWidget);
        expect(find.text('Clocked out · 17:00'), findsOneWidget);
        expect(find.byKey(const Key('punchTimes_p1')), findsNothing, reason: 'device and server agree');
        expect(find.byKey(const Key('punchTimes_p3')), findsOneWidget);
        expect(find.textContaining('Device time 17:00 · server time 08:30'), findsOneWidget);
        expect(find.text('Synced late'), findsWidgets);
        expect(find.text('Corrections'), findsOneWidget);
        expect(find.textContaining('Mia Manager'), findsOneWidget);
        expect(find.text('Clock-out set to 17:00'), findsOneWidget);
        expect(find.text('Reason: forgot to clock out'), findsOneWidget);
        expect(find.text('Voided the record'), findsOneWidget);
        expect(find.textContaining('A manager ·'), findsOneWidget, reason: 'a correction without a known name');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('no corrections: no Corrections section', (t) async {
      when(
        () => repo.getAttendanceRecordDetail(
          'st1',
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
        ),
      ).thenAnswer((_) async => recordDetail(withCorrection: false));
      await pump(t, AttendanceRecordView(record: record(), canCorrect: false, detailController: detailCtl()));
      expect(find.text('Punches'), findsOneWidget);
      expect(find.text('Corrections'), findsNothing);
    });

    testWidgets('loading, then a worded error with Try again', (t) async {
      final comp = Completer<AttendanceRecordDetail?>();
      when(
        () => repo.getAttendanceRecordDetail(
          'st1',
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, AttendanceRecordView(record: record(), canCorrect: false, detailController: detailCtl()));
      expect(find.byKey(const Key('recDetailLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
      expect(find.byKey(const Key('recDetailRetry')), findsOneWidget);
    });

    testWidgets('offline: the record still shows and the history says it needs an internet connection (no request)', (t) async {
      offline();
      await pump(t, AttendanceRecordView(record: record(), canCorrect: false, detailController: detailCtl()));
      expect(find.byKey(const Key('recIn')), findsOneWidget);
      expect(find.byKey(const Key('recDetailOffline')), findsOneWidget);
      expect(find.text('Punches'), findsNothing);
      verifyNever(
        () => repo.getAttendanceRecordDetail(
          any(),
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
        ),
      );
    });
  });

  // ── roster ────────────────────────────────────────────────────────────────────────────────────
  group('RosterView', () {
    RosterController put({bool manager = false}) {
      SharedPreferences.setMockInitialValues({'store_id': 'st1', if (manager) 'pos_employee_role': 'manager'});
      return Get.put(
        RosterController(
          repository: repo,
          cache: testTeamCache(),
          storeId: 'st1',
          employeeIdProvider: () async => 'e1',
          clock: () => DateTime(2026, 11, 11, 15),
          locationNames: () async => {'l1': 'Main shop'},
        ),
      )..canManageHint.value = manager;
    }

    void stubRoster(List<RosterShift> l) => when(
      () => repo.getRoster(
        'st1',
        from: any(named: 'from'),
        to: any(named: 'to'),
        employeeId: any(named: 'employeeId'),
      ),
    ).thenAnswer((_) async => l);

    for (final env in _Env.values) {
      testWidgets('${env.name}: the week Monday to Sunday with every shift; my own highlighted with "You"', (t) async {
        stubRoster([shift(location: 'l1', note: 'opening'), shift(id: 'sh2', employeeId: 'e2', name: 'Ali', start: DateTime(2026, 11, 11, 13), end: DateTime(2026, 11, 11, 21))]);
        await pump(t, RosterView(controller: put()), env);
        expect(find.text('9 Nov - 15 Nov 2026'), findsOneWidget);
        expect(find.text('Monday 9 Nov'), findsOneWidget);
        expect(find.text('Sunday 15 Nov'), findsOneWidget);
        expect(find.byKey(const Key('shift_sh1')), findsOneWidget);
        expect(find.byKey(const Key('shift_sh2')), findsOneWidget);
        expect(find.text('You'), findsOneWidget, reason: 'only my shift');
        expect(find.textContaining('Main shop'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a cashier is read only: no add button, no cancel, shifts do not open', (t) async {
      stubRoster([shift()]);
      await pump(t, RosterView(controller: put()));
      expect(find.byKey(const Key('rosterAdd')), findsNothing);
      expect(find.byKey(const Key('rosterCancel_sh1')), findsNothing);
    });

    testWidgets('a manager (online) gets Add shift and Cancel on a shift', (t) async {
      stubRoster([shift()]);
      await pump(t, RosterView(controller: put(manager: true)));
      expect(find.byKey(const Key('rosterAdd')), findsOneWidget);
      expect(find.byKey(const Key('rosterCancel_sh1')), findsOneWidget);
    });

    testWidgets('cancelling asks first and then cancels', (t) async {
      stubRoster([shift()]);
      await pump(t, RosterView(controller: put(manager: true)));
      when(() => repo.cancelRosterShift('st1', 'sh1')).thenAnswer((_) async => (success: true, message: null, code: null));
      await tapKey(t, 'rosterCancel_sh1');
      expect(find.text('Cancel this shift?'), findsOneWidget);
      verifyNever(() => repo.cancelRosterShift(any(), any()));
      await t.tap(find.byKey(const Key('rosterCancelYes')));
      await t.pumpAndSettle();
      verify(() => repo.cancelRosterShift('st1', 'sh1')).called(1);
      expect(find.byKey(const Key('shift_sh1')), findsNothing);
    });

    testWidgets('the arrows move the week and reload', (t) async {
      stubRoster([]);
      await pump(t, RosterView(controller: put()));
      await tapKey(t, 'rosterNext');
      verify(() => repo.getRoster('st1', from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 23), employeeId: null)).called(1);
      expect(find.text('16 Nov - 22 Nov 2026'), findsOneWidget);
    });

    testWidgets('OFFLINE with a remembered week: "Last synced <time> - read only", the shifts, and no editing even for a manager', (t) async {
      final cache = testTeamCache();
      await cache.saveRoster('st1', '2026-11-09', [shift(), shift(id: 'sh2', employeeId: 'e2', name: 'Ali')]);
      offline();
      final c = Get.put(RosterController(repository: repo, cache: cache, storeId: 'st1', employeeIdProvider: () async => 'e1', clock: () => DateTime(2026, 11, 11, 15)))..canManageHint.value = true;
      await pump(t, RosterView(controller: c));
      expect(find.byKey(const Key('teamLastSynced')), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
      expect(find.textContaining('read only'), findsOneWidget);
      expect(find.byKey(const Key('shift_sh1')), findsOneWidget);
      expect(find.byKey(const Key('rosterAdd')), findsNothing);
      expect(find.byKey(const Key('rosterCancel_sh1')), findsNothing);
      verifyNever(
        () => repo.getRoster(
          any(),
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      );
    });

    testWidgets('offline with nothing remembered: Needs internet; loading and error states', (t) async {
      offline();
      await pump(t, RosterView(controller: put()));
      expect(find.byKey(const Key('teamNeedsInternet')), findsOneWidget);
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      final comp = Completer<List<RosterShift>?>();
      when(
        () => repo.getRoster(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, RosterView(controller: put()));
      expect(find.byKey(const Key('teamLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
    });

    testWidgets('a saved shift with a warning shows the non-blocking notice', (t) async {
      stubRoster([]);
      final c = put(manager: true);
      await pump(t, RosterView(controller: c));
      c.applySaved(shift(warnings: ['OVER_60_HOURS_WEEK']));
      await t.pump();
      expect(find.byKey(const Key('rosterNotice')), findsOneWidget);
      expect(find.textContaining('more than 60 hours'), findsOneWidget);
      expect(find.byKey(const Key('shift_sh1')), findsOneWidget);
    });
  });

  group('ShiftSheet', () {
    ShiftController make({RosterShift? existing}) =>
        ShiftController(existing: existing, presetDay: DateTime(2026, 11, 9), repository: repo, storeId: 'st1', people: [employee('e1', 'Sam'), employee('e2', 'Ali')], locations: {'l1': 'Main shop'});
    Future<ShiftController> mount(WidgetTester t, ShiftController c, [_Env env = _Env.phone]) async {
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: ShiftSheet(controller: c)),
        ),
        env,
      );
      return c;
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: people, day, start / end, location and note; Add shift needs a person and the times', (t) async {
        final c = await mount(t, make(), env);
        for (final k in ['shiftPerson_e1', 'shiftPerson_e2', 'shiftDay', 'shiftStart', 'shiftEnd', 'shiftLoc_l1', 'shiftNote', 'shiftSave']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(t.widget<AppButton>(find.byKey(const Key('shiftSave'))).onPressed, isNull);
        await t.tap(find.byKey(const Key('shiftPerson_e1')));
        c.start.value = const TimeOfDay(hour: 9, minute: 0);
        c.end.value = const TimeOfDay(hour: 17, minute: 0);
        await t.pump();
        expect(find.byKey(const Key('shiftLength')), findsOneWidget);
        expect(find.text('8:00 hours'), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('shiftSave'))).onPressed, isNotNull);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('an overlap is explained with the clashing time and the sheet stays open; the length warns of an overnight shift', (t) async {
      final c = await mount(t, make());
      c.employeeId.value = 'e1';
      c.start.value = const TimeOfDay(hour: 22, minute: 0);
      c.end.value = const TimeOfDay(hour: 6, minute: 0);
      await t.pump();
      expect(find.text('8:00 hours (ends the next day)'), findsOneWidget);
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
          extra: {'conflictStartAt': DateTime(2026, 11, 9, 20).toUtc().toIso8601String(), 'conflictEndAt': DateTime(2026, 11, 10, 4).toUtc().toIso8601String()},
          shift: null,
        ),
      );
      await tapKey(t, 'shiftSave');
      expect(find.byKey(const Key('shiftError')), findsOneWidget);
      expect(find.text('This person already has a shift from 20:00 to 04:00 on Mon 9 Nov.'), findsOneWidget);
    });

    testWidgets('SHIFT_TOO_LONG is explained; a warning is kept as a notice and does not block', (t) async {
      final c = await mount(t, make());
      c.employeeId.value = 'e1';
      c.start.value = const TimeOfDay(hour: 6, minute: 0);
      c.end.value = const TimeOfDay(hour: 23, minute: 0);
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
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'SHIFT_TOO_LONG', extra: null, shift: null));
      await tapKey(t, 'shiftSave');
      expect(find.text('A shift can be at most 16 hours.'), findsOneWidget);
      when(
        () => repo.createRosterShift(
          'st1',
          employeeId: any(named: 'employeeId'),
          startAt: any(named: 'startAt'),
          endAt: any(named: 'endAt'),
          locationId: any(named: 'locationId'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => (success: true, message: null, code: null, extra: null, shift: shift(warnings: ['OVER_60_HOURS_WEEK'])));
      await tapKey(t, 'shiftSave');
      expect(c.warnings, ['OVER_60_HOURS_WEEK']);
    });

    testWidgets('editing prefills; offline says Needs internet and disables save', (t) async {
      final c = await mount(
        t,
        make(
          existing: shift(id: 'sh9', employeeId: 'e2', location: 'l1', note: 'x'),
        ),
      );
      expect(find.text('Save changes'), findsOneWidget);
      expect(c.employeeId.value, 'e2');
      Get.reset();
      offline();
      await mount(t, make());
      expect(find.byKey(const Key('shiftOffline')), findsOneWidget);
    });
  });

  // ── report ────────────────────────────────────────────────────────────────────────────────────
  group('TeamReportView', () {
    TeamReportController put({Future<void> Function(ShareParams)? share}) =>
        Get.put(TeamReportController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15), tzOffsetMinutes: () => -300, share: share, storeName: () async => 'Dev Store'));
    void stubReport(TeamReport r) => when(
      () => repo.getTeamReport(
        'st1',
        from: any(named: 'from'),
        to: any(named: 'to'),
        employeeId: any(named: 'employeeId'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenAnswer((_) async => r);

    for (final env in _Env.values) {
      testWidgets('${env.name}: period chips, total hours as h:mm, each person with days, breaks, late, missing clock-outs, corrections and rostered vs worked', (t) async {
        stubReport(report());
        await pump(t, TeamReportView(controller: put()), env);
        for (final k in ['repPeriod_week', 'repPeriod_month', 'repPeriod_thisMonth', 'repPeriod_custom']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('64:20'), findsOneWidget, reason: 'total worked 3860 minutes');
        expect(find.byKey(const Key('reportPerson_e1')), findsOneWidget);
        expect(find.text('40:15'), findsOneWidget);
        expect(find.text('2 · 35m'), findsOneWidget, reason: 'late count and minutes');
        expect(find.text('Rostered 40:00 · worked 40:15'), findsOneWidget);
        expect(find.textContaining('late = more than 10 min'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a period chip reloads the report', (t) async {
      stubReport(report());
      await pump(t, TeamReportView(controller: put()));
      await tapKey(t, 'repPeriod_thisMonth');
      verify(() => repo.getTeamReport('st1', from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 10), employeeId: null, tzOffsetMinutes: -300)).called(1);
    });

    testWidgets('Share PDF hands a PDF to the share sheet', (t) async {
      stubReport(report());
      ShareParams? shared;
      await pump(t, TeamReportView(controller: put(share: (p) async => shared = p)));
      await tapKey(t, 'reportShare');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump();
      expect(shared?.files?.single.mimeType, 'application/pdf');
    });

    testWidgets('a cashier\'s report is just themself', (t) async {
      stubReport(TeamReport(people: [report().people.first], totalWorkedMinutes: 2415));
      await pump(t, TeamReportView(controller: put()));
      expect(find.byKey(const Key('reportPerson_e1')), findsOneWidget);
      expect(find.byKey(const Key('reportPerson_e2')), findsNothing);
      expect(find.byKey(const Key('repPerson')), findsNothing);
    });

    testWidgets('empty / loading / error / offline', (t) async {
      stubReport(const TeamReport(people: []));
      await pump(t, TeamReportView(controller: put()));
      expect(find.text('No attendance'), findsOneWidget);
      expect(find.byKey(const Key('reportShare')), findsNothing);
      Get.reset();
      final comp = Completer<TeamReport?>();
      when(
        () => repo.getTeamReport(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, TeamReportView(controller: put()));
      expect(find.byKey(const Key('teamLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('RANGE_REQUIRED');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Choose a period of at most 93 days.'), findsOneWidget);
      Get.reset();
      offline();
      await pump(t, TeamReportView(controller: put()));
      expect(find.byKey(const Key('teamNeedsInternet')), findsOneWidget);
    });
  });

  // ── needs attention ───────────────────────────────────────────────────────────────────────────
  group('Needs attention: attendance problems and clock events', () {
    Future<(_Queue, PosNeedsAttentionController)> mount(WidgetTester t, {bool manager = true, List<AttendanceAnomaly> anomalies = const [], List<PendingClockRecord> rows = const []}) async {
      SharedPreferences.setMockInitialValues({'store_id': 'st1', if (manager) 'pos_employee_role': 'manager'});
      final q = _Queue()..setRows(rows);
      final sync = _Sync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => repo.getSalesNeedingReview(any())).thenAnswer((_) async => []);
      when(() => repo.getAttendanceAnomalies('st1')).thenAnswer((_) async => anomalies);
      final c = PosNeedsAttentionController(syncService: sync, posRepository: repo, paymentsRepository: FakePaymentsRepo(), teamQueue: q);
      Get.put<PosNeedsAttentionController>(c);
      await pump(t, PosNeedsAttentionView(controller: c));
      await t.pump(const Duration(milliseconds: 200));
      return (q, c);
    }

    testWidgets('a manager sees the attendance problems with Fix and Acknowledge; a problem with no record has no Fix', (t) async {
      await mount(
        t,
        anomalies: [
          anomaly(),
          anomaly(kind: 'late_sync', recordId: null, eventId: 'ev2', name: 'Bo'),
        ],
      );
      expect(find.text('Attendance problems'), findsOneWidget);
      expect(find.textContaining('Missing clock-out · Ali'), findsOneWidget);
      expect(find.textContaining('Recorded late (offline) · Bo'), findsOneWidget);
      expect(find.text('Clocked in more than 14 hours ago and never clocked out.'), findsOneWidget);
      expect(find.byKey(const Key('anomalyFix_ev9')), findsOneWidget);
      expect(find.byKey(const Key('anomalyAck_ev9')), findsOneWidget);
      expect(find.byKey(const Key('anomalyFix_ev2')), findsNothing);
      expect(find.byKey(const Key('anomalyAck_ev2')), findsOneWidget);
    });

    testWidgets('Acknowledge sends the ack and the problem leaves the list', (t) async {
      await mount(t, anomalies: [anomaly()]);
      when(() => repo.ackAttendanceAnomaly('st1', employeeId: 'e2', eventId: 'ev9', kind: 'missing_clock_out')).thenAnswer((_) async => (success: true, message: null, code: null));
      await tapKey(t, 'anomalyAck_ev9');
      verify(() => repo.ackAttendanceAnomaly('st1', employeeId: 'e2', eventId: 'ev9', kind: 'missing_clock_out')).called(1);
      expect(find.byKey(const Key('anomaly_ev9')), findsNothing);
    });

    testWidgets('Fix finds the record around the problem and opens the Correct sheet on it', (t) async {
      await mount(t, anomalies: [anomaly()]);
      when(
        () => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 6, 9), to: DateTime(2026, 11, 10, 9), employeeId: 'e2'),
      ).thenAnswer((_) async => [record(id: 'other'), record(id: 'rec9', employeeId: 'e2', name: 'Ali', noOut: true)]);
      await tapKey(t, 'anomalyFix_ev9');
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('corrReason')), findsOneWidget);
      expect(find.text('Add clock-out'), findsOneWidget);
    });

    testWidgets('a cashier is not shown the attendance problems and no request is made', (t) async {
      await mount(t, manager: false, anomalies: [anomaly()]);
      expect(find.text('Attendance problems'), findsNothing);
      verifyNever(() => repo.getAttendanceAnomalies(any()));
    });

    testWidgets('clock events made offline: waiting ones and refused ones with the reason, Retry and Dismiss (manager)', (t) async {
      final (q, _) = await mount(
        t,
        rows: [
          clockRow('w1', attempts: 2),
          clockRow('f1', action: 'clock_out', status: 'failed', message: 'Sign in with your PIN first. Attendance belongs to a team member, not to the owner account.'),
        ],
      );
      expect(find.text('Clock events not yet on the server'), findsOneWidget);
      expect(find.text('Waiting to retry (attempt 2)'), findsOneWidget);
      expect(find.text('Refused by the server — needs a decision'), findsOneWidget);
      expect(find.textContaining('Sign in with your PIN first'), findsOneWidget);
      expect(find.byKey(const Key('clockRetry_w1')), findsNothing, reason: 'a waiting one retries by itself');
      await t.tap(find.byKey(const Key('clockRetry_f1')));
      await t.pump();
      expect(q.retried, ['f1']);
      await t.tap(find.byKey(const Key('clockDismiss_f1')));
      await t.pumpAndSettle();
      expect(find.text('Dismiss this clock event?'), findsOneWidget);
      await t.tap(find.text('Dismiss').last);
      await t.pumpAndSettle();
      expect(q.dismissed, ['f1']);
    });

    testWidgets('nothing at all: "Everything is synced"', (t) async {
      await mount(t);
      expect(find.text('Everything is synced. Nothing needs attention.'), findsOneWidget);
    });
  });

  group('Attendance events never block closing a shift', () {
    test('UnsyncedGuard ignores waiting and refused clock events', () async {
      final q = _Queue()..setRows([clockRow('w1'), clockRow('f1', status: 'failed', message: 'x')]);
      Get.put<PendingTeamSyncService>(q);
      final status = await UnsyncedGuard.check();
      expect(status.blocks, isFalse);
      expect(q.items.length, 2);
    });
  });
}
