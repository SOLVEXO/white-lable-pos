// G3.4 repository: request paths, the employee / approver headers, the Idempotency-Key on writes (kept across an unknown outcome, dropped on a
// definite answer), the cashier-safe order list parsing, and the server's error code kept for the UI.
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

import 'support/g34_fixtures.dart';

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

void main() {
  late _MockClient client;
  late PosRepository repo;
  final sent = <({String url, Map<String, dynamic> headers, dynamic data, Map<String, dynamic>? query, String verb})>[];
  final base = '${ApiConstants.apiPrefix}/pos/supply';

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
    test('orders: path, status / supplier query, employee token, rows parse; a cashier list has no money', () async {
      scriptGet(
        _res({
          'success': true,
          'data': poListData([poJson(costs: false)]),
        }),
      );
      final l = await repo.getSupplyOrders('st1', status: 'approved', supplierId: 's9');
      expect(sent.single.url, '$base/orders/st1');
      expect(sent.single.query, {'status': 'approved', 'supplierId': 's9'});
      expect(sent.single.headers['x-pos-employee-token'], 'tok-emp');
      expect(l!.orders.single.totalMinor, isNull);
      expect(l.cur, usd);
      expect(l.raw, isNotNull);
    });

    test('"all" sends no status; the other reads use their paths', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'suppliers': [],
            'totals': {},
            'receipts': [],
            'order': poJson(),
            'supplier': {'id': 's1', 'name': 'A'},
            'aging': {},
            'entries': [],
          },
        }),
      );
      await repo.getSupplyOrders('st1');
      await repo.getSupplyOrder('st1', 'po1');
      await repo.getSuppliers('st1');
      await repo.getSupplier('st1', 's1');
      await repo.getSupplyReceipts('st1', supplierId: 's1');
      await repo.getPayables('st1');
      await repo.getSupplierLedger('st1', 's1');
      expect(sent[0].query, isEmpty);
      expect(sent.map((s) => s.url).skip(1), ['$base/orders/st1/po1', '$base/suppliers/st1', '$base/suppliers/st1/s1', '$base/receipts/st1', '$base/payables/st1', '$base/payables/st1/s1']);
    });

    test('a failed read is null with the server code kept', () async {
      scriptGet(_fail(403, {'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}));
      expect(await repo.getPayables('st1'), isNull);
      expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    });
  });

  group('writes', () {
    test('receive: POST with the employee token and an Idempotency-Key; the body carries the requestId', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'receipt': receiptJson(), 'order': null, 'duplicate': false},
        }),
      ]);
      final r = await repo.receiveSupply('st1', {'purchaseOrderId': 'po1', 'requestId': 'rid-1', 'lines': []});
      expect(sent.single.url, '$base/receipts/st1');
      expect(sent.single.headers['x-pos-employee-token'], 'tok-emp');
      expect(sent.single.headers['Idempotency-Key'], isNotEmpty);
      expect((sent.single.data as Map)['requestId'], 'rid-1');
      expect(r.success, isTrue);
      expect(r.result!.receipt.receiptNumber, 'GRN-000001');
    });

    test('an unknown outcome (no response) keeps the SAME Idempotency-Key on the retry; a definite answer drops it', () async {
      scriptWrite('POST', [
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionTimeout,
        ),
        _fail(409, {'code': 'OVER_RECEIPT', 'message': 'only 2 more'}),
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'receipt': receiptJson(), 'duplicate': true},
        }),
      ]);
      final body = {'purchaseOrderId': 'po1', 'requestId': 'rid-1', 'lines': []};
      final a = await repo.receiveSupply('st1', body);
      expect(a.success, isFalse);
      expect(a.code, isNull);
      final b = await repo.receiveSupply('st1', body);
      expect(b.code, 'OVER_RECEIPT');
      expect(b.message, 'only 2 more');
      expect(repo.lastErrorCode, 'OVER_RECEIPT');
      expect(sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key']);
      final c = await repo.receiveSupply('st1', body);
      expect(c.result!.duplicate, isTrue);
      expect(sent[2].headers['Idempotency-Key'], isNot(sent[1].headers['Idempotency-Key']));
    });

    test('pay: cash sends sessionId, bank does not; the approver token goes in x-pos-approver-token', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'duplicate': false,
            'payment': {'amountMinor': 1000, 'method': 'cash'},
            'balanceMinor': 4000,
          },
        }),
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'duplicate': false,
            'payment': {'amountMinor': 500, 'method': 'bank'},
            'balanceMinor': 3500,
          },
        }),
      ]);
      final cash = await repo.paySupplier('st1', 's1', amountMinor: 1000, method: 'cash', requestId: 'p1', sessionId: 'sess1', reference: ' ', approverToken: 'tok-mgr');
      final bank = await repo.paySupplier('st1', 's1', amountMinor: 500, method: 'bank', requestId: 'p2', sessionId: 'sess1', reference: 'TT-5');
      expect(sent[0].url, '$base/payments/st1/s1');
      expect(sent[0].data, {'amountMinor': 1000, 'method': 'cash', 'requestId': 'p1', 'sessionId': 'sess1'});
      expect(sent[0].headers['x-pos-approver-token'], 'tok-mgr');
      expect(sent[1].data, {'amountMinor': 500, 'method': 'bank', 'requestId': 'p2', 'reference': 'TT-5'});
      expect(sent[1].headers.containsKey('x-pos-approver-token'), isFalse);
      expect(cash.result!.balanceMinor, 4000);
      expect(bank.result!.method, 'bank');
    });

    test('order actions use their paths; approve passes the approver token; create / update use POST / PATCH with minor money', () async {
      scriptWrite('POST', [
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'order': poJson(status: 'approved')},
        }),
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'order': poJson(status: 'partially_received')},
        }),
        _res({
          'success': true,
          'data': {'currency': 'USD', 'currencyExponent': 2, 'order': poJson(status: 'draft')},
        }),
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'return': {'id': 'x', 'returnNumber': 'SR-1', 'supplierName': 'A', 'reason': 'damaged', 'creditMinor': 750, 'items': []},
          },
        }),
      ]);
      final a = await repo.supplyOrderAction('st1', 'po1', 'approve', approverToken: 'tk');
      await repo.supplyOrderAction('st1', 'po1', 'close-short');
      final created = await repo.createSupplyOrder('st1', {
        'supplierId': 's1',
        'items': [
          {'variantId': 'v1', 'quantityOrdered': 2, 'unitCostMinor': 1250},
        ],
      });
      final ret = await repo.createSupplierReturn('st1', {'receiptId': 'r1', 'requestId': 'x', 'items': []});
      expect(sent[0].url, '$base/orders/st1/po1/approve');
      expect(sent[0].headers['x-pos-approver-token'], 'tk');
      expect(sent[1].url, '$base/orders/st1/po1/close-short');
      expect(sent[2].url, '$base/orders/st1');
      expect(((sent[2].data as Map)['items'] as List).single['unitCostMinor'], 1250);
      expect(sent[3].url, '$base/returns/st1');
      expect(a.order!.status, 'approved');
      expect(a.order!.cur, usd, reason: 'the order takes the response currency');
      expect(created.order!.status, 'draft');
      expect(ret.result!.creditMinor, 750);

      scriptWrite('PATCH', [
        _res({
          'success': true,
          'data': {'order': poJson(status: 'draft')},
        }),
        _res({
          'success': true,
          'data': {
            'supplier': {'id': 's1', 'name': 'New'},
          },
        }),
      ]);
      await repo.updateSupplyOrder('st1', 'po1', {'notes': 'x'});
      final up = await repo.updateSupplier('st1', 's1', {'name': 'New'});
      expect(sent[4].url, '$base/orders/st1/po1');
      expect(sent[4].verb, 'PATCH');
      expect(sent[5].url, '$base/suppliers/st1/s1');
      expect(up.supplier!.name, 'New');
    });

    test('POS_APPROVAL_REQUIRED and POS_OWNER_REQUIRED come back as the code', () async {
      scriptWrite('POST', [
        _fail(403, {'code': 'POS_APPROVAL_REQUIRED', 'message': 'ask'}),
        _fail(403, {'code': 'POS_OWNER_REQUIRED', 'message': 'owner'}),
      ]);
      expect((await repo.supplyOrderAction('st1', 'po1', 'approve')).code, 'POS_APPROVAL_REQUIRED');
      expect((await repo.paySupplier('st1', 's1', amountMinor: 1, method: 'bank', requestId: 'r')).code, 'POS_OWNER_REQUIRED');
    });
  });
}
