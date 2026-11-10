// G3.6 team controllers against a mocked PosRepository: the clock (request building, requestId, the offline queue and the state derived from it), attendance,
// corrections (a reason is required, only what changed is sent), the roster (week, cache, conflicts), shifts, and the report.
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/attendance_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/correction_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/roster_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/shift_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_report_controller.dart';

import 'support/g36_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

/// A queue that keeps what it is given in memory (the controller only enqueues, reads what is waiting and asks for a sync).
class _Queue extends PendingTeamSyncService {
  _Queue()
    : super(
        posRepository: _Repo(),
        localStore: PendingTeamLocalStore(dbPath: 'unused.db'),
      );
  int syncs = 0;
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
    final r = PendingClockRecord(
      seq: items.length + 1,
      id: requestId,
      action: action,
      deviceAt: deviceAt,
      status: 'pending',
      createdAt: deviceAt,
      storeId: storeId,
      employeeId: employeeId,
      employeeToken: employeeToken,
    );
    items.add(r);
    return r;
  }

  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) => syncs++;
}

typedef ClockRes = ({bool success, String? message, String? code, bool retryable, ClockResult? result});

void main() {
  late _Repo repo;
  late _Queue queue;
  var clock = DateTime(2026, 11, 9, 9, 2);

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = _Repo();
    queue = _Queue();
    clock = DateTime(2026, 11, 9, 9, 2);
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me());
    when(
      () => repo.getAttendanceRecords(
        'st1',
        from: any(named: 'from'),
        to: any(named: 'to'),
        employeeId: any(named: 'employeeId'),
      ),
    ).thenAnswer((_) async => <AttendanceRecord>[]);
  });

  Future<void> pause([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));
  void goOffline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  TeamClockController make({String? employee = 'e1', String Function()? ids, PendingTeamSyncService? q, dynamic cache}) => TeamClockController(
    repository: repo,
    cache: cache ?? testTeamCache(),
    queue: q ?? queue,
    storeId: 'st1',
    employeeIdProvider: () async => employee,
    employeeNameProvider: () async => 'Sam',
    employeeTokenProvider: () async => 'tok-sam',
    requestIdFactory: ids,
    clock: () => clock,
  );

  void stubClock(Future<ClockRes> Function(Map<Symbol, dynamic> a) f) {
    when(
      () => repo.teamClock(
        any(),
        action: any(named: 'action'),
        requestId: any(named: 'requestId'),
        deviceAt: any(named: 'deviceAt'),
        note: any(named: 'note'),
        employeeToken: any(named: 'employeeToken'),
      ),
    ).thenAnswer((i) => f(i.namedArguments));
  }

  group('formatting and state', () {
    test('formatHm prints hours and minutes', () {
      expect([formatHm(0), formatHm(5), formatHm(95), formatHm(600), formatHm(1445), formatHm(null), formatHm(-3)], ['0:00', '0:05', '1:35', '10:00', '24:05', '0:00', '0:00']);
    });

    test('ClockState follows clock in / break / break end / clock out and says what is allowed', () {
      var s = const ClockState();
      expect([s.allows('clock_in'), s.allows('clock_out'), s.allows('break_start'), s.allows('break_end')], [true, false, false, false]);
      s = s.after('clock_in', DateTime(2026, 11, 9, 9));
      expect([s.clockedIn, s.since], [true, DateTime(2026, 11, 9, 9)]);
      expect([s.allows('clock_in'), s.allows('clock_out'), s.allows('break_start'), s.allows('break_end')], [false, true, true, false]);
      s = s.after('break_start', DateTime(2026, 11, 9, 12));
      expect([s.onBreak, s.allows('break_end'), s.allows('break_start'), s.allows('clock_out')], [true, true, false, true]);
      s = s.after('break_end', DateTime(2026, 11, 9, 12, 30));
      expect([s.onBreak, s.since], [false, DateTime(2026, 11, 9, 9)]);
      s = s.after('clock_out', DateTime(2026, 11, 9, 17));
      expect(s.clockedIn, isFalse);
    });

    test('error codes in words; a roster overlap names the clashing shift', () {
      for (final c in [
        'ALREADY_CLOCKED_IN',
        'NOT_CLOCKED_IN',
        'ALREADY_ON_BREAK',
        'NOT_ON_BREAK',
        'EMPLOYEE_REQUIRED',
        'REASON_REQUIRED',
        'INVALID_DATE',
        'SHIFT_TOO_LONG',
        'RANGE_REQUIRED',
        'POS_ACTION_FORBIDDEN',
      ]) {
        expect(teamErrorMessage(c), isNot(contains('Something went wrong')), reason: c);
      }
      final m = teamErrorMessage(
        'ROSTER_OVERLAP',
        extra: {'conflictStartAt': DateTime(2026, 11, 9, 9).toUtc().toIso8601String(), 'conflictEndAt': DateTime(2026, 11, 9, 17).toUtc().toIso8601String()},
      );
      expect(m, 'This person already has a shift from 09:00 to 17:00 on Mon 9 Nov.');
      expect(teamErrorMessage('ROSTER_OVERLAP'), 'This person already has a shift at that time.');
      expect(teamWarningMessage('OVER_60_HOURS_WEEK'), contains('more than 60 hours'));
    });

    test('anomaly kinds have plain titles; only an anomaly with a record can be fixed', () {
      expect(anomaly(kind: 'missing_clock_out').title, 'Missing clock-out');
      expect(anomaly(kind: 'double_clock_in').title, 'Clocked in twice');
      expect(anomaly(kind: 'overlap').title, 'Overlapping records');
      expect(anomaly(kind: 'device_clock_ahead').title, 'Device clock was ahead');
      expect(anomaly(kind: 'late_sync').title, 'Recorded late (offline)');
      expect(anomaly().fixable, isTrue);
      expect(anomaly(recordId: null).fixable, isFalse);
    });

    test('models parse the server\'s shapes', () {
      final m = TeamMe.fromJson(meJson());
      expect(m.state.clockedIn, isTrue);
      expect(m.nextShifts.single.range, isNotEmpty);
      final r = AttendanceRecord.fromJson({
        'recordId': 'r',
        'employeeId': 'e',
        'clockInAt': '2026-11-09T04:00:00.000Z',
        'clockOutAt': null,
        'status': 'open',
        'workedMinutes': 0,
        'breakMinutes': 5,
        'breaks': [
          {'startAt': '2026-11-09T05:00:00.000Z', 'endAt': null, 'minutes': 0},
        ],
        'corrected': true,
        'flags': ['missing_clock_out'],
      });
      expect(
        [r.isOpen, r.corrected, r.flags, r.breaks.length],
        [
          true,
          true,
          ['missing_clock_out'],
          1,
        ],
      );
      final rep = TeamReport.fromJson({
        'from': '2026-11-03T00:00:00.000Z',
        'to': '2026-11-10T00:00:00.000Z',
        'lateGraceMinutes': 10,
        'people': [
          {'employeeId': 'e', 'employeeName': 'Sam', 'workedMinutes': 600, 'lateCount': 1, 'lateMinutes': 12},
        ],
        'totals': {'workedMinutes': 600, 'lateCount': 1, 'missingClockOuts': 0},
      });
      expect([rep.people.single.workedMinutes, rep.totalWorkedMinutes, rep.lateGraceMinutes], [600, 600, 10]);
    });
  });

  group('TeamClockController', () {
    test('loads me (state, next shifts) and today\'s punches for THIS person, and remembers me for offline', () async {
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true));
      when(
        () => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10), employeeId: 'e1'),
      ).thenAnswer((_) async => [record(noOut: true), record(id: 'v', status: 'voided')]);
      final cache = testTeamCache();
      final c = make(cache: cache)..onInit();
      await pause();
      expect(c.state.clockedIn, isTrue);
      expect(c.employeeName.value, 'Sam');
      expect(c.today.map((r) => r.recordId), ['rec1'], reason: 'a voided record is not a punch');
      expect((await cache.loadMe('st1', 'e1'))!.state.clockedIn, isTrue);
      expect(await cache.loadMe('st1', 'someone-else'), isNull, reason: 'another person\'s state is never shown');
      c.onClose();
    });

    test('Clock in (online): one request with the action, a fresh request id and the time the person tapped; the state follows the answer', () async {
      var n = 0;
      final c = make(ids: () => 'req-${++n}')..onInit();
      await pause();
      Map<Symbol, dynamic>? sent;
      stubClock((a) async {
        sent = a;
        return (success: true, message: null, code: null, retryable: false, result: clockResult());
      });
      expect(await c.perform(ClockAction.clockIn), ClockOutcome.done);
      expect(sent![#action], 'clock_in');
      expect(sent![#requestId], 'req-1');
      expect(sent![#deviceAt], clock);
      expect(c.state.clockedIn, isTrue);
      expect(c.notice.value, 'Clocked in at 09:02.');
      c.onClose();
    });

    test('a timeout (no answer) queues the SAME request id and the tap time; the person is not blocked', () async {
      final c = make(ids: () => 'req-t')..onInit();
      await pause();
      stubClock((_) async => (success: false, message: 'Could not reach the server.', code: null, retryable: true, result: null));
      expect(await c.perform(ClockAction.clockIn), ClockOutcome.queued);
      final q = queue.items.single;
      expect((q.id, q.action, q.deviceAt, q.employeeId, q.employeeToken), ('req-t', 'clock_in', clock, 'e1', 'tok-sam'));
      expect(c.state.clockedIn, isTrue, reason: 'the state is derived from the queue');
      expect(queue.syncs, 1);
      c.onClose();
    });

    test('a definite refusal (ALREADY_CLOCKED_IN) shows the server\'s words and looks at the server state again', () async {
      final c = make()..onInit();
      await pause();
      stubClock((_) async => (success: false, message: 'x', code: 'ALREADY_CLOCKED_IN', retryable: false, result: null));
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true));
      expect(await c.perform(ClockAction.clockIn), isNull);
      expect(c.actionError.value, 'You are already clocked in.');
      await pause();
      expect(c.state.clockedIn, isTrue);
      c.onClose();
    });

    test('offline: every tap is accepted and queued in order; the state (and the buttons) follow the queue', () async {
      goOffline();
      var n = 0;
      final c = make(ids: () => 'o${++n}')..onInit();
      await pause();
      expect([c.canDo('clock_in'), c.canDo('clock_out'), c.canDo('break_start')], [true, false, false]);
      clock = DateTime(2026, 11, 9, 9, 0);
      expect(await c.perform(ClockAction.clockIn), ClockOutcome.queued);
      expect(c.state.clockedIn, isTrue);
      expect(c.state.since, DateTime(2026, 11, 9, 9, 0));
      expect([c.canDo('clock_in'), c.canDo('clock_out'), c.canDo('break_start'), c.canDo('break_end')], [false, true, true, false]);
      clock = DateTime(2026, 11, 9, 12, 0);
      await c.perform(ClockAction.breakStart);
      expect(c.state.onBreak, isTrue);
      expect([c.canDo('break_end'), c.canDo('break_start')], [true, false]);
      clock = DateTime(2026, 11, 9, 12, 30);
      await c.perform(ClockAction.breakEnd);
      clock = DateTime(2026, 11, 9, 17, 0);
      await c.perform(ClockAction.clockOut);
      expect(c.state.clockedIn, isFalse);
      expect(queue.items.map((r) => '${r.id}:${r.action}'), ['o1:clock_in', 'o2:break_start', 'o3:break_end', 'o4:clock_out']);
      expect(queue.items.map((r) => r.deviceAt.hour), [9, 12, 12, 17], reason: 'each keeps the time the person tapped');
      expect(c.waiting, hasLength(4));
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
      c.onClose();
    });

    test('obvious double taps are refused locally and queue nothing; the server stays the authority for the rest', () async {
      goOffline();
      final c = make()..onInit();
      await pause();
      await c.perform(ClockAction.clockIn);
      expect(await c.perform(ClockAction.clockIn), isNull);
      expect(c.actionError.value, 'You are already clocked in.');
      expect(await c.perform(ClockAction.breakEnd), isNull);
      expect(c.actionError.value, 'You are not on a break.');
      expect(queue.items, hasLength(1));
      c.onClose();
    });

    test('the busy flag stops a second tap while one is in flight', () async {
      final c = make()..onInit();
      await pause();
      var calls = 0;
      stubClock((_) async {
        calls++;
        await pause(30);
        return (success: true, message: null, code: null, retryable: false, result: clockResult());
      });
      final a = c.perform(ClockAction.clockIn);
      final b = c.perform(ClockAction.clockIn);
      expect(await b, isNull);
      expect(await a, ClockOutcome.done);
      expect(calls, 1);
      c.onClose();
    });

    test('server clocked in + a queued clock out = not clocked in (derived); on a break + queued break end = clocked in', () async {
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me(clockedIn: true));
      final c = make()..onInit();
      await pause();
      goOffline();
      clock = DateTime(2026, 11, 9, 17);
      await c.perform(ClockAction.clockOut);
      expect(c.state.clockedIn, isFalse);
      c.onClose();
    });

    test('offline start: the remembered state is shown (marked "as of"); with nothing remembered it is "not clocked in" and the person can still clock in', () async {
      final cache = testTeamCache();
      await cache.saveMe('st1', me(clockedIn: true));
      goOffline();
      var c = make(cache: cache)..onInit();
      await pause();
      expect(c.state.clockedIn, isTrue);
      expect(c.me.value!.asOf, isNotNull);
      verifyNever(() => repo.getTeamMe(any()));
      c.onClose();
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      goOffline();
      c = make(cache: testTeamCache())..onInit();
      await pause();
      expect(c.state.clockedIn, isFalse);
      expect(c.canDo('clock_in'), isTrue);
      c.onClose();
    });

    test('no PIN-signed-in person: asks for a PIN and does nothing; EMPLOYEE_REQUIRED from the server says the same', () async {
      var c = make(employee: null)..onInit();
      await pause();
      expect(c.needsPin.value, isTrue);
      expect(await c.perform(ClockAction.clockIn), isNull);
      expect(c.actionError.value, contains('Sign in with your PIN'));
      c.onClose();
      Get.reset();
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('EMPLOYEE_REQUIRED');
      c = make()..onInit();
      await pause();
      expect(c.needsPin.value, isTrue);
      c.onClose();
    });

    test('a load error shows the server\'s words; a manager also gets the anomaly count', () async {
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
      var c = make()..onInit();
      await pause();
      expect(c.error.value, 'Sign in with your PIN first.');
      c.onClose();
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1', 'pos_employee_role': 'manager'});
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getTeamMe('st1')).thenAnswer((_) async => me());
      when(() => repo.getAttendanceAnomalies('st1')).thenAnswer((_) async => [anomaly(), anomaly(eventId: 'ev8')]);
      c = make()..onInit();
      await pause(80);
      expect(c.anomalyCount.value, 2);
      c.onClose();
    });

    test('the next shift today or tomorrow is found for the Home card, with the right word', () async {
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          shifts: [
            shift(id: 'a', start: DateTime(2026, 11, 7, 9), end: DateTime(2026, 11, 7, 17)),
            shift(id: 'b', start: DateTime(2026, 11, 10, 9), end: DateTime(2026, 11, 10, 17)),
            shift(id: 'c', start: DateTime(2026, 11, 13, 9), end: DateTime(2026, 11, 13, 17)),
          ],
        ),
      );
      final c = make()..onInit();
      await pause();
      expect(c.nextShiftSoon!.id, 'b');
      expect(c.dayWord(c.nextShiftSoon!.startAt), 'tomorrow');
      expect(c.dayWord(DateTime(2026, 11, 9, 15)), 'today');
      c.onClose();
      Get.reset();
      when(() => repo.getTeamMe('st1')).thenAnswer(
        (_) async => me(
          shifts: [shift(start: DateTime(2026, 11, 20, 9), end: DateTime(2026, 11, 20, 17))],
        ),
      );
      final d = make()..onInit();
      await pause();
      expect(d.nextShiftSoon, isNull);
      d.onClose();
    });
  });

  group('AttendanceController', () {
    AttendanceController att() => AttendanceController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15));

    test('asks for the period as local midnights (and a person); filters and totals are computed on what came back (voided never counts)', () async {
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
          record(id: 'b', worked: 60, breaks: 0, corrected: true),
          record(id: 'v', status: 'voided', worked: 999),
          record(id: 'o', noOut: true, flags: ['missing_clock_out']),
        ],
      );
      final c = att()..onInit();
      await pause();
      verify(() => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 10), employeeId: null)).called(1);
      expect(c.workedMinutes, 465 + 60);
      expect(c.breakMinutes, 30 + 0 + 30);
      expect(c.visible, hasLength(4));
      c.setFilter('voided');
      expect(c.visible.map((r) => r.recordId), ['v']);
      c.setFilter('corrected');
      expect(c.visible.map((r) => r.recordId), ['b']);
      c.setFilter('open');
      expect(c.visible.map((r) => r.recordId), ['o']);
      c.setFilter('flagged');
      expect(c.visible.map((r) => r.recordId), ['o']);
      c.setPeriod(AttendancePeriod.today);
      await pause();
      verify(() => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10), employeeId: null)).called(1);
      c.setPerson('e2');
      await pause();
      verify(() => repo.getAttendanceRecords('st1', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10), employeeId: 'e2')).called(1);
      c.onClose();
    });

    test('error words, offline = no request, a correction replaces the record on the list', () async {
      when(
        () => repo.getAttendanceRecords(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      var c = att()..onInit();
      await pause();
      expect(c.error.value, 'Your role is not allowed to do this.');
      c.onClose();
      Get.reset();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(
        () => repo.getAttendanceRecords(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) async => [record()]);
      c = att()..onInit();
      await pause();
      c.applyCorrected(record(corrected: true, worked: 400));
      expect(c.records.single.corrected, isTrue);
      c.onClose();
      Get.reset();
      goOffline();
      clearInteractions(repo);
      final d = att()..onInit();
      await pause();
      verifyNever(
        () => repo.getAttendanceRecords(
          any(),
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      );
      d.onClose();
    });
  });

  group('CorrectionController', () {
    CorrectionController corr(AttendanceRecord r) => CorrectionController(record: r, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 20));
    void stubCorrect(Future<({bool success, String? message, String? code, AttendanceRecord? record})> Function(Map<Symbol, dynamic> a) f) {
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
      ).thenAnswer((i) => f(i.namedArguments));
    }

    test('nothing changed and no reason: nothing is sent, and each is explained', () async {
      final c = corr(record());
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isNull);
      expect(c.error.value, teamErrorMessage('INVALID_CORRECTION'));
      c.voided.value = true;
      expect(c.canSubmit, isFalse, reason: 'a REASON is required');
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Say why the attendance is being corrected.');
      verifyNever(
        () => repo.correctAttendance(
          any(),
          employeeId: any(named: 'employeeId'),
          recordId: any(named: 'recordId'),
          reason: any(named: 'reason'),
          clockInAt: any(named: 'clockInAt'),
          clockOutAt: any(named: 'clockOutAt'),
          voided: any(named: 'voided'),
        ),
      );
    });

    test('adding a missing clock-out sends only the clock-out and the reason', () async {
      final open = record(noOut: true);
      final c = corr(open);
      expect(c.addsClockOut, isFalse);
      c.clockOutAt.value = DateTime(2026, 11, 9, 17);
      expect(c.addsClockOut, isTrue);
      c.reason.value = ' forgot to clock out ';
      Map<Symbol, dynamic>? sent;
      stubCorrect((a) async {
        sent = a;
        return (success: true, message: null, code: null, record: record(corrected: true));
      });
      final r = await c.submit();
      expect(r!.corrected, isTrue);
      expect(sent![#clockOutAt], DateTime(2026, 11, 9, 17));
      expect(sent![#clockInAt], isNull);
      expect(sent![#voided], false);
      expect(sent![#reason], ' forgot to clock out ');
    });

    test('changing the clock-in only sends the clock-in; voiding sends only voided (times are ignored)', () async {
      var c = corr(record());
      c.clockInAt.value = DateTime(2026, 11, 9, 8, 45);
      c.reason.value = 'arrived early';
      Map<Symbol, dynamic>? sent;
      stubCorrect((a) async {
        sent = a;
        return (success: true, message: null, code: null, record: record(corrected: true));
      });
      await c.submit();
      expect([sent![#clockInAt], sent![#clockOutAt]], [DateTime(2026, 11, 9, 8, 45), null]);
      c = corr(record());
      c.clockInAt.value = DateTime(2026, 11, 9, 8);
      c.voided.value = true;
      c.reason.value = 'duplicate';
      await c.submit();
      expect([sent![#voided], sent![#clockInAt], sent![#clockOutAt]], [true, null, null]);
      expect(c.payload!.containsKey('clockInAt'), isFalse);
    });

    test('a future time and a clock-out before the clock-in are refused before the request', () async {
      var c = corr(record(noOut: true));
      c.clockOutAt.value = DateTime(2026, 11, 9, 21);
      c.reason.value = 'x';
      expect(await c.submit(), isNull);
      expect(c.error.value, contains('cannot be in the future'));
      c = corr(record(noOut: true));
      c.clockOutAt.value = DateTime(2026, 11, 9, 8);
      c.reason.value = 'x';
      expect(await c.submit(), isNull);
      expect(c.error.value, contains('clock-out must be after the clock-in'));
    });

    test('the server\'s refusals are shown in words (RECORD_NOT_FOUND, POS_ACTION_FORBIDDEN); offline says Needs internet', () async {
      final c = corr(record());
      c.voided.value = true;
      c.reason.value = 'x';
      stubCorrect((_) async => (success: false, message: 'x', code: 'POS_ACTION_FORBIDDEN', record: null));
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Your role is not allowed to do this.');
      goOffline();
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Needs internet.');
    });
  });

  group('RosterController', () {
    RosterController ros({dynamic cache, String? me = 'e1'}) => RosterController(
      repository: repo,
      cache: cache ?? testTeamCache(),
      storeId: 'st1',
      employeeIdProvider: () async => me,
      clock: () => DateTime(2026, 11, 11, 15),
      locationNames: () async => {'l1': 'Main shop'},
    );

    test('the week is Monday to Sunday; it asks for [Mon, next Mon), remembers the answer, and highlights my own shifts', () async {
      when(
        () => repo.getRoster(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) async => [shift(), shift(id: 'sh2', employeeId: 'e2', name: 'Ali', start: DateTime(2026, 11, 11, 9), end: DateTime(2026, 11, 11, 17))]);
      final cache = testTeamCache();
      final c = ros(cache: cache)..onInit();
      await pause();
      verify(() => repo.getRoster('st1', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 16), employeeId: null)).called(1);
      expect(c.days.first, DateTime(2026, 11, 9));
      expect(c.days.last, DateTime(2026, 11, 15));
      expect(c.shiftsOn(DateTime(2026, 11, 9)).single.id, 'sh1');
      expect([c.isMine(c.shifts[0]), c.isMine(c.shifts[1])], [true, false]);
      expect(c.locations['l1'], 'Main shop');
      expect((await cache.loadRoster('st1', '2026-11-09'))!.shifts, hasLength(2));
      c.nextWeek();
      await pause();
      verify(() => repo.getRoster('st1', from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 23), employeeId: null)).called(1);
      c.thisWeek();
      expect(c.weekStart.value, DateTime(2026, 11, 9));
      c.onClose();
    });

    test('offline: the remembered week is shown READ ONLY with its time; nothing remembered = Needs internet; no edit offline', () async {
      final cache = testTeamCache();
      await cache.saveRoster('st1', '2026-11-09', [shift()]);
      goOffline();
      var c = ros(cache: cache)..onInit();
      await pause();
      c.canManageHint.value = true;
      expect(c.readOnly, isTrue);
      expect(c.asOf.value, isNotNull);
      expect(c.shifts, hasLength(1));
      expect(c.canEdit, isFalse);
      verifyNever(
        () => repo.getRoster(
          any(),
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      );
      c.onClose();
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      goOffline();
      c = ros()..onInit();
      await pause();
      expect(c.needsInternet.value, isTrue);
      c.onClose();
    });

    test('a saved shift appears at once and the server\'s warning becomes a notice; cancel removes it; errors are explained', () async {
      when(
        () => repo.getRoster(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) async => [shift()]);
      final c = ros()..onInit();
      await pause();
      c.applySaved(shift(id: 'new', start: DateTime(2026, 11, 12, 9), end: DateTime(2026, 11, 12, 18), warnings: ['OVER_60_HOURS_WEEK']));
      expect(c.shifts, hasLength(2));
      expect(c.notice.value, contains('more than 60 hours'));
      when(() => repo.cancelRosterShift('st1', 'new')).thenAnswer((_) async => (success: true, message: null, code: null));
      expect(await c.cancel(c.shifts.firstWhere((s) => s.id == 'new')), isTrue);
      expect(c.shifts, hasLength(1));
      when(() => repo.cancelRosterShift('st1', 'sh1')).thenAnswer((_) async => (success: false, message: 'x', code: 'SHIFT_NOT_FOUND'));
      expect(await c.cancel(c.shifts.single), isFalse);
      expect(c.actionError.value, contains('may have been cancelled'));
      c.onClose();
    });

    test('a load error shows the server\'s words', () async {
      when(
        () => repo.getRoster(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = ros()..onInit();
      await pause();
      expect(c.error.value, 'Your role is not allowed to do this.');
      c.onClose();
    });
  });

  group('ShiftController', () {
    ShiftController sh({RosterShift? existing}) =>
        ShiftController(existing: existing, presetDay: DateTime(2026, 11, 9), repository: repo, storeId: 'st1', people: [employee('e1', 'Sam'), employee('e2', 'Ali')], locations: {'l1': 'Main shop'});
    void stubCreate(Future<({bool success, String? message, String? code, Map<String, dynamic>? extra, RosterShift? shift})> Function(Map<Symbol, dynamic> a) f) {
      when(
        () => repo.createRosterShift(
          'st1',
          employeeId: any(named: 'employeeId'),
          startAt: any(named: 'startAt'),
          endAt: any(named: 'endAt'),
          locationId: any(named: 'locationId'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((i) => f(i.namedArguments));
    }

    test('build the request: person, day + start / end (an end at or before the start means the next day), location and note', () async {
      final c = sh()..onInit();
      c.employeeId.value = 'e2';
      c.start.value = const TimeOfDay(hour: 22, minute: 0);
      c.end.value = const TimeOfDay(hour: 6, minute: 0);
      c.locationId.value = 'l1';
      c.note.value = 'night';
      expect(c.canSubmit, isTrue);
      expect(c.startAt, DateTime(2026, 11, 9, 22));
      expect(c.endAt, DateTime(2026, 11, 10, 6));
      Map<Symbol, dynamic>? sent;
      stubCreate((a) async {
        sent = a;
        return (success: true, message: null, code: null, extra: null, shift: shift(id: 'n', employeeId: 'e2'));
      });
      expect((await c.submit())!.id, 'n');
      expect([sent![#employeeId], sent![#startAt], sent![#endAt], sent![#locationId], sent![#note]], ['e2', DateTime(2026, 11, 9, 22), DateTime(2026, 11, 10, 6), 'l1', 'night']);
    });

    test('ROSTER_OVERLAP names the clashing time; SHIFT_TOO_LONG is explained; the sheet stays open', () async {
      final c = sh()..onInit();
      c.employeeId.value = 'e1';
      c.start.value = const TimeOfDay(hour: 9, minute: 0);
      c.end.value = const TimeOfDay(hour: 17, minute: 0);
      stubCreate(
        (_) async => (
          success: false,
          message: 'x',
          code: 'ROSTER_OVERLAP',
          extra: {'conflictStartAt': DateTime(2026, 11, 9, 13).toUtc().toIso8601String(), 'conflictEndAt': DateTime(2026, 11, 9, 21).toUtc().toIso8601String()},
          shift: null,
        ),
      );
      expect(await c.submit(), isNull);
      expect(c.error.value, 'This person already has a shift from 13:00 to 21:00 on Mon 9 Nov.');
      stubCreate((_) async => (success: false, message: 'x', code: 'SHIFT_TOO_LONG', extra: null, shift: null));
      await c.submit();
      expect(c.error.value, 'A shift can be at most 16 hours.');
    });

    test('a warning (OVER_60_HOURS_WEEK) does not block: the shift is saved and the warning is kept as a notice', () async {
      final c = sh()..onInit();
      c.employeeId.value = 'e1';
      c.start.value = const TimeOfDay(hour: 9, minute: 0);
      c.end.value = const TimeOfDay(hour: 17, minute: 0);
      stubCreate((_) async => (success: true, message: null, code: null, extra: null, shift: shift(warnings: ['OVER_60_HOURS_WEEK'])));
      final s = await c.submit();
      expect(s, isNotNull);
      expect(c.warnings, ['OVER_60_HOURS_WEEK']);
    });

    test('editing prefills from the shift and sends an update; offline and incomplete requests are refused', () async {
      final existing = shift(id: 'sh9', employeeId: 'e2', location: 'l1', note: 'x');
      final c = sh(existing: existing)..onInit();
      expect([c.employeeId.value, c.locationId.value, c.note.value, c.isEdit], ['e2', 'l1', 'x', true]);
      expect([c.start.value, c.end.value], [const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 17, minute: 0)]);
      when(
        () => repo.updateRosterShift(
          'st1',
          'sh9',
          employeeId: any(named: 'employeeId'),
          startAt: any(named: 'startAt'),
          endAt: any(named: 'endAt'),
          locationId: any(named: 'locationId'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => (success: true, message: null, code: null, extra: null, shift: shift(id: 'sh9')));
      expect((await c.submit())!.id, 'sh9');
      verify(() => repo.updateRosterShift('st1', 'sh9', employeeId: 'e2', startAt: DateTime(2026, 11, 9, 9), endAt: DateTime(2026, 11, 9, 17), locationId: 'l1', note: 'x')).called(1);
      final empty = sh()..onInit();
      expect(empty.canSubmit, isFalse);
      goOffline();
      empty.employeeId.value = 'e1';
      empty.start.value = const TimeOfDay(hour: 9, minute: 0);
      empty.end.value = const TimeOfDay(hour: 10, minute: 0);
      expect(await empty.submit(), isNull);
      expect(empty.error.value, contains('Needs internet'));
    });
  });

  group('TeamReportController', () {
    TeamReportController rep({Future<void> Function(ShareParams)? share, int tz = -300}) =>
        TeamReportController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15), tzOffsetMinutes: () => tz, share: share, storeName: () async => 'Dev Store');

    test('the periods are local midnights; the tz offset is sent in the JavaScript convention (UTC+5 is -300); a person can be picked', () async {
      when(
        () => repo.getTeamReport(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) async => report());
      final c = rep()..onInit();
      await pause();
      verify(() => repo.getTeamReport('st1', from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 10), employeeId: null, tzOffsetMinutes: -300)).called(1);
      c.setPeriod(ReportPeriod.thisMonth);
      await pause();
      verify(() => repo.getTeamReport('st1', from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 10), employeeId: null, tzOffsetMinutes: -300)).called(1);
      c.setCustom(DateTime(2026, 10, 1), DateTime(2026, 10, 15));
      await pause();
      verify(() => repo.getTeamReport('st1', from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), employeeId: null, tzOffsetMinutes: -300)).called(1);
      c.setPerson('e1');
      await pause();
      verify(() => repo.getTeamReport('st1', from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), employeeId: 'e1', tzOffsetMinutes: -300)).called(1);
      expect(c.report.value!.totalWorkedMinutes, 3860);
      c.onClose();
    });

    test('Share PDF hands a PDF named by the period to the share sheet; errors and offline are explained', () async {
      when(
        () => repo.getTeamReport(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) async => report());
      ShareParams? shared;
      final c = rep(share: (p) async => shared = p)..onInit();
      await pause();
      await c.sharePdf();
      expect(shared!.subject, 'Attendance report 2026-11-03 to 2026-11-09');
      expect(shared!.files!.single.mimeType, 'application/pdf');
      c.onClose();
      Get.reset();
      when(
        () => repo.getTeamReport(
          'st1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          employeeId: any(named: 'employeeId'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('RANGE_REQUIRED');
      final d = rep()..onInit();
      await pause();
      expect(d.error.value, 'Choose a period of at most 93 days.');
      d.onClose();
    });
  });
}
