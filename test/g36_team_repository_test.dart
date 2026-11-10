// G3.6 repository: request paths, the employee token header, the stable Idempotency-Key of clock events (the request id), the retryable-or-definite answer
// the offline queue relies on, UTC times, and the roster / correction / report requests.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'support/g36_fixtures.dart';

class _MockClient extends Mock implements BaseClient {}

Response _res(dynamic data, {int? statusCode}) => Response(
  data: data,
  statusCode: statusCode ?? 200,
  requestOptions: RequestOptions(path: ''),
);
DioException _fail(int status, Map<String, dynamic> body) => DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.badResponse,
  response: _res(body, statusCode: status),
);
final _noNet = DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.connectionError,
);

void main() {
  late _MockClient client;
  late PosRepository repo;
  final sent = <({String url, Map<String, dynamic> headers, dynamic data, Map<String, dynamic>? query, String verb})>[];
  final base = '${ApiConstants.apiPrefix}/pos/team';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    await AppPreferences.setPosEmployeeToken('tok-emp');
    client = _MockClient();
    repo = PosRepository(client: client, intents: IdempotencyIntentStore());
    sent.clear();
  });

  void scriptGet(Object outcome) =>
      when(
        () => client.get(
          any(),
          queryParameters: any(named: 'queryParameters'),
          data: any(named: 'data'),
          requiresAuth: any(named: 'requiresAuth'),
          responseType: any(named: 'responseType'),
          validateStatus: any(named: 'validateStatus'),
          retryable: any(named: 'retryable'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((i) async {
        sent.add((
          url: i.positionalArguments[0] as String,
          headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(),
          data: null,
          query: (i.namedArguments[#queryParameters] as Map?)?.cast<String, dynamic>(),
          verb: 'GET',
        ));
        if (outcome is DioException) throw outcome;
        return outcome as Response;
      });

  void scriptWrite(String verb, List<Object> outcomes) {
    var n = 0;
    Future<Response> answer(Invocation i) async {
      sent.add((url: i.positionalArguments[0] as String, headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(), data: i.namedArguments[#data], query: null, verb: verb));
      final o = outcomes[n++];
      if (o is DioException) throw o;
      return o as Response;
    }

    if (verb == 'POST') {
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(answer);
    } else {
      when(
        () => client.patch(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(answer);
    }
  }

  group('reads', () {
    test('me: path, token, parsed state and next shifts', () async {
      scriptGet(_res({'success': true, 'data': meJson()}));
      final m = await repo.getTeamMe('st1');
      expect(sent.single.url, '$base/me/st1');
      expect(sent.single.headers['x-pos-employee-token'], 'tok-emp');
      expect(m!.state.clockedIn, isTrue);
      expect(m.nextShifts, hasLength(1));
    });

    test('records / roster / report: UTC ISO range, the person, and the tz offset as the JavaScript convention', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {'records': [], 'shifts': [], 'people': [], 'totals': {}, 'anomalies': []},
        }),
      );
      final from = DateTime.utc(2026, 11, 8, 19), to = DateTime.utc(2026, 11, 9, 19);
      await repo.getAttendanceRecords('st1', from: from, to: to, employeeId: 'e1');
      await repo.getRoster('st1', from: from, to: to);
      await repo.getTeamReport('st1', from: from, to: to, employeeId: 'e2', tzOffsetMinutes: -300);
      await repo.getAttendanceAnomalies('st1');
      expect(sent[0].url, '$base/records/st1');
      expect(sent[0].query, {'from': '2026-11-08T19:00:00.000Z', 'to': '2026-11-09T19:00:00.000Z', 'employeeId': 'e1'});
      expect(sent[1].url, '$base/roster/st1');
      expect(sent[1].query, {'from': '2026-11-08T19:00:00.000Z', 'to': '2026-11-09T19:00:00.000Z'});
      expect(sent[2].url, '$base/report/st1');
      expect(sent[2].query, {'from': '2026-11-08T19:00:00.000Z', 'to': '2026-11-09T19:00:00.000Z', 'employeeId': 'e2', 'tzOffsetMinutes': -300});
      expect(sent[3].url, '$base/anomalies/st1');
    });

    test('a failed read is null with the server code kept (a cashier asking for the anomalies)', () async {
      scriptGet(_fail(403, {'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}));
      expect(await repo.getAttendanceAnomalies('st1'), isNull);
      expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    });
  });

  group('clock', () {
    test('POST with the action, request id and the UTC time the person tapped; the Idempotency-Key IS the request id (stable)', () async {
      scriptWrite('POST', [
        _res({'success': true, 'data': clockResultJson()}),
        _res({'success': true, 'data': clockResultJson(duplicate: true)}),
      ]);
      final at = DateTime.utc(2026, 11, 9, 4, 2);
      final r = await repo.teamClock('st1', action: 'clock_in', requestId: 'req-1', deviceAt: at, note: '  ');
      final again = await repo.teamClock('st1', action: 'clock_in', requestId: 'req-1', deviceAt: at, employeeToken: 'tok-old');
      expect(sent[0].url, '$base/clock/st1');
      expect(sent[0].data, {'action': 'clock_in', 'requestId': 'req-1', 'deviceAt': '2026-11-09T04:02:00.000Z'});
      expect(sent[0].headers['Idempotency-Key'], 'clk-req-1');
      expect(sent[1].headers['Idempotency-Key'], 'clk-req-1');
      expect(sent[0].headers['x-pos-employee-token'], 'tok-emp');
      expect(sent[1].headers['x-pos-employee-token'], 'tok-old', reason: 'a queued replay goes out as the person who made it');
      expect(r.result!.state.clockedIn, isTrue);
      expect(again.result!.duplicate, isTrue);
    });

    test('answers: no connection and 5xx are RETRYABLE; 409 and 400 are DEFINITE (with the code)', () async {
      scriptWrite('POST', [
        _noNet,
        _fail(503, {'message': 'down'}),
        _fail(409, {'code': 'ALREADY_CLOCKED_IN', 'message': 'x'}),
        _fail(400, {'code': 'EMPLOYEE_REQUIRED', 'message': 'x'}),
      ]);
      Future<(bool, String?)> go() async {
        final r = await repo.teamClock('st1', action: 'clock_in', requestId: 'r', deviceAt: DateTime.utc(2026));
        return (r.retryable, r.code);
      }

      expect(await go(), (true, null));
      expect(await go(), (true, null));
      expect(await go(), (false, 'ALREADY_CLOCKED_IN'));
      expect(await go(), (false, 'EMPLOYEE_REQUIRED'));
      expect(repo.lastErrorCode, 'EMPLOYEE_REQUIRED');
    });
  });

  group('manager writes', () {
    test('correction: only what changed, UTC times, the reason trimmed; the corrected record parses', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {
            'record': {
              'recordId': 'rec1',
              'employeeId': 'e1',
              'employeeName': 'Sam',
              'clockInAt': '2026-11-09T04:00:00.000Z',
              'clockOutAt': '2026-11-09T12:00:00.000Z',
              'status': 'closed',
              'workedMinutes': 480,
              'breakMinutes': 0,
              'breaks': [],
              'corrected': true,
              'flags': [],
            },
          },
        }),
        _fail(400, {'code': 'REASON_REQUIRED', 'message': 'x'}),
      ]);
      final r = await repo.correctAttendance('st1', employeeId: 'e1', recordId: 'rec1', reason: ' forgot ', clockOutAt: DateTime.utc(2026, 11, 9, 12));
      expect(sent[0].url, '$base/corrections/st1');
      expect(sent[0].data, {'employeeId': 'e1', 'recordId': 'rec1', 'reason': 'forgot', 'clockOutAt': '2026-11-09T12:00:00.000Z'});
      expect(r.record!.corrected, isTrue);
      final bad = await repo.correctAttendance('st1', employeeId: 'e1', recordId: 'rec1', reason: '', voided: true);
      expect(sent[1].data, {'employeeId': 'e1', 'recordId': 'rec1', 'reason': '', 'voided': true});
      expect(bad.code, 'REASON_REQUIRED');
    });

    test('ack: employee, event and kind (with a note)', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {'acknowledged': true},
        }),
      ]);
      final r = await repo.ackAttendanceAnomaly('st1', employeeId: 'e2', eventId: 'ev9', kind: 'missing_clock_out', note: ' seen ');
      expect(sent.single.url, '$base/anomalies/st1/ack');
      expect(sent.single.data, {'employeeId': 'e2', 'eventId': 'ev9', 'kind': 'missing_clock_out', 'note': 'seen'});
      expect(r.success, isTrue);
    });

    test('roster: create (POST), update (PATCH), cancel (POST /cancel); an overlap comes back with the clashing times in `extra`; warnings parse', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {
            'shift': {
              'id': 'n',
              'employeeId': 'e1',
              'employeeName': 'Sam',
              'startAt': '2026-11-09T04:00:00.000Z',
              'endAt': '2026-11-09T12:00:00.000Z',
              'status': 'active',
              'warnings': ['OVER_60_HOURS_WEEK'],
            },
          },
        }),
        _fail(409, {'code': 'ROSTER_OVERLAP', 'message': 'x', 'conflictStartAt': '2026-11-09T08:00:00.000Z', 'conflictEndAt': '2026-11-09T16:00:00.000Z'}),
        _res({
          'success': true,
          'data': {'cancelled': true},
        }),
      ]);
      final made = await repo.createRosterShift('st1', employeeId: 'e1', startAt: DateTime.utc(2026, 11, 9, 4), endAt: DateTime.utc(2026, 11, 9, 12), locationId: 'l1', note: ' am ');
      expect(sent[0].url, '$base/roster/st1');
      expect(sent[0].data, {'employeeId': 'e1', 'startAt': '2026-11-09T04:00:00.000Z', 'endAt': '2026-11-09T12:00:00.000Z', 'locationId': 'l1', 'note': 'am'});
      expect(made.shift!.warnings, ['OVER_60_HOURS_WEEK']);
      final clash = await repo.createRosterShift('st1', employeeId: 'e1', startAt: DateTime.utc(2026, 11, 9, 5), endAt: DateTime.utc(2026, 11, 9, 9));
      expect(clash.code, 'ROSTER_OVERLAP');
      expect(clash.extra!['conflictStartAt'], '2026-11-09T08:00:00.000Z');
      final gone = await repo.cancelRosterShift('st1', 'n');
      expect(sent[2].url, '$base/roster/st1/n/cancel');
      expect(gone.success, isTrue);
      scriptWrite('PATCH', [
        _res({
          'success': true,
          'data': {
            'shift': {'id': 'n', 'employeeId': 'e2', 'startAt': '2026-11-09T04:00:00.000Z', 'endAt': '2026-11-09T12:00:00.000Z', 'status': 'active'},
          },
        }),
      ]);
      final up = await repo.updateRosterShift('st1', 'n', employeeId: 'e2', startAt: DateTime.utc(2026, 11, 9, 4));
      expect(sent[3].verb, 'PATCH');
      expect(sent[3].url, '$base/roster/st1/n');
      expect(sent[3].data, {'employeeId': 'e2', 'startAt': '2026-11-09T04:00:00.000Z'});
      expect(up.shift!.employeeId, 'e2');
    });
  });

  group('record detail', () {
    test('asks for team/records/:store/:employee/:record and reads punches and corrections', () async {
      scriptGet(_res({'success': true, 'data': recordDetailJson()}));
      final d = await repo.getAttendanceRecordDetail('st1', employeeId: 'e1', recordId: 'rec1');
      expect(sent.single.url, '$base/records/st1/e1/rec1');
      expect(d!.record.recordId, 'rec1');
      expect(d.punches.map((p) => p.type), ['clock_in', 'break_start', 'clock_out']);
      expect(d.corrections.first.byName, 'Mia Manager');
    });

    test('a refusal is null with the server code kept', () async {
      scriptGet(_fail(404, {'code': 'RECORD_NOT_FOUND', 'message': 'no'}));
      expect(await repo.getAttendanceRecordDetail('st1', employeeId: 'e1', recordId: 'x'), isNull);
      expect(repo.lastErrorCode, 'RECORD_NOT_FOUND');
    });
  });
}
