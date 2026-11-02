// Supporting pieces of 5C: the per-tender refund instructions (card machine / cash — the cash slice must equal what
// the drawer report expects), the close-shift / sign-out guard, and the new repository calls (quote, discard audit,
// replay with the saved employee token, queued payload shape).

import 'package:cryptography/cryptography.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/utils/refund_instructions.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockBaseClient extends Mock implements BaseClient {}

class MockPosRepository extends Mock implements PosRepository {}

class FakeSync extends PendingSaleSyncService {
  final List<MapEntry<String, Map<String, dynamic>>> enqueued = [];
  final List<String?> tokens = [];
  @override
  Future<void> enqueue(String id, Map<String, dynamic> payload, {String? employeeToken}) async {
    enqueued.add(MapEntry(id, payload));
    tokens.add(employeeToken);
  }

  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

Response res(dynamic data, {int? status}) => Response(data: data, statusCode: status, requestOptions: RequestOptions(path: ''));
DioException fail(DioExceptionType t, {int? status, dynamic body}) =>
    DioException(requestOptions: RequestOptions(path: ''), type: t, response: status != null ? res(body ?? {'message': 'x'}, status: status) : null);

AesGcmQueueCipher testCipher([int seed = 7]) => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, seed)));

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? 'mgr-token-now' : null,
    );
  });

  group('refund instructions per tender', () {
    List<String> plan(double amount, {double already = 0, int exp = 2}) {
      final splits = posAllocateRefund(
        tenders: const [(method: 'cash', amount: 40.0), (method: 'card', amount: 60.0)], // cash entered FIRST on purpose
        alreadyRefunded: already, amount: amount, exponent: exp,
      );
      return posRefundInstructions(splits, currency: 'USD', exponent: exp);
    }

    test('goes to the card machine first even though cash was entered first', () {
      expect(plan(25), ['Refund \$25.00 on the card machine']);
      expect(plan(60), ['Refund \$60.00 on the card machine']);
    });
    test('spills into cash only after the card is exhausted: "card machine" then "give cash"', () {
      expect(plan(70), ['Refund \$60.00 on the card machine', 'Give \$10.00 in cash from the drawer']);
      expect(plan(100), ['Refund \$60.00 on the card machine', 'Give \$40.00 in cash from the drawer']);
    });
    test('is cumulative across several refunds, like the server', () {
      expect(plan(25, already: 50), ['Refund \$10.00 on the card machine', 'Give \$15.00 in cash from the drawer']);
      expect(plan(25, already: 75), ['Give \$25.00 in cash from the drawer']);
    });
    test('the cash slice equals what the server deducts from expected cash (same allocation as the backend fixtures)', () {
      double cash(double amount, double already) => posAllocateRefund(
            tenders: const [(method: 'cash', amount: 40.0), (method: 'card', amount: 60.0)], alreadyRefunded: already, amount: amount, exponent: 2,
          ).where((s) => s.method == 'cash').fold(0.0, (a, s) => a + s.amount);
      expect(cash(70, 0), 10); // backend: refund 70 → card 60 + cash 10
      expect(cash(100, 0), 40);
      expect(cash(25, 50), 15);
      expect(cash(25, 75), 25);
      expect(cash(25, 0), 0);
    });
    test('cash change is NOT refundable (cash line is what was applied, not what was handed over)', () {
      final s = posAllocateRefund(tenders: const [(method: 'cash', amount: 40.0)], alreadyRefunded: 0, amount: 100, exponent: 2);
      expect(s.single.amount, 40);
    });
    test('a bank/other tender gets its own wording; JPY stays whole yen', () {
      final lines = posRefundInstructions(const [PosRefundSplit('other', 500), PosRefundSplit('cash', 250)], currency: 'JPY', exponent: 0);
      expect(lines.first, contains('bank transfer'));
      expect(lines.first, isNot(contains('.')));
      expect(lines.last, contains('cash'));
    });
    test('single-tender legacy sale', () {
      expect(posRefundInstructions(posAllocateRefund(tenders: const [(method: 'cash', amount: 20.0)], alreadyRefunded: 0, amount: 5, exponent: 2), currency: 'USD', exponent: 2), ['Give \$5.00 in cash from the drawer']);
    });
  });

  group('cashier attribution survives a different login at sync time', () {
    test('the queued payload keeps the cashier who rang the sale, whoever is signed in when it syncs', () async {
      final tmp = await Directory.systemTemp.createTemp('attr_');
      final store = PendingSaleLocalStore(dbPath: '${tmp.path}/q.db', cipher: testCipher());
      final repo = MockPosRepository();
      final sent = <Map<String, dynamic>>[];
      when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((i) async {
        sent.add(i.positionalArguments.first as Map<String, dynamic>);
        return (success: true, connectivityError: false, retryable: false, message: null, code: null);
      });
      final svc = PendingSaleSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's1', persistLastSync: false);

      // Cashier A rings the sale while offline …
      await store.enqueue('k1', {'storeId': 's1', 'sessionId': 'A', 'employeeId': 'cashier-A', 'employeeName': 'Ann', 'items': <dynamic>[]});
      // … then cashier B signs in (forced re-login) before connectivity returns. Nothing about B is consulted by the queue.
      SharedPreferences.setMockInitialValues({'pos_employee_id': 'cashier-B'});
      await svc.syncNow();

      expect(sent, hasLength(1));
      expect(sent.single['employeeId'], 'cashier-A');
      expect(sent.single['employeeName'], 'Ann');
      await store.close();
      await tmp.delete(recursive: true);
    });
  });

  group('UnsyncedGuard (close shift / sign out)', () {
    late Directory tmp;
    late PendingSaleLocalStore store;
    late MockPosRepository repo;
    late PendingSaleSyncService svc;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('guard_');
      store = PendingSaleLocalStore(dbPath: '${tmp.path}/q.db', cipher: testCipher());
      repo = MockPosRepository();
      svc = PendingSaleSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's1', persistLastSync: false);
      // sync can't reach the server: nothing gets resolved by the guard's own sync attempt
      when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken')))
          .thenAnswer((_) async => (success: false, connectivityError: true, retryable: true, message: null, code: null));
    });
    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    Map<String, dynamic> p(String session) => {'storeId': 's1', 'sessionId': session, 'items': <dynamic>[]};

    test('an empty queue never blocks', () async {
      final s = await UnsyncedGuard.check(sessionId: 'A', service: svc);
      expect(s.blocks, isFalse);
      expect(s.total, 0);
    });

    test('pending AND rejected sales of the session block, and are counted separately', () async {
      await store.enqueue('a1', p('A'));
      await store.enqueue('a2', p('A'));
      await store.markFailed('a2', 'rejected', errorCode: 'X');
      final s = await UnsyncedGuard.check(sessionId: 'A', service: svc);
      expect(s.blocks, isTrue);
      expect(s.pending, 1);
      expect(s.failed, 1);
      expect(s.total, 2);
    });

    test('only THIS session blocks its own shift close; another session\'s sales do not', () async {
      await store.enqueue('b1', p('B'));
      expect((await UnsyncedGuard.check(sessionId: 'A', service: svc)).blocks, isFalse);
      expect((await UnsyncedGuard.check(sessionId: 'B', service: svc)).blocks, isTrue);
    });

    test('sign-out (no session) is blocked by anything unresolved for the signed-in store', () async {
      await store.enqueue('b1', p('B'));
      expect((await UnsyncedGuard.check(service: svc)).blocks, isTrue);
    });

    test('once a manager has resolved them (discarded with a reason), they no longer block', () async {
      await store.enqueue('a1', p('A'));
      await store.markFailed('a1', 'rejected');
      await store.markDiscarding('a1', reason: 'customer left', discardedBy: 'm1');
      await svc.refreshCounts();
      expect((await UnsyncedGuard.check(sessionId: 'A', service: svc)).blocks, isFalse);
    });

    test('the guard first TRIES to sync, so a sale that was only waiting on a timer does not block needlessly', () async {
      await store.enqueue('a1', p('A'));
      when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken')))
          .thenAnswer((_) async => (success: true, connectivityError: false, retryable: false, message: null, code: null));
      await svc.refreshCounts();
      final s = await UnsyncedGuard.check(sessionId: 'A', service: svc);
      expect(s.blocks, isFalse);
      expect(await store.getAll(), isEmpty);
    });
  });

  group('PosRepository — 5C calls', () {
    late MockBaseClient client;
    late PosRepository repo;
    late List<Map<String, dynamic>> headers;
    late List<dynamic> bodies;

    void script(List<Object> outcomes) {
      var i = 0;
      when(() => client.post(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters'), requiresAuth: any(named: 'requiresAuth'), headers: any(named: 'headers')))
          .thenAnswer((inv) async {
        headers.add((inv.namedArguments[#headers] as Map?)?.cast<String, dynamic>() ?? {});
        bodies.add(inv.namedArguments[#data]);
        final o = outcomes[i++];
        if (o is DioException) throw o;
        return o as Response;
      });
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      Get.reset();
      client = MockBaseClient();
      repo = PosRepository(client: client, intents: IdempotencyIntentStore());
      headers = [];
      bodies = [];
    });

    test('quoteSale parses the server pricing, including the settingsVersion and the unit prices', () async {
      script([res({'success': true, 'data': {
        'subtotal': 59.97, 'discount': 6, 'tax': 4.45, 'total': 58.42, 'taxRate': 0.0825, 'currency': 'USD', 'currencyExponent': 2, 'settingsVersion': 3,
        'settingsVersionReplaced': true, 'lines': [{'variantId': 'v1', 'price': 19.99}],
      }})]);
      final r = await repo.quoteSale(storeId: 's', items: const [{'productId': 'p', 'variantId': 'v1', 'qty': 3}], discountType: 'percent', discountValue: 10, settingsVersion: 2);
      expect(r.quote!.total, 58.42);
      expect(r.quote!.settingsVersion, 3);
      expect(r.quote!.settingsVersionReplaced, isTrue);
      expect(r.quote!.unitPrices, {'v1': 19.99});
      expect((bodies.single as Map)['settingsVersion'], 2);
      expect((bodies.single as Map)['discountType'], 'percent');
    });

    test('quoteSale: unreachable (timeout / 5xx) → no quote and NO message (the till prices locally); a business refusal → its message', () async {
      script([fail(DioExceptionType.connectionError), fail(DioExceptionType.badResponse, status: 503), fail(DioExceptionType.badResponse, status: 403, body: {'code': 'POS_PLAN_REQUIRED', 'message': 'POS plan is not active for this store'})]);
      final a = await repo.quoteSale(storeId: 's', items: const []);
      final b = await repo.quoteSale(storeId: 's', items: const []);
      final c = await repo.quoteSale(storeId: 's', items: const []);
      expect([a.quote, a.message], [null, null]);
      expect([b.quote, b.message], [null, null]);
      expect(c.quote, isNull);
      expect(c.message, 'POS plan is not active for this store');
      expect(c.code, 'POS_PLAN_REQUIRED');
    });

    test('a queued sale keeps its time, settingsVersion and original key, is marked offline, and keeps the employee token only when a discount needs it', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      script([fail(DioExceptionType.connectionError), fail(DioExceptionType.connectionError)]);
      final when1 = DateTime.utc(2026, 11, 2, 10, 30);
      await repo.createSale(storeId: 's', sessionId: 'sess', registerId: 'r', employeeId: 'e', items: const [{'productId': 'p', 'variantId': 'v', 'qty': 1}],
          paymentMethod: 'cash', status: 'completed', settingsVersion: 4, clientCreatedAt: when1, clientTotal: 10, idempotencyKey: 'key-A');
      await repo.createSale(storeId: 's', sessionId: 'sess', registerId: 'r', employeeId: 'e', items: const [{'productId': 'p', 'variantId': 'v', 'qty': 1}],
          paymentMethod: 'cash', status: 'completed', discountType: 'percent', discountValue: 10, idempotencyKey: 'key-B');
      expect(sync.enqueued[0].key, 'key-A');
      final q = sync.enqueued[0].value;
      expect(q['offline'], true);
      expect(q['clientCreatedAt'], '2026-11-02T10:30:00.000Z');
      expect(q['settingsVersion'], 4);
      expect(q['sessionId'], 'sess');
      expect(q['idempotencyKey'], 'key-A');
      expect(q['clientTotal'], 10);
      expect(sync.tokens[0], isNull, reason: 'no discount → no manager token kept');
      expect(sync.tokens[1], 'mgr-token-now', reason: 'a discount sale keeps the token so the server can check it was valid when the sale was made');
    });

    test('replay uses the SAVED employee token (not whoever is logged in now) and the original key as Idempotency-Key', () async {
      script([res({'success': true, 'data': {}})]);
      await repo.submitRawSale({'idempotencyKey': 'key-A', 'storeId': 's'}, employeeToken: 'saved-sale-time-token');
      expect(headers.single['x-pos-employee-token'], 'saved-sale-time-token');
      expect(headers.single['Idempotency-Key'], 'key-A');
    });

    test('recordOfflineDiscard: recorded / already synced / unreachable are told apart', () async {
      script([
        res({'success': true, 'data': {'alreadyRecorded': false}}),
        fail(DioExceptionType.badResponse, status: 409, body: {'code': 'SALE_ALREADY_SYNCED', 'message': 'This sale already reached the server'}),
        fail(DioExceptionType.connectionError),
        fail(DioExceptionType.badResponse, status: 403, body: {'message': 'Only managers can discard an unsynced sale'}),
      ]);
      final ok = await repo.recordOfflineDiscard(storeId: 's', idempotencyKey: 'k', reason: 'left', employeeToken: 'mgr');
      expect(ok.recorded, isTrue);
      expect(headers.first['x-pos-employee-token'], 'mgr');
      expect((bodies.first as Map)['reason'], 'left');
      final synced = await repo.recordOfflineDiscard(storeId: 's', idempotencyKey: 'k', reason: 'left');
      expect(synced.alreadySynced, isTrue);
      expect(synced.recorded, isFalse);
      final offline = await repo.recordOfflineDiscard(storeId: 's', idempotencyKey: 'k', reason: 'left');
      expect(offline.connectivityError, isTrue);
      final denied = await repo.recordOfflineDiscard(storeId: 's', idempotencyKey: 'k', reason: 'left');
      expect(denied.recorded, isFalse);
      expect(denied.connectivityError, isFalse, reason: 'a manager-only refusal is final, not "try again later"');
    });
  });
}
