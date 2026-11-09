// G3.1 repository: request paths, the employee / approver headers, the Idempotency-Key on writes and the error code kept for the UI.
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

import 'support/inventory_fixtures.dart';

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
  final base = '${ApiConstants.apiPrefix}/pos/inventory';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    await AppPreferences.setPosEmployeeToken('tok-cashier');
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
      sent.add((url: i.positionalArguments[0] as String, headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(), data: i.namedArguments[#data], query: null, verb: 'POST'));
      final o = outcomes[n++];
      if (o is DioException) throw o;
      return o as Response;
    });
  }

  group('reads', () {
    test('overview: path, employee token header, parsed role-dependent fields', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {
            'role': 'manager',
            'skuCount': 4,
            'lowStockCount': 1,
            'outOfStockCount': 0,
            'expiredLots': 0,
            'expiringIn7Days': 0,
            'expiringIn30Days': 0,
            'openStockCount': null,
            'stockValueMinor': 5000,
            'variantsWithoutCost': 1,
            'currencyExponent': 2,
          },
        }),
      );
      final o = await repo.getInventoryOverview('st1');
      expect(sent.single.url, '$base/overview/st1');
      expect(sent.single.headers['x-pos-employee-token'], 'tok-cashier');
      expect(o!.stockValueMinor, 5000);
      expect(o.hasOpenCount, isFalse);
    });

    test('stock: search / filter / paging go as query parameters and rows parse', () async {
      scriptGet(
        _res({
          'success': true,
          'data': pageJson([row(id: 'a')], total: 9, page: 2, hasMore: true)..['items'] = [rowJson(id: 'a')],
        }),
      );
      final p = await repo.getInventoryStock('st1', search: ' latte ', filter: 'low', page: 2, limit: 10);
      expect(sent.single.url, '$base/stock/st1');
      expect(sent.single.query, {'search': 'latte', 'filter': 'low', 'page': 2, 'limit': 10});
      expect(p!.items.single.productName, 'Dev Latte');
      expect(p.hasMore, isTrue);
      expect(p.page, 2);
    });

    test('low-stock, lookup, variant, movements, limits use their paths and query', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {'items': [], 'total': 0, 'page': 1, 'hasMore': false},
        }),
      );
      await repo.getInventoryLowStock('st1');
      await repo.getInventoryMovements('st1', variantId: 'v1', type: 'sale', page: 3, limit: 5);
      expect(sent[0].url, '$base/low-stock/st1');
      expect(sent[1].url, '$base/movements/st1');
      expect(sent[1].query, {'variantId': 'v1', 'type': 'sale', 'page': 3, 'limit': 5});

      scriptGet(
        _res({
          'success': true,
          'data': [rowJson()],
        }),
      );
      final rows = await repo.lookupInventory('st1', ' 1000000000011 ');
      expect(sent.last.url, '$base/lookup/st1');
      expect(sent.last.query, {'code': '1000000000011'});
      expect(rows!.single.sku, 'DEV-LATTE');

      scriptGet(
        _res({
          'success': true,
          'data': detail().row.productName == '' ? {} : {...rowJson(), 'locations': [], 'lots': [], 'recentMovements': [], 'ledgerStartsAt': null, 'currencyExponent': 2},
        }),
      );
      final d = await repo.getInventoryVariant('st1', 'v1');
      expect(sent.last.url, '$base/variant/st1/v1');
      expect(d!.ledgerStartsAt, isNull);

      scriptGet(
        _res({
          'success': true,
          'data': {
            'currencyExponent': 2,
            'limits': [
              {'key': 'k', 'label': 'L', 'kind': 'minor', 'value': 2000, 'defaultValue': 2000},
            ],
          },
        }),
      );
      final l = await repo.getInventoryLimits('st1');
      expect(sent.last.url, '$base/limits/st1');
      expect(l!.limits.single.isMoney, isTrue);
    });

    test('a 403 is captured as lastErrorCode and the read returns null (cashier on movements)', () async {
      scriptGet(_fail(403, {'success': false, 'code': 'POS_ACTION_FORBIDDEN', 'message': 'no'}));
      expect(await repo.getInventoryMovements('st1'), isNull);
      expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
      scriptGet(
        _res({
          'success': true,
          'data': {'items': [], 'total': 0, 'page': 1, 'hasMore': false},
        }),
      );
      await repo.getInventoryMovements('st1');
      expect(repo.lastErrorCode, isNull); // reset on the next call
    });
  });

  group('adjust', () {
    test('POST path, body, employee token and an Idempotency-Key; no approver header on the first try', () async {
      scriptPost([
        _res({
          'success': true,
          'message': 'Stock updated',
          'data': {'stock': 18},
        }),
      ]);
      final r = await repo.adjustInventory('st1', 'v1', delta: -2, reason: 'correction', note: '  recount ');
      expect(sent.single.url, '$base/adjust/st1/v1');
      expect(sent.single.data, {'delta': -2, 'reason': 'correction', 'note': 'recount'});
      expect(sent.single.headers['x-pos-employee-token'], 'tok-cashier');
      expect((sent.single.headers['Idempotency-Key'] as String), isNotEmpty);
      expect(sent.single.headers.containsKey('x-pos-approver-token'), isFalse);
      expect(r.success, isTrue);
      expect(r.data!['stock'], 18);
    });

    test('POS_APPROVAL_REQUIRED keeps code + reasons; the retry carries x-pos-approver-token and the employee token stays the cashier\'s', () async {
      scriptPost([
        _fail(403, {
          'success': false,
          'code': 'POS_APPROVAL_REQUIRED',
          'approver': 'manager',
          'reasons': ['qty_above_limit'],
          'message': 'needs approval',
        }),
        _res({'success': true, 'data': {}}),
      ]);
      final first = await repo.adjustInventory('st1', 'v1', delta: -9, reason: 'correction');
      expect(first.success, isFalse);
      expect(first.code, 'POS_APPROVAL_REQUIRED');
      expect(repo.lastErrorCode, 'POS_APPROVAL_REQUIRED');
      expect(repo.lastErrorReasons, ['qty_above_limit']);
      final second = await repo.adjustInventory('st1', 'v1', delta: -9, reason: 'correction', approverToken: 'tok-mgr');
      expect(second.success, isTrue);
      expect(sent[1].headers['x-pos-approver-token'], 'tok-mgr');
      expect(sent[1].headers['x-pos-employee-token'], 'tok-cashier');
      expect(repo.lastErrorCode, isNull);
    });

    test('a retry after a lost response reuses the SAME key; after a definite answer the next change is a new intent', () async {
      scriptPost([
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.receiveTimeout,
        ),
        _res({'success': true, 'data': {}}),
        _res({'success': true, 'data': {}}),
      ]);
      await repo.adjustInventory('st1', 'v1', delta: 1, reason: 'restocked');
      await repo.adjustInventory('st1', 'v1', delta: 1, reason: 'restocked');
      expect(sent[1].headers['Idempotency-Key'], sent[0].headers['Idempotency-Key']);
      await repo.adjustInventory('st1', 'v1', delta: 1, reason: 'restocked');
      expect(sent[2].headers['Idempotency-Key'], isNot(sent[0].headers['Idempotency-Key']));
    });

    test('every documented error code is captured', () async {
      for (final code in ['DELTA_INVALID', 'REASON_INVALID', 'NOTE_REQUIRED', 'UNLIMITED_STOCK', 'POS_PIN_REQUIRED', 'POS_ACTION_FORBIDDEN', 'POS_OWNER_REQUIRED']) {
        scriptPost([
          _fail(400, {'success': false, 'code': code, 'message': 'm'}),
        ]);
        final r = await repo.adjustInventory('st1', 'v1', delta: 1, reason: 'other');
        expect(r.code, code);
        expect(repo.lastErrorCode, code);
      }
    });

    test('note and location are only sent when present', () async {
      scriptPost([
        _res({'success': true, 'data': {}}),
      ]);
      await repo.adjustInventory('st1', 'v1', delta: 1, reason: 'restocked', locationId: 'loc9');
      expect(sent.single.data, {'delta': 1, 'reason': 'restocked', 'locationId': 'loc9'});
    });
  });

  group('stock counts', () {
    test('start / enter / finish / cancel: paths, bodies, token and Idempotency-Key', () async {
      scriptPost([
        _res({
          'success': true,
          'data': {'_id': 'c1', 'status': 'open', 'items': []},
        }),
        _res({
          'success': true,
          'data': {'_id': 'c1', 'status': 'open', 'items': []},
        }),
        _res({
          'success': true,
          'data': {
            'count': {'_id': 'c1'},
            'applied': 2,
            'skipped': ['x'],
          },
        }),
        _res({
          'success': true,
          'data': {'_id': 'c1', 'status': 'cancelled'},
        }),
      ]);
      final s = await repo.startInventoryCount('st1');
      await repo.enterInventoryCount('st1', 'c1', 'i1', 7);
      final f = await repo.finishInventoryCount('st1', 'c1');
      final c = await repo.cancelInventoryCount('st1', 'c1');
      expect(sent.map((e) => e.url), ['$base/counts/st1', '$base/counts/st1/c1/items/i1', '$base/counts/st1/c1/finish', '$base/counts/st1/c1/cancel']);
      expect(sent[1].data, {'countedQty': 7});
      for (final e in sent) {
        expect(e.headers['x-pos-employee-token'], 'tok-cashier');
        expect((e.headers['Idempotency-Key'] as String), isNotEmpty);
      }
      expect(s.count!.id, 'c1');
      expect(f.result!.applied, 2);
      expect(f.result!.skipped, ['x']);
      expect(c.success, isTrue);
    });

    test('a cashier starting a count gets the server\'s refusal with its code', () async {
      scriptPost([
        _fail(403, {'success': false, 'code': 'POS_ACTION_FORBIDDEN', 'message': 'Managers only'}),
      ]);
      final r = await repo.startInventoryCount('st1');
      expect(r.success, isFalse);
      expect(r.code, 'POS_ACTION_FORBIDDEN');
      expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    });

    test('QTY_INVALID is captured on enter; list / get / find read paths work', () async {
      scriptPost([
        _fail(400, {'success': false, 'code': 'QTY_INVALID', 'message': 'bad'}),
      ]);
      final e = await repo.enterInventoryCount('st1', 'c1', 'i1', -1);
      expect(e.code, 'QTY_INVALID');

      scriptGet(
        _res({
          'success': true,
          'data': [
            {'_id': 'c1', 'status': 'open', 'items': []},
          ],
        }),
      );
      expect((await repo.listInventoryCounts('st1'))!.single.isOpen, isTrue);
      expect(sent.last.url, '$base/counts/st1');
      scriptGet(
        _res({
          'success': true,
          'data': {'_id': 'c1', 'status': 'open', 'items': []},
        }),
      );
      await repo.getInventoryCount('st1', 'c1');
      expect(sent.last.url, '$base/counts/st1/c1');
      scriptGet(
        _res({
          'success': true,
          'data': {
            'found': true,
            'item': {'_id': 'i1', 'variantId': 'v1', 'productName': 'P', 'systemQty': 3, 'countedQty': null},
          },
        }),
      );
      final f = await repo.findInventoryCountItem('st1', 'c1', ' 123 ');
      expect(sent.last.url, '$base/counts/st1/c1/find');
      expect(sent.last.query, {'code': '123'});
      expect(f!.found, isTrue);
      expect(f.item!.systemQty, 3);
      scriptGet(
        _res({
          'success': true,
          'data': {'found': false},
        }),
      );
      expect((await repo.findInventoryCountItem('st1', 'c1', 'zz'))!.found, isFalse);
    });
  });
}
