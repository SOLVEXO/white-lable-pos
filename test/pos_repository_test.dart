// Direct unit tests for PosRepository's own logic — response envelope
// unwrapping, paging, the offline-queue/connectivity detection from Phase 3
// of the last session, and requiresAuth usage. Mocks BaseClient (the seam
// added in this session's Phase 1); never touches Dio or a real network
// call. Deliberately plain `test()` blocks, not `testWidgets` — nothing
// here shows a CustomAppSnackbar or navigates, so the GetX/snackbar
// fragility documented in the controller test files doesn't apply.
//
// Not every one of PosRepository's ~35 methods gets its own test: most are
// structurally identical thin wrappers around _data()/_ok() (a GET that
// unwraps a single object, a DELETE that checks {success}). Depth goes into
// createSale/refundSale/voidSale (highest-stakes, explicitly named in the
// task) and getSales (paging) instead of repeating the same shape 30 times.

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

class MockBaseClient extends Mock implements BaseClient {}

/// A real GetxController subclass, not a mocktail `Mock` — Get.put/delete
/// drive real lifecycle hooks (onStart/onDelete) that read internal fields
/// (`InternalFinalCallback`) a `Mock`'s implementation leaves null,
/// crashing with "type 'Null' is not a subtype of type
/// `InternalFinalCallback<void>`" the moment it's registered. Overriding
/// just enqueue() also sidesteps the real implementation's sqflite access.
class FakePendingSaleSyncService extends PendingSaleSyncService {
  final List<MapEntry<String, Map<String, dynamic>>> enqueued = [];

  @override
  Future<void> enqueue(String id, Map<String, dynamic> payload) async {
    enqueued.add(MapEntry(id, payload));
  }
}

Response _res(dynamic data) => Response(data: data, requestOptions: RequestOptions(path: ''));

Map<String, dynamic> _saleJson({String status = 'completed'}) => {
      '_id': 'sale-1',
      'saleNumber': 'S-0001',
      'storeId': 'store-1',
      'sessionId': 'session-1',
      'registerId': 'register-1',
      'employeeId': 'employee-1',
      'items': [
        {'productId': 'p1', 'name': 'Widget', 'qty': 2, 'price': 5.0, 'lineTotal': 10.0},
      ],
      'discount': 0,
      'tax': 0,
      'subtotal': 10.0,
      'total': 10.0,
      'paymentMethod': 'cash',
      'customerName': 'Walk-in',
      'notes': '',
      'status': status,
      'createdAt': '2026-01-01T00:00:00.000Z',
    };

void main() {
  late MockBaseClient client;
  late PosRepository repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
    // Every authenticated call goes through _employeeAuthHeaders(), which
    // reads flutter_secure_storage — a real platform channel with no test
    // double by default. Left unmocked, the awaited read/write never
    // completes at all (see pos_pin_login_test.dart's identical fix last
    // session).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  setUp(() {
    client = MockBaseClient();
    repo = PosRepository(client: client);
  });

  // Common stub shape for the three POST-based methods under test — each
  // takes different positional/named args, so these helpers just narrow
  // the `any()` matchers per call site rather than sharing one signature.
  void stubPost(Response response) {
    when(() => client.post(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async => response);
  }

  group('response envelope — createSale', () {
    test('unwraps {success:true, data:{...}} into a populated PosSaleModel', () async {
      stubPost(_res({'success': true, 'data': _saleJson()}));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      expect(result.success, isTrue);
      expect(result.sale?.id, 'sale-1');
      expect(result.sale?.total, 10.0);
      expect(result.message, isNull);
      expect(result.queued, isFalse);
    });

    test('a {success:false, message:...} response surfaces the message and no sale', () async {
      stubPost(_res({'success': false, 'message': 'Insufficient stock for Widget'}));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      expect(result.success, isFalse);
      expect(result.sale, isNull);
      expect(result.message, 'Insufficient stock for Widget');
    });
  });

  group('response envelope — refundSale', () {
    test('unwraps a successful refund', () async {
      stubPost(_res({
        'success': true,
        'data': {'refundedAmount': 10.0, 'newStatus': 'refunded'},
      }));

      final result = await repo.refundSale('sale-1');

      expect(result.success, isTrue);
      expect(result.refundedAmount, 10.0);
      expect(result.newStatus, 'refunded');
    });

    test('a {success:false} response surfaces the backend message', () async {
      stubPost(_res({'success': false, 'message': 'Refund window has expired.'}));

      final result = await repo.refundSale('sale-1');

      expect(result.success, isFalse);
      expect(result.message, 'Refund window has expired.');
      expect(result.refundedAmount, isNull);
    });
  });

  group('response envelope — voidSale', () {
    test('returns true on {success:true}', () async {
      stubPost(_res({'success': true}));

      expect(await repo.voidSale('sale-1'), isTrue);
    });

    test('returns false on {success:false} (message goes to a toast, not the return value)', () async {
      stubPost(_res({'success': false, 'message': 'Sale already voided.'}));

      expect(await repo.voidSale('sale-1'), isFalse);
    });
  });

  group('paging — getSales', () {
    test('parses a realistic paged payload', () async {
      when(() => client.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            data: any(named: 'data'),
            requiresAuth: any(named: 'requiresAuth'),
            responseType: any(named: 'responseType'),
            validateStatus: any(named: 'validateStatus'),
            retryable: any(named: 'retryable'),
          )).thenAnswer((_) async => _res({
            'success': true,
            'data': {
              'sales': [_saleJson(), _saleJson(status: 'held')],
              'pagination': {'page': 1, 'totalPages': 3, 'total': 25},
            },
          }));

      final result = await repo.getSales(storeId: 'store-1');

      expect(result.items, hasLength(2));
      expect(result.total, 25);
      expect(result.totalPages, 3);
      expect(result.hasMore, isTrue, reason: 'page 1 of 3');
    });

    test('returns an empty page on {success:false}', () async {
      when(() => client.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            data: any(named: 'data'),
            requiresAuth: any(named: 'requiresAuth'),
            responseType: any(named: 'responseType'),
            validateStatus: any(named: 'validateStatus'),
            retryable: any(named: 'retryable'),
          )).thenAnswer((_) async => _res({'success': false, 'message': 'nope'}));

      final result = await repo.getSales(storeId: 'store-1');

      expect(result.items, isEmpty);
      expect(result.total, 0);
      expect(result.hasMore, isFalse);
    });

    test('a malformed/missing pagination block still returns the items with sane defaults', () async {
      when(() => client.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            data: any(named: 'data'),
            requiresAuth: any(named: 'requiresAuth'),
            responseType: any(named: 'responseType'),
            validateStatus: any(named: 'validateStatus'),
            retryable: any(named: 'retryable'),
          )).thenAnswer((_) async => _res({
            'success': true,
            'data': {'sales': [_saleJson()]}, // no 'pagination' key at all
          }));

      final result = await repo.getSales(storeId: 'store-1');

      expect(result.items, hasLength(1));
      expect(result.total, 1, reason: 'falls back to items.length when pagination.total is missing');
      expect(result.totalPages, 1);
      expect(result.hasMore, isFalse, reason: 'page 1 of totalPages-default-1 is not "more"');
    });
  });

  group('offline queue / connectivity detection (createSale)', () {
    late FakePendingSaleSyncService syncService;

    setUp(() {
      syncService = FakePendingSaleSyncService();
    });

    tearDown(() {
      if (Get.isRegistered<PendingSaleSyncService>()) Get.delete<PendingSaleSyncService>();
    });

    test('a connection error queues the sale and reports queued:true when a sync service is registered', () async {
      Get.put<PendingSaleSyncService>(syncService);
      when(() => client.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            requiresAuth: any(named: 'requiresAuth'),
            headers: any(named: 'headers'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
        idempotencyKey: 'idem-1',
      );

      expect(result.queued, isTrue);
      expect(result.success, isFalse);
      expect(syncService.enqueued, hasLength(1));
      expect(syncService.enqueued.single.key, 'idem-1', reason: 'queued under the same key the backend dedupes on');
    });

    test('a connection error without a registered sync service just fails normally (queued:false)', () async {
      // No Get.put here — Get.isRegistered<PendingSaleSyncService>() is false.
      when(() => client.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            requiresAuth: any(named: 'requiresAuth'),
            headers: any(named: 'headers'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      expect(result.queued, isFalse);
      expect(result.success, isFalse);
    });

    test('a real server rejection (badResponse) is never queued, even with a sync service registered', () async {
      Get.put<PendingSaleSyncService>(syncService);
      when(() => client.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            requiresAuth: any(named: 'requiresAuth'),
            headers: any(named: 'headers'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.badResponse,
        response: _res({'message': 'Validation failed'}),
      ));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      expect(result.queued, isFalse,
          reason: 'a validation error would just fail identically on retry — must not be queued');
      expect(syncService.enqueued, isEmpty);
    });

    test('connectionTimeout is also treated as a connectivity error', () async {
      Get.put<PendingSaleSyncService>(syncService);
      when(() => client.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            requiresAuth: any(named: 'requiresAuth'),
            headers: any(named: 'headers'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionTimeout,
      ));

      final result = await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      expect(result.queued, isTrue);
    });

    test('submitRawSale reports connectivityError on a connection error, distinct from a validation failure',
        () async {
      when(() => client.post(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            requiresAuth: any(named: 'requiresAuth'),
            headers: any(named: 'headers'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));

      final result = await repo.submitRawSale({'storeId': 'store-1'});

      expect(result.success, isFalse);
      expect(result.connectivityError, isTrue);
    });
  });

  group('auth headers', () {
    // Spot-check across GET/POST/DELETE and employee/session/sale endpoints
    // rather than all 44 call sites individually — every one of them was
    // confirmed (via `grep -c requiresAuth` vs `grep -c '_client\.'`) to
    // pass requiresAuth explicitly, 44/44, all `true`. PosRepository sits
    // entirely behind PIN login, so that's expected: nothing in this
    // repository is meant to be reachable unauthenticated.
    test('getEmployees (GET) requires auth', () async {
      when(() => client.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            data: any(named: 'data'),
            requiresAuth: any(named: 'requiresAuth'),
            responseType: any(named: 'responseType'),
            validateStatus: any(named: 'validateStatus'),
            retryable: any(named: 'retryable'),
          )).thenAnswer((_) async => _res({'success': true, 'data': <dynamic>[]}));

      await repo.getEmployees('store-1');

      verify(() => client.get(any(), queryParameters: any(named: 'queryParameters'), data: any(named: 'data'),
          requiresAuth: true, responseType: any(named: 'responseType'), validateStatus: any(named: 'validateStatus'),
          retryable: any(named: 'retryable'))).called(1);
    });

    test('createSale (POST) requires auth', () async {
      stubPost(_res({'success': true, 'data': _saleJson()}));

      await repo.createSale(
        storeId: 'store-1',
        sessionId: 'session-1',
        registerId: 'register-1',
        employeeId: 'employee-1',
        items: const [],
        paymentMethod: 'cash',
        status: 'completed',
      );

      verify(() => client.post(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters'),
          requiresAuth: true, headers: any(named: 'headers'))).called(1);
    });

    test('deleteEmployee (DELETE) requires auth', () async {
      when(() => client.delete(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'))).thenAnswer((_) async => _res({'success': true}));

      await repo.deleteEmployee('store-1', 'emp-1');

      verify(() => client.delete(any(), data: any(named: 'data'), queryParameters: any(named: 'queryParameters'),
          requiresAuth: true)).called(1);
    });
  });
}
