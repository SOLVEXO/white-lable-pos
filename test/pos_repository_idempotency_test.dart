// Phase 5A: every mutating POS call carries an Idempotency-Key that belongs to
// the user's intent. A retry after an ambiguous failure (timeout, 5xx) reuses
// the SAME key; a definite rejection or success releases it. An ambiguous
// failure on a sale is queued under that key instead of being surfaced as a
// failure the cashier would re-ring.

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

class MockBaseClient extends Mock implements BaseClient {}

class FakeSync extends PendingSaleSyncService {
  final List<MapEntry<String, Map<String, dynamic>>> enqueued = [];
  int scheduled = 0;
  final List<({String key, String realNumber, String? saleId})> synced = [];

  @override
  Future<void> noteSynced(String key, {required String realNumber, String? saleId}) async => synced.add((key: key, realNumber: realNumber, saleId: saleId));

  @override
  Future<void> enqueue(String id, Map<String, dynamic> payload, {String? employeeToken}) async => enqueued.add(MapEntry(id, payload));

  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) => scheduled++;
}

Response _res(dynamic data, {int? statusCode}) =>
    Response(data: data, statusCode: statusCode, requestOptions: RequestOptions(path: ''));

DioException _fail(DioExceptionType type, {int? status, dynamic body}) => DioException(
      requestOptions: RequestOptions(path: ''),
      type: type,
      response: status != null ? _res(body ?? {'message': 'x'}, statusCode: status) : null,
    );

Map<String, dynamic> _saleJson() => {
      '_id': 'sale-1', 'saleNumber': 'S-1', 'storeId': 'st', 'sessionId': 'se', 'registerId': 'r', 'employeeId': 'e',
      'items': [], 'discount': 0, 'tax': 0, 'subtotal': 10.0, 'total': 10.0, 'paymentMethod': 'cash',
      'customerName': 'Walk-in', 'notes': '', 'status': 'completed', 'createdAt': '2026-01-01T00:00:00.000Z',
    };

void main() {
  late MockBaseClient client;
  late PosRepository repo;
  late List<Map<String, dynamic>> sentHeaders;
  late List<dynamic> sentData;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    client = MockBaseClient();
    repo = PosRepository(client: client, intents: IdempotencyIntentStore());
    sentHeaders = [];
    sentData = [];
  });

  /// Each call to post() pops the next outcome (a Response or a thrown DioException).
  void scriptPosts(List<Object> outcomes) {
    var i = 0;
    when(() => client.post(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        )).thenAnswer((inv) async {
      sentHeaders.add((inv.namedArguments[#headers] as Map).cast<String, dynamic>());
      sentData.add(inv.namedArguments[#data]);
      final o = outcomes[i++];
      if (o is DioException) throw o;
      return o as Response;
    });
  }

  Future<({bool success, dynamic sale, String? message, bool queued})> charge() => repo.createSale(
        storeId: 'st', sessionId: 'se', registerId: 'r', employeeId: 'e',
        items: const [{'productId': 'p', 'variantId': 'v', 'qty': 1}],
        paymentMethod: 'cash', status: 'completed',
      );

  group('createSale', () {
    test('sends the key both as the Idempotency-Key header and the body idempotencyKey', () async {
      scriptPosts([_res({'success': true, 'data': _saleJson()})]);
      await charge();
      final key = sentHeaders.single['Idempotency-Key'] as String;
      expect(key, isNotEmpty);
      expect((sentData.single as Map)['idempotencyKey'], key);
    });

    test('a retry of the same cart after an ambiguous failure reuses the SAME key', () async {
      scriptPosts([
        _fail(DioExceptionType.receiveTimeout), // lost response — may have been recorded
        _res({'success': true, 'data': _saleJson()}),
      ]);
      final first = await charge(); // no sync service registered → surfaced as a failure
      expect(first.success, isFalse);
      final second = await charge();
      expect(second.success, isTrue);
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
    });

    test('after a success the next identical cart is a NEW intent with a NEW key', () async {
      scriptPosts([_res({'success': true, 'data': _saleJson()}), _res({'success': true, 'data': _saleJson()})]);
      await charge();
      await charge();
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']));
    });

    test('a definite rejection (400) releases the key — the cashier fixing the cart starts fresh', () async {
      scriptPosts([_fail(DioExceptionType.badResponse, status: 400), _res({'success': true, 'data': _saleJson()})]);
      await charge();
      await charge();
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']));
    });

    test('an ambiguous failure (receive timeout) is queued under the same key and a sync is scheduled', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.receiveTimeout)]);

      final result = await charge();

      expect(result.queued, isTrue, reason: 'the cashier must not be told to ring it up again');
      expect(sync.enqueued.single.key, sentHeaders.single['Idempotency-Key']);
      expect((sync.enqueued.single.value)['idempotencyKey'], sentHeaders.single['Idempotency-Key']);
      expect(sync.scheduled, 1);
    });

    test('a sale with a Raast QR payment is NEVER queued for later: an ambiguous failure is just a failure (retry reuses the key and the paid payment)', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true, 'data': _saleJson()})]);
      Future<({bool success, dynamic sale, String? message, bool queued})> qrCharge() => repo.createSale(
            storeId: 'st', sessionId: 'se', registerId: 'r', employeeId: 'e',
            items: const [{'productId': 'p', 'variantId': 'v', 'qty': 1}],
            paymentMethod: 'raast_qr', payments: const [{'method': 'raast_qr', 'amount': 10.0, 'intentId': 'pi-1'}],
            idempotencyKey: 'KEY-QR', status: 'completed',
          );
      final first = await qrCharge();
      expect(first.queued, isFalse);
      expect(first.success, isFalse);
      expect(sync.enqueued, isEmpty);
      expect(sync.scheduled, 0);
      final second = await qrCharge(); // the cashier presses Charge again: same key, same payment
      expect(second.success, isTrue);
      expect(sentHeaders[1]['Idempotency-Key'], 'KEY-QR');
      expect(((sentData[1] as Map)['payments'] as List).single['intentId'], 'pi-1');
    });

    test('a 5xx is ambiguous too: queued, not surfaced as a failed sale', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.badResponse, status: 502)]);
      expect((await charge()).queued, isTrue);
      expect(sync.enqueued, hasLength(1));
    });

    test('IDEMPOTENCY_IN_PROGRESS (409) is ambiguous: queued with the same key', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.badResponse, status: 409, body: {'code': 'IDEMPOTENCY_IN_PROGRESS', 'message': 'still running'})]);
      expect((await charge()).queued, isTrue);
      expect(sync.enqueued, hasLength(1));
    });

    test('a BUSINESS 409 is final: shown to the user, never queued, key released', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([
        _fail(DioExceptionType.badResponse, status: 409, body: {'code': 'HELD_SALE_ALREADY_RESOLVED', 'message': 'This held sale was already completed or discarded'}),
        _res({'success': true, 'data': _saleJson()}),
      ]);
      final result = await charge();
      expect(result.queued, isFalse);
      expect(result.success, isFalse);
      expect(result.message, 'This held sale was already completed or discarded');
      expect(sync.enqueued, isEmpty);
      await charge();
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']), reason: 'a final answer ends the intent');
    });

    test('a 409 with no code at all is treated as a business conflict (final), not retried', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.badResponse, status: 409)]);
      expect((await charge()).queued, isFalse);
    });

    test('a POS-plan rejection (403 POS_PLAN_REQUIRED) is final: not queued, message surfaced', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([
        _fail(DioExceptionType.badResponse,
            status: 403, body: {'code': 'POS_PLAN_REQUIRED', 'message': 'POS plan is not active for this store'}),
      ]);
      final result = await charge();
      expect(result.queued, isFalse);
      expect(result.message, 'POS plan is not active for this store');
      expect(sync.enqueued, isEmpty);
    });

    test('once queued, the key is handed to the queue: ringing the same cart again is a new sale', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true, 'data': _saleJson()})]);
      await charge();
      await charge();
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']));
    });
  });

  group('other mutating calls carry an Idempotency-Key and reuse it on retry', () {
    test('refundSale', () async {
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true, 'data': {'refundedAmount': 5, 'newStatus': 'refunded'}})]);
      await repo.refundSale('sale-1', items: const [{'saleItemId': 'i1', 'qty': 1}]);
      await repo.refundSale('sale-1', items: const [{'saleItemId': 'i1', 'qty': 1}]);
      expect(sentHeaders[0]['Idempotency-Key'], isNotNull);
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
    });

    test('a refund of a DIFFERENT quantity is a different intent (new key)', () async {
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true})]);
      await repo.refundSale('sale-1', items: const [{'saleItemId': 'i1', 'qty': 1}]);
      await repo.refundSale('sale-1', items: const [{'saleItemId': 'i1', 'qty': 2}]);
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']));
    });

    test('voidSale', () async {
      scriptPosts([_fail(DioExceptionType.connectionTimeout), _res({'success': true})]);
      await repo.voidSale('sale-1', reason: 'mistake');
      await repo.voidSale('sale-1', reason: 'mistake');
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
    });

    test('cashAdjustment', () async {
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true, 'data': {'amount': 20}})]);
      await repo.cashAdjustment(sessionId: 'se', type: 'cash_in', amount: 20, reason: 'float', employeeId: 'e');
      await repo.cashAdjustment(sessionId: 'se', type: 'cash_in', amount: 20, reason: 'float', employeeId: 'e');
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
    });

    test('two genuine back-to-back cash-ins of the same amount are two intents (key released on success)', () async {
      scriptPosts([_res({'success': true, 'data': {'amount': 20}}), _res({'success': true, 'data': {'amount': 20}})]);
      await repo.cashAdjustment(sessionId: 'se', type: 'cash_in', amount: 20, reason: 'float', employeeId: 'e');
      await repo.cashAdjustment(sessionId: 'se', type: 'cash_in', amount: 20, reason: 'float', employeeId: 'e');
      expect(sentHeaders[1]['Idempotency-Key'], isNot(sentHeaders[0]['Idempotency-Key']));
    });

    test('openSession and closeSession', () async {
      scriptPosts([
        _fail(DioExceptionType.receiveTimeout),
        _res({'success': true, 'data': {'_id': 'se', 'storeId': 'st', 'registerId': 'r', 'employeeId': 'e', 'status': 'open', 'openingCash': 0}}),
        _fail(DioExceptionType.receiveTimeout),
        _res({'success': true, 'data': {'_id': 'se', 'storeId': 'st', 'registerId': 'r', 'employeeId': 'e', 'status': 'closed', 'openingCash': 0}}),
      ]);
      await repo.openSession(storeId: 'st', registerId: 'r', employeeId: 'e', openingCash: 50);
      await repo.openSession(storeId: 'st', registerId: 'r', employeeId: 'e', openingCash: 50);
      await repo.closeSession(sessionId: 'se', closingCash: 80);
      await repo.closeSession(sessionId: 'se', closingCash: 80);
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
      expect(sentHeaders[3]['Idempotency-Key'], sentHeaders[2]['Idempotency-Key']);
    });

    test('completeSale of a held sale', () async {
      scriptPosts([_fail(DioExceptionType.receiveTimeout), _res({'success': true, 'data': _saleJson()})]);
      await repo.completeSale(saleId: 'h1', paymentMethod: 'cash');
      await repo.completeSale(saleId: 'h1', paymentMethod: 'cash');
      expect(sentHeaders[1]['Idempotency-Key'], sentHeaders[0]['Idempotency-Key']);
    });
  });

  group('submitRawSale (queue replay)', () {
    final payload = {'storeId': 'st', 'idempotencyKey': 'queued-key-1'};

    test('replays with the queued sale\'s original key in the header', () async {
      scriptPosts([_res({'success': true, 'data': _saleJson()})]);
      final r = await repo.submitRawSale(payload);
      expect(r.success, isTrue);
      expect(sentHeaders.single['Idempotency-Key'], 'queued-key-1');
    });

    test('a successful replay records the server\'s real receipt number against the queued key (provisional → real)', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_res({'success': true, 'data': _saleJson()})]);
      expect((await repo.submitRawSale(payload)).success, isTrue);
      expect(sync.synced.single, (key: 'queued-key-1', realNumber: 'S-1', saleId: 'sale-1'));
    });

    test('a failed replay records nothing, and the provisional number is never in the request body', () async {
      final sync = FakeSync();
      Get.put<PendingSaleSyncService>(sync);
      scriptPosts([_fail(DioExceptionType.badResponse, status: 400, body: {'message': 'no'})]);
      await repo.submitRawSale(payload);
      expect(sync.synced, isEmpty);
      expect(sentData.toString(), isNot(contains('OFF-')));
    });

    test('replay: IDEMPOTENCY_IN_PROGRESS stays queued; a business 409 is final (marked failed, shown, never retried)', () async {
      scriptPosts([
        _fail(DioExceptionType.badResponse, status: 409, body: {'code': 'IDEMPOTENCY_IN_PROGRESS', 'message': 'x'}),
        _fail(DioExceptionType.badResponse, status: 409, body: {'code': 'SESSION_ALREADY_CLOSED', 'message': 'closed'}),
      ]);
      expect((await repo.submitRawSale(payload)).retryable, isTrue);
      final biz = await repo.submitRawSale(payload);
      expect(biz.retryable, isFalse);
      expect(biz.code, 'SESSION_ALREADY_CLOSED');
    });

    test('a 5xx / timeout is retryable (keep it queued), a 400/403 is final', () async {
      scriptPosts([
        _fail(DioExceptionType.badResponse, status: 503),
        _fail(DioExceptionType.receiveTimeout),
        _fail(DioExceptionType.badResponse, status: 403, body: {'code': 'POS_PLAN_REQUIRED', 'message': 'no plan'}),
      ]);
      expect((await repo.submitRawSale(payload)).retryable, isTrue);
      expect((await repo.submitRawSale(payload)).retryable, isTrue);
      final last = await repo.submitRawSale(payload);
      expect(last.retryable, isFalse);
      expect(last.code, 'POS_PLAN_REQUIRED');
    });
  });

  group('isRetryableStatus', () {
    test('network, 5xx, 408, 429 retry; only IDEMPOTENCY_IN_PROGRESS among 409s retries; other 4xx are final', () {
      expect(isRetryableStatus(null, null), isTrue);
      expect(isRetryableStatus(500, null), isTrue);
      expect(isRetryableStatus(503, null), isTrue);
      expect(isRetryableStatus(408, null), isTrue);
      expect(isRetryableStatus(429, null), isTrue);
      expect(isRetryableStatus(409, 'IDEMPOTENCY_IN_PROGRESS'), isTrue);
      expect(isRetryableStatus(409, 'HELD_SALE_ALREADY_RESOLVED'), isFalse);
      expect(isRetryableStatus(409, 'SALE_CHANGED_CONCURRENTLY'), isFalse);
      expect(isRetryableStatus(409, null), isFalse);
      for (final c in [400, 401, 403, 404, 422]) {
        expect(isRetryableStatus(c, null), isFalse, reason: '$c is a definite answer');
      }
    });
  });
}
