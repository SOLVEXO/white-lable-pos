// G3.5 repository: request paths, the employee / approver headers, the stable Idempotency-Key of cash writes (the request id), the retryable-or-definite
// answer the offline queue relies on, minor-unit money, the multipart receipt upload and the daybook query.
import 'dart:io';

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

import 'support/g35_fixtures.dart';

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
  final sent = <({String url, Map<String, dynamic> headers, dynamic data, Map<String, dynamic>? query})>[];
  final base = '${ApiConstants.apiPrefix}/pos/cash';

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
        ));
        if (outcome is DioException) throw outcome;
        return outcome as Response;
      });

  void scriptPost(List<Object> outcomes) {
    var n = 0;
    when(
      () => client.post(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        requiresAuth: any(named: 'requiresAuth'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer((i) async {
      sent.add((url: i.positionalArguments[0] as String, headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(), data: i.namedArguments[#data], query: null));
      final o = outcomes[n++];
      if (o is DioException) throw o;
      return o as Response;
    });
  }

  Response moveOk({bool duplicate = false}) => _res({
    'success': true,
    'data': {
      'currency': 'USD',
      'currencyExponent': 2,
      'duplicate': duplicate,
      'movement': {'type': 'cash_in', 'category': 'float_topup', 'amountMinor': 1250},
    },
  });

  group('reads', () {
    test('config: path, employee token, parsed lists, limits and currency', () async {
      scriptGet(_res({'success': true, 'data': cashConfigJson(currency: 'KWD', exponent: 3)}));
      final c = await repo.getCashConfig('st1');
      expect(sent.single.url, '$base/config/st1');
      expect(sent.single.headers['x-pos-employee-token'], 'tok-emp');
      expect(c!.cur, kwd);
      expect(c.cashOutCategories, contains('safe_drop'));
      expect(c.cashOutApprovalAboveMinor, 5000);
    });

    test('expenses: status / from / to go as query (UTC ISO), "all" sends no status; totals and rows parse with the response currency', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'expenses': [expenseJson()],
            'totalsByCategoryMinor': {'rent': 12000},
          },
        }),
      );
      final l = await repo.getExpenses('st1', status: 'approved', from: DateTime.utc(2026, 11, 8, 19), to: DateTime.utc(2026, 11, 9, 19));
      await repo.getExpenses('st1');
      expect(sent[0].url, '$base/expenses/st1');
      expect(sent[0].query, {'status': 'approved', 'from': '2026-11-08T19:00:00.000Z', 'to': '2026-11-09T19:00:00.000Z'});
      expect(sent[1].query, isEmpty);
      expect(l!.expenses.single.cur, usd);
      expect(l.totalsByCategoryMinor['rent'], 12000);
    });

    test('one expense and its receipt link use their paths; the link parses and never prints its url', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'expense': expenseJson(hasReceipt: true), 'url': 'https://signed.example/r?sig=1', 'expiresInSeconds': 300, 'mimeType': 'image/png'},
        }),
      );
      final e = await repo.getExpense('st1', 'x1');
      final l = await repo.getExpenseReceiptLink('st1', 'x1');
      expect(sent[0].url, '$base/expenses/st1/x1');
      expect(sent[1].url, '$base/expenses/st1/x1/receipt');
      expect(e!.hasReceipt, isTrue);
      expect(l!.url, contains('sig=1'));
      expect(l.expiresInSeconds, 300);
      expect(l.toString(), isNot(contains('signed.example')));
    });

    test('daybook: from / to (+ register) as UTC ISO; the shifts, lines and the unreconciled flag parse', () async {
      scriptGet(_res({'success': true, 'data': daybookJson()}));
      final d = await repo.getDaybook('st1', from: DateTime.utc(2026, 11, 8, 19), to: DateTime.utc(2026, 11, 9, 19), registerId: 'r1');
      expect(sent.single.url, '$base/daybook/st1');
      expect(sent.single.query, {'from': '2026-11-08T19:00:00.000Z', 'to': '2026-11-09T19:00:00.000Z', 'registerId': 'r1'});
      expect(d!.reconciled, isFalse);
      expect(d.unreconciledMinor, -300);
    });

    test('a failed read is null with the server code kept (a cashier asking for what is not theirs)', () async {
      scriptGet(_fail(403, {'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}));
      expect(await repo.getExpense('st1', 'x1'), isNull);
      expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    });
  });

  group('cash movement', () {
    test('POST with the minor amount, request id, shift and UTC device time; the Idempotency-Key IS the request id (stable)', () async {
      scriptPost([moveOk(), moveOk()]);
      final at = DateTime.utc(2026, 11, 9, 7, 30);
      final r = await repo.recordCashMovement('st1', type: 'cash_in', category: 'float_topup', amountMinor: 1250, sessionId: 'se1', requestId: 'req-1', note: '  ', occurredAt: at);
      await repo.recordCashMovement('st1', type: 'cash_in', category: 'float_topup', amountMinor: 1250, sessionId: 'se1', requestId: 'req-1', occurredAt: at);
      expect(sent[0].url, '$base/movements/st1');
      expect(sent[0].data, {'type': 'cash_in', 'category': 'float_topup', 'amountMinor': 1250, 'sessionId': 'se1', 'requestId': 'req-1', 'occurredAt': '2026-11-09T07:30:00.000Z'});
      expect(sent[0].headers['Idempotency-Key'], 'cash-req-1');
      expect(sent[1].headers['Idempotency-Key'], 'cash-req-1');
      expect(sent[0].headers['x-pos-employee-token'], 'tok-emp');
      expect(r.success, isTrue);
      expect(r.result!.amountMinor, 1250);
    });

    test('a queued replay goes out as the employee who made it, with the manager approval in x-pos-approver-token; a note is trimmed', () async {
      scriptPost([moveOk(duplicate: true)]);
      final r = await repo.recordCashMovement(
        'st1',
        type: 'cash_out',
        category: 'other_out',
        amountMinor: 5,
        sessionId: 'se1',
        requestId: 'req-2',
        note: ' float ',
        employeeToken: 'tok-old',
        approverToken: 'tok-mgr',
      );
      expect(sent.single.headers['x-pos-employee-token'], 'tok-old');
      expect(sent.single.headers['x-pos-approver-token'], 'tok-mgr');
      expect((sent.single.data as Map)['note'], 'float');
      expect(r.result!.duplicate, isTrue);
    });

    test('answers: no connection and 5xx are RETRYABLE; 409 NO_OPEN_SHIFT, 403 POS_APPROVAL_REQUIRED and 400 are DEFINITE (with the code)', () async {
      scriptPost([
        _noNet,
        _fail(503, {'message': 'down'}),
        _fail(409, {'code': 'NO_OPEN_SHIFT', 'message': 'closed'}),
        _fail(403, {'code': 'POS_APPROVAL_REQUIRED', 'message': 'ask'}),
        _fail(400, {'code': 'NOTE_REQUIRED', 'message': 'note'}),
      ]);
      Future<({bool retryable, String? code})> go() async {
        final r = await repo.recordCashMovement('st1', type: 'cash_in', category: 'float_topup', amountMinor: 1, sessionId: 's', requestId: 'r');
        return (retryable: r.retryable, code: r.code);
      }

      expect(await go(), (retryable: true, code: null));
      expect(await go(), (retryable: true, code: null));
      expect(await go(), (retryable: false, code: 'NO_OPEN_SHIFT'));
      expect(await go(), (retryable: false, code: 'POS_APPROVAL_REQUIRED'));
      expect(await go(), (retryable: false, code: 'NOTE_REQUIRED'));
      expect(repo.lastErrorCode, 'NOTE_REQUIRED');
    });
  });

  group('expenses', () {
    Response expOk({bool duplicate = false}) => _res({
      'success': true,
      'data': {'currency': 'USD', 'currencyExponent': 2, 'duplicate': duplicate, 'expense': expenseJson()},
    });

    test('a cash expense sends the shift, minor amount, payee and note; bank / other never send a session', () async {
      scriptPost([expOk(), expOk()]);
      final cash = await repo.recordExpense(
        'st1',
        category: 'rent',
        method: 'cash',
        amountMinor: 12000,
        requestId: 'ex-1',
        sessionId: 'se1',
        payee: ' Landlord ',
        note: 'Nov',
        occurredAt: DateTime.utc(2026, 11, 9, 9),
      );
      await repo.recordExpense('st1', category: 'rent', method: 'bank', amountMinor: 12000, requestId: 'ex-2', sessionId: 'se1');
      expect(sent[0].url, '$base/expenses/st1');
      expect(sent[0].data, {
        'category': 'rent',
        'method': 'cash',
        'amountMinor': 12000,
        'requestId': 'ex-1',
        'sessionId': 'se1',
        'payee': 'Landlord',
        'note': 'Nov',
        'occurredAt': '2026-11-09T09:00:00.000Z',
      });
      expect(sent[0].headers['Idempotency-Key'], 'exp-ex-1');
      expect((sent[1].data as Map).containsKey('sessionId'), isFalse);
      expect(cash.result!.expense.number, 'EXP-000001');
    });

    test('duplicate:true parses; retryable vs definite like a movement', () async {
      scriptPost([
        expOk(duplicate: true),
        _noNet,
        _fail(409, {'code': 'NO_OPEN_SHIFT', 'message': 'x'}),
      ]);
      expect((await repo.recordExpense('st1', category: 'rent', method: 'cash', amountMinor: 1, requestId: 'a', sessionId: 's')).result!.duplicate, isTrue);
      expect((await repo.recordExpense('st1', category: 'rent', method: 'cash', amountMinor: 1, requestId: 'a', sessionId: 's')).retryable, isTrue);
      final r = await repo.recordExpense('st1', category: 'rent', method: 'cash', amountMinor: 1, requestId: 'a', sessionId: 's');
      expect((r.retryable, r.code), (false, 'NO_OPEN_SHIFT'));
    });

    test('a decision: approve / reject with a note, the same key until the server answers, and a definite answer frees it', () async {
      scriptPost([
        _noNet,
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'expense': expenseJson(status: 'rejected', decisionNote: 'dup')},
        }),
        _fail(409, {'code': 'ALREADY_DECIDED', 'message': 'x'}),
        _fail(409, {'code': 'ALREADY_DECIDED', 'message': 'x'}),
      ]);
      final a = await repo.decideExpense('st1', 'x1', approve: false, note: ' dup ');
      expect(a.success, isFalse);
      final b = await repo.decideExpense('st1', 'x1', approve: false, note: 'dup');
      expect(sent[0].url, '$base/expenses/st1/x1/decision');
      expect(sent[0].data, {'decision': 'reject', 'note': 'dup'});
      expect(sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key'], reason: 'an unknown outcome is retried with the same key');
      expect(b.expense!.status, 'rejected');
      final c = await repo.decideExpense('st1', 'x1', approve: true);
      expect(c.code, 'ALREADY_DECIDED');
      expect(sent[2].data, {'decision': 'approve'});
      await repo.decideExpense('st1', 'x1', approve: true);
      expect(sent[3].headers['Idempotency-Key'], isNot(sent[2].headers['Idempotency-Key']), reason: 'a definite answer ended that intent');
    });
  });

  group('receipt upload', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rcpt_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('multipart field "file" to the expense\'s receipt path, as the employee who made it; retryable vs definite', () async {
      final f = File('${tmp.path}/p.jpg')..writeAsBytesSync([0xFF, 0xD8, 1, 2, 3]);
      scriptPost([
        _res({'success': true, 'data': {}}),
        _noNet,
        _fail(400, {'code': 'FILE_TYPE', 'message': 'x'}),
      ]);
      final ok = await repo.uploadExpenseReceipt('st1', 'x1', f, employeeToken: 'tok-old');
      expect(sent[0].url, '$base/expenses/st1/x1/receipt');
      expect(sent[0].data, isA<FormData>());
      expect((sent[0].data as FormData).files.single.key, 'file');
      expect((sent[0].data as FormData).files.single.value.filename, 'p.jpg');
      expect(sent[0].headers['x-pos-employee-token'], 'tok-old');
      expect(ok.success, isTrue);
      expect((await repo.uploadExpenseReceipt('st1', 'x1', f)).retryable, isTrue);
      final bad = await repo.uploadExpenseReceipt('st1', 'x1', f);
      expect((bad.retryable, bad.code), (false, 'FILE_TYPE'));
    });
  });
}
