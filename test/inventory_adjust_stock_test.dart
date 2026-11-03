// Gap #23: stock edits go through the reason-coded DELTA route, are retry-safe (same Idempotency-Key until a final answer),
// and the backend's refusal text (400/409) reaches the user instead of a generic failure.

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

class MockBaseClient extends Mock implements BaseClient {}

Response _res(dynamic data, {int? statusCode}) => Response(data: data, statusCode: statusCode ?? 200, requestOptions: RequestOptions(path: ''));
DioException _fail(DioExceptionType type, {int? status, dynamic body}) => DioException(
      requestOptions: RequestOptions(path: ''),
      type: type,
      response: status != null ? _res(body ?? {'message': 'x'}, statusCode: status) : null,
    );

void main() {
  late MockBaseClient client;
  late InventoryRepository repo;
  final urls = <String>[];
  final headers = <Map<String, dynamic>>[];
  final bodies = <dynamic>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    urls.clear(); headers.clear(); bodies.clear();
    client = MockBaseClient();
    repo = InventoryRepository(client: client, intents: IdempotencyIntentStore());
  });

  void script(List<Object> outcomes) {
    var i = 0;
    when(() => client.patch(any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        requiresAuth: any(named: 'requiresAuth'),
        headers: any(named: 'headers'),
        retryable: any(named: 'retryable'))).thenAnswer((inv) async {
      urls.add(inv.positionalArguments.first as String);
      headers.add((inv.namedArguments[#headers] as Map).cast<String, dynamic>());
      bodies.add(inv.namedArguments[#data]);
      final o = outcomes[i++];
      if (o is DioException) throw o;
      return o as Response;
    });
  }

  Future<({bool success, String? message})> adjust({int delta = -2}) =>
      repo.adjustVariantStock(storeId: 's1', variantId: 'v1', delta: delta, reason: 'damaged', note: 'dropped');

  test('sends a delta + reason (never an absolute stock) to the adjust route', () async {
    script([_res({'success': true, 'message': 'Stock updated'})]);
    final r = await adjust();
    expect(r.success, isTrue);
    expect(urls.single, endsWith('/inventory/s1/variant/v1/adjust'));
    expect(bodies.single, {'delta': -2, 'reason': 'damaged', 'note': 'dropped'});
    expect((bodies.single as Map).containsKey('stock'), isFalse);
  });

  test('a lost response is retried under the SAME Idempotency-Key, so a timed-out success cannot apply twice', () async {
    script([_fail(DioExceptionType.receiveTimeout), _res({'success': true})]);
    expect((await adjust()).success, isFalse);
    expect((await adjust()).success, isTrue);
    expect(headers[0]['Idempotency-Key'], isNotEmpty);
    expect(headers[1]['Idempotency-Key'], headers[0]['Idempotency-Key']);
  });

  test('after a final answer the next identical adjustment is a NEW intent (new key)', () async {
    script([_res({'success': true}), _res({'success': true})]);
    await adjust(); await adjust();
    expect(headers[1]['Idempotency-Key'], isNot(headers[0]['Idempotency-Key']));
  });

  test('a backend refusal (409/400) shows the server\'s message and releases the key', () async {
    script([
      _fail(DioExceptionType.badResponse, status: 409, body: {'message': 'Cannot remove 5 units: only 3 available'}),
      _fail(DioExceptionType.badResponse, status: 400, body: {'message': 'reason is required'}),
    ]);
    final a = await adjust(delta: -5);
    expect(a.success, isFalse);
    expect(a.message, 'Cannot remove 5 units: only 3 available');
    final b = await adjust(delta: -5);
    expect(b.message, 'reason is required');
    expect(headers[1]['Idempotency-Key'], isNot(headers[0]['Idempotency-Key'])); // a definite refusal ends the intent
  });
}
