// G3.2 / G3.3 repository: request paths, the employee / approver headers, the Idempotency-Key on writes, the error code kept for the UI,
// the minor-unit parsing with the RESPONSE's currency, and the sale / refund extras.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

class _MockClient extends Mock implements BaseClient {}

class _FakeSync extends PendingSaleSyncService {
  final List<Map<String, dynamic>> enqueued = [];
  @override
  Future<String?> provisionalNumberFor(String key) async => null;
  @override
  Future<void> enqueue(
    String id,
    Map<String, dynamic> payload, {
    String? employeeToken,
  }) async => enqueued.add(payload);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

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

typedef _Sent = ({
  String url,
  Map<String, dynamic> headers,
  dynamic data,
  Map<String, dynamic>? query,
  String verb,
});

void main() {
  late _MockClient client;
  late PosRepository repo;
  final sent = <_Sent>[];
  final lots = '${ApiConstants.apiPrefix}/pos/inventory/lots';
  final cust = '${ApiConstants.apiPrefix}/pos/customers';

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
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
          query: (i.namedArguments[#queryParameters] as Map?)
              ?.cast<String, dynamic>(),
          verb: 'GET',
        ));
        if (outcome is DioException) throw outcome;
        return outcome as Response;
      });

  void scriptWrite(String verb, List<Object> outcomes) {
    var n = 0;
    Future<Response> answer(Invocation i) async {
      sent.add((
        url: i.positionalArguments[0] as String,
        headers: (i.namedArguments[#headers] as Map).cast<String, dynamic>(),
        data: i.namedArguments[#data],
        query: null,
        verb: verb,
      ));
      final o = outcomes[n++];
      if (o is DioException) throw o;
      return o as Response;
    }

    if (verb == 'PATCH') {
      when(
        () => client.patch(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
          retryable: any(named: 'retryable'),
        ),
      ).thenAnswer(answer);
    } else {
      when(
        () => client.post(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          requiresAuth: any(named: 'requiresAuth'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(answer);
    }
  }

  Map<String, dynamic> customer({
    String id = 'c1',
    String name = 'Dev Customer',
    bool existing = false,
  }) => {
    'id': id,
    'kind': 'pos',
    'name': name,
    'phone': '03001112222',
    'email': null,
    'creditBalanceMinor': 2000,
    'loyaltyPoints': 40,
    'loyaltyTier': 'silver',
    if (existing) 'existing': true,
  };

  group('G3.2 lot preview', () {
    test('GET path, qty query, employee token; allocations parse', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {
            'variantId': 'v9',
            'trackLots': true,
            'qty': 6,
            'serverTime': '2026-11-09T10:00:00.000Z',
            'shortBy': 0,
            'expiredUnits': 4,
            'allocations': [
              {
                'lotId': 'l1',
                'lotNumber': 'LOT-SOON',
                'take': 5,
                'expiryDate': '2026-11-12T00:00:00.000Z',
                'daysLeft': 3,
              },
              {
                'lotId': 'l2',
                'lotNumber': 'LOT-LATER',
                'take': 1,
                'expiryDate': '2026-12-04T00:00:00.000Z',
                'daysLeft': 25,
              },
            ],
          },
        }),
      );
      final p = await repo.getLotPreview('st1', 'v9', 6);
      expect(sent.single.url, '$lots/st1/v9');
      expect(sent.single.query, {'qty': 6});
      expect(sent.single.headers['x-pos-employee-token'], 'tok-cashier');
      expect(p!.headline, 'Lot LOT-SOON · expires in 3 d');
      expect(p.spill, '+ 1 from LOT-LATER');
      expect(p.expiresWithin(7), isTrue);
      expect(p.needsExpiredOverride, isFalse);
      expect(p.asOf, isNotNull);
    });

    test('a 4xx returns null and keeps the code', () async {
      scriptGet(_fail(403, {'success': false, 'code': 'POS_PIN_REQUIRED'}));
      expect(await repo.getLotPreview('st1', 'v9', 1), isNull);
      expect(repo.lastErrorCode, 'POS_PIN_REQUIRED');
    });

    test(
      'stock rows parse expiredUnits and nextExpiryAt; the expiring filter is a plain query value',
      () async {
        scriptGet(
          _res({
            'success': true,
            'data': {
              'currency': 'USD',
              'currencyExponent': 2,
              'total': 1,
              'page': 1,
              'hasMore': false,
              'items': [
                {
                  'variantId': 'v9',
                  'productId': 'p9',
                  'productName': 'Yogurt',
                  'stock': 12,
                  'trackLots': true,
                  'expiredUnits': 4,
                  'nextExpiryAt': '2026-11-12T00:00:00.000Z',
                },
              ],
            },
          }),
        );
        final page = await repo.getInventoryStock('st1', filter: 'expiring');
        expect(sent.single.query!['filter'], 'expiring');
        expect(page!.items.single.expiredUnits, 4);
        expect(page.items.single.nextExpiryAt, isNotNull);
      },
    );
  });

  group('G3.3 reads', () {
    test('config: path and loyalty rules', () async {
      scriptGet(
        _res({
          'success': true,
          'data': {
            'currency': 'USD',
            'currencyExponent': 2,
            'storeCreditTenderEnabled': true,
            'loyalty': {
              'enabled': true,
              'earnSpendMinor': 1000,
              'redeemMinorPerPoint': 50,
            },
          },
        }),
      );
      final c = await repo.getCustomerConfig('st1');
      expect(sent.single.url, '$cust/config/st1');
      expect(c!.storeCreditTenderEnabled, isTrue);
      expect(c.loyalty.canRedeem, isTrue);
      expect(c.loyalty.redeemMinorPerPoint, 50);
      expect(c.cur, const InvCur('USD', 2));
    });

    test(
      'search: q is trimmed into the query, rows and the response currency parse',
      () async {
        scriptGet(
          _res({
            'success': true,
            'data': {
              'currency': 'USD',
              'currencyExponent': 2,
              'items': [customer()],
            },
          }),
        );
        final r = await repo.searchPosCustomers('st1', ' dev ');
        expect(sent.single.url, '$cust/search/st1');
        expect(sent.single.query, {'q': 'dev'});
        expect(r!.items.single.creditBalanceMinor, 2000);
        expect(r.items.single.loyaltyPoints, 40);
        expect(r.cur!.format(r.items.single.creditBalanceMinor!), '\$20.00');
      },
    );

    test(
      'a response WITHOUT currency / exponent yields no currency (so no money is shown, never the configured one)',
      () async {
        scriptGet(
          _res({
            'success': true,
            'data': {
              'items': [customer()],
            },
          }),
        );
        final r = await repo.searchPosCustomers('st1', '');
        expect(r!.cur, isNull);
        scriptGet(
          _res({
            'success': true,
            'data': {
              'currency': 'USD',
              'customer': customer(),
              'creditBalanceMinor': 5,
            },
          }),
        );
        expect((await repo.getCustomerProfile('st1', 'c1'))!.cur, isNull);
        scriptGet(
          _res({
            'success': true,
            'data': {'enabled': true, 'items': []},
          }),
        );
        expect((await repo.getCustomerCredit('st1', 'c1'))!.cur, isNull);
      },
    );

    test(
      'profile: path, balances, role-dependent lifetime spend (absent for a cashier)',
      () async {
        scriptGet(
          _res({
            'success': true,
            'data': {
              'currency': 'USD',
              'currencyExponent': 2,
              'customer': customer(),
              'creditBalanceMinor': 2000,
              'loyaltyPoints': 40,
              'loyaltyTier': 'silver',
              'loyalty': {
                'points': 40,
                'tier': 'silver',
                'enabled': true,
                'earnSpendMinor': 1000,
                'redeemMinorPerPoint': 50,
              },
              'orderCount': 3,
              'lastVisitAt': '2026-11-01T10:00:00.000Z',
              'recentSales': [
                {
                  'id': 's1',
                  'number': 'S-1',
                  'totalMinor': 1200,
                  'status': 'completed',
                  'at': '2026-11-01T10:00:00.000Z',
                },
              ],
            },
          }),
        );
        final p = await repo.getCustomerProfile('st1', 'c1');
        expect(sent.single.url, '$cust/profile/st1/c1');
        expect(p!.lifetimeSpendMinor, isNull);
        expect(p.recentSales.single.totalMinor, 1200);
        expect(p.orderCount, 3);
        expect(p.loyalty.canRedeem, isTrue);
      },
    );

    test(
      'credit ledger: path, page query, signed amounts; a cashier 403 keeps the code',
      () async {
        scriptGet(
          _res({
            'success': true,
            'data': {
              'enabled': true,
              'currency': 'USD',
              'currencyExponent': 2,
              'hasMore': true,
              'items': [
                {
                  'id': 'e1',
                  'at': '2026-11-01T10:00:00.000Z',
                  'type': 'manual_adjustment',
                  'amountMinor': -500,
                  'balanceAfterMinor': 1500,
                  'note': 'oops',
                },
              ],
            },
          }),
        );
        final l = await repo.getCustomerCredit('st1', 'c1', page: 2);
        expect(sent.single.url, '$cust/credit/st1/c1');
        expect(sent.single.query, {'page': 2});
        expect(l!.items.single.amountMinor, -500);
        expect(l.hasMore, isTrue);
        scriptGet(
          _fail(403, {'success': false, 'code': 'POS_ACTION_FORBIDDEN'}),
        );
        expect(await repo.getCustomerCredit('st1', 'c1'), isNull);
        expect(repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
      },
    );
  });

  group('G3.3 writes', () {
    test(
      'create: POST path, only filled fields, employee token + Idempotency-Key; existing flag parses',
      () async {
        scriptWrite('POST', [
          _res({'success': true, 'data': customer(existing: true)}),
        ]);
        final r = await repo.createPosCustomer('st1', {
          'name': ' Dev ',
          'phone': '0300',
          'email': null,
          'ntn': 'x',
          'marketingConsent': true,
        });
        expect(sent.single.url, '$cust/st1');
        expect(sent.single.verb, 'POST');
        expect(sent.single.data, {
          'name': 'Dev',
          'phone': '0300',
          'ntn': 'x',
          'marketingConsent': true,
        });
        expect(sent.single.headers['x-pos-employee-token'], 'tok-cashier');
        expect(sent.single.headers['Idempotency-Key'], isNotEmpty);
        expect(r.success, isTrue);
        expect(r.customer!.existing, isTrue);
      },
    );

    test(
      'create: a validation code is captured; the key is released so a corrected retry is a new intent',
      () async {
        scriptWrite('POST', [
          _fail(400, {
            'success': false,
            'code': 'PHONE_INVALID',
            'message': 'bad',
          }),
          _res({'success': true, 'data': customer()}),
        ]);
        final a = await repo.createPosCustomer('st1', {
          'name': 'Dev',
          'phone': 'x',
        });
        expect(a.success, isFalse);
        expect(a.code, 'PHONE_INVALID');
        expect(repo.lastErrorCode, 'PHONE_INVALID');
        await repo.createPosCustomer('st1', {'name': 'Dev', 'phone': 'x'});
        expect(
          sent[1].headers['Idempotency-Key'],
          isNot(sent[0].headers['Idempotency-Key']),
        );
      },
    );

    test(
      'create: an ambiguous failure keeps the SAME key on the retry',
      () async {
        scriptWrite('POST', [
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.receiveTimeout,
          ),
          _res({'success': true, 'data': customer()}),
        ]);
        await repo.createPosCustomer('st1', {'name': 'Dev'});
        await repo.createPosCustomer('st1', {'name': 'Dev'});
        expect(
          sent[1].headers['Idempotency-Key'],
          sent[0].headers['Idempotency-Key'],
        );
      },
    );

    test(
      'update: PATCH path with the id; a cashier is refused with POS_ACTION_FORBIDDEN, a taken phone with PHONE_IN_USE',
      () async {
        scriptWrite('PATCH', [
          _fail(403, {'success': false, 'code': 'POS_ACTION_FORBIDDEN'}),
          _fail(409, {'success': false, 'code': 'PHONE_IN_USE'}),
          _res({'success': true, 'data': customer(name: 'New')}),
        ]);
        expect(
          (await repo.updatePosCustomer('st1', 'c1', {'name': 'New'})).code,
          'POS_ACTION_FORBIDDEN',
        );
        expect(
          (await repo.updatePosCustomer('st1', 'c1', {'phone': '1'})).code,
          'PHONE_IN_USE',
        );
        final ok = await repo.updatePosCustomer('st1', 'c1', {'name': 'New'});
        expect(sent.last.url, '$cust/st1/c1');
        expect(sent.last.verb, 'PATCH');
        expect(sent.last.headers['Idempotency-Key'], isNotEmpty);
        expect(ok.customer!.name, 'New');
      },
    );

    test(
      'credit adjust: POST path and body (signed minor, trimmed note, expiry as UTC), Idempotency-Key; POS_OWNER_REQUIRED kept',
      () async {
        scriptWrite('POST', [
          _res({'success': true, 'data': {}}),
          _fail(403, {'success': false, 'code': 'POS_OWNER_REQUIRED'}),
        ]);
        final ok = await repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: -500,
          note: ' goodwill ',
          expiresAt: DateTime.utc(2027, 1, 1),
        );
        expect(sent.first.url, '$cust/credit/st1/c1/adjust');
        expect(sent.first.data, {
          'amountMinor': -500,
          'note': 'goodwill',
          'expiresAt': '2027-01-01T00:00:00.000Z',
        });
        expect(sent.first.headers['Idempotency-Key'], isNotEmpty);
        expect(ok.success, isTrue);
        final big = await repo.adjustCustomerCredit(
          'st1',
          'c1',
          amountMinor: 999999,
          note: 'x',
        );
        expect(big.code, 'POS_OWNER_REQUIRED');
      },
    );
  });

  group('sale and refund extras', () {
    Future<({bool success, dynamic sale, String? message, bool queued})> sell({
      String? expiredToken,
      int? redeem,
      List<Map<String, dynamic>>? payments,
      Map<String, dynamic> item = const {},
    }) => repo.createSale(
      storeId: 'st',
      sessionId: 'se',
      registerId: 'r',
      employeeId: 'e',
      items: [
        {
          'productId': 'p',
          'variantId': 'v',
          'qty': 2,
          'unitPrice': 4.0,
          ...item,
        },
      ],
      paymentMethod: 'cash',
      status: 'completed',
      customerId: 'c1',
      payments: payments,
      expiredApproverToken: expiredToken,
      redeemPoints: redeem,
    );
    Map<String, dynamic> saleJson() => {
      '_id': 's1',
      'saleNumber': 'S-1',
      'storeId': 'st',
      'sessionId': 'se',
      'registerId': 'r',
      'employeeId': 'e',
      'discount': 0,
      'tax': 0,
      'subtotal': 8.0,
      'total': 8.0,
      'paymentMethod': 'cash',
      'customerName': 'Dev',
      'notes': '',
      'status': 'completed',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'currency': 'USD',
      'currencyExponent': 2,
      'items': [
        {
          '_id': 'i1',
          'productId': 'p',
          'name': 'Yogurt',
          'qty': 6,
          'price': 4.0,
          'lineTotal': 24.0,
          'soldExpired': true,
          'lots': [
            {
              'lotId': 'l1',
              'lotNumber': 'LOT-OLD',
              'qty': 4,
              'expiryDate': '2026-10-01T00:00:00.000Z',
              'expired': true,
              'costPriceMinor': 100,
            },
          ],
        },
      ],
      'loyalty': {
        'earnedPoints': 1,
        'redeemedPoints': 10,
        'redeemValueMinor': 500,
      },
    };

    test(
      'sellExpired goes on the item and the manager token travels as x-pos-approver-token (the cashier token stays the employee token)',
      () async {
        scriptWrite('POST', [
          _res({'success': true, 'data': saleJson()}),
        ]);
        final r = await sell(
          expiredToken: 'tok-mgr',
          item: {'sellExpired': true},
        );
        expect(sent.single.headers['x-pos-approver-token'], 'tok-mgr');
        expect(sent.single.headers['x-pos-employee-token'], 'tok-cashier');
        expect(
          ((sent.single.data as Map)['items'] as List).single['sellExpired'],
          isTrue,
        );
        final item = (r.sale as dynamic).items.single;
        expect(item.soldExpired, isTrue);
        expect(item.lots.single.label, 'Lot LOT-OLD ×4');
        expect(item.lots.single.expired, isTrue);
        expect((r.sale as dynamic).loyalty.redeemedPoints, 10);
      },
    );

    test(
      'no approver header unless a token is given; redeemPoints only when > 0',
      () async {
        scriptWrite('POST', [
          _res({'success': true, 'data': saleJson()}),
          _res({'success': true, 'data': saleJson()}),
        ]);
        await sell();
        expect(sent[0].headers.containsKey('x-pos-approver-token'), isFalse);
        expect((sent[0].data as Map).containsKey('redeemPoints'), isFalse);
        await sell(redeem: 10);
        expect((sent[1].data as Map)['redeemPoints'], 10);
      },
    );

    test(
      'a store-credit tender line is sent as is (major units + minor twin)',
      () async {
        scriptWrite('POST', [
          _res({'success': true, 'data': saleJson()}),
        ]);
        await sell(
          payments: [
            {'method': 'store_credit', 'amount': 5.0},
            {'method': 'cash', 'amount': 3.0},
          ],
        );
        final pay = (sent.single.data as Map)['payments'] as List;
        expect(pay.first['method'], 'store_credit');
        expect(pay.first['amountMinor'], 500);
      },
    );

    test(
      'an offline (ambiguous) failure queues a plain sale WITHOUT sellExpired',
      () async {
        final sync = _FakeSync();
        Get.put<PendingSaleSyncService>(sync);
        scriptWrite('POST', [
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError,
          ),
        ]);
        final r = await sell(item: {'sellExpired': true});
        expect(r.queued, isTrue);
        expect(
          ((sync.enqueued.single['items']) as List).single.containsKey(
            'sellExpired',
          ),
          isFalse,
        );
      },
    );

    test(
      'store credit and points are NEVER queued: an ambiguous failure is just a failure',
      () async {
        final sync = _FakeSync();
        Get.put<PendingSaleSyncService>(sync);
        scriptWrite('POST', [
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError,
          ),
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError,
          ),
        ]);
        expect(
          (await sell(
            payments: [
              {'method': 'store_credit', 'amount': 8.0},
            ],
          )).queued,
          isFalse,
        );
        expect((await sell(redeem: 5)).queued, isFalse);
        expect(sync.enqueued, isEmpty);
      },
    );

    test('server codes of the sale are kept in lastErrorCode', () async {
      scriptWrite('POST', [
        _fail(409, {
          'success': false,
          'code': 'STORE_CREDIT_INSUFFICIENT',
          'message': 'no',
        }),
      ]);
      final r = await sell(
        payments: [
          {'method': 'store_credit', 'amount': 8.0},
        ],
      );
      expect(r.success, isFalse);
      expect(repo.lastErrorCode, 'STORE_CREDIT_INSUFFICIENT');
    });

    test(
      'refundSale: refundTo is sent only when given; a store_credit tender parses; the approval reason is kept',
      () async {
        scriptWrite('POST', [
          _res({
            'success': true,
            'data': {
              'refundedAmount': 8.0,
              'newStatus': 'refunded',
              'tenders': [
                {'method': 'store_credit', 'amount': 8.0},
              ],
            },
          }),
          _res({
            'success': true,
            'data': {
              'refundedAmount': 8.0,
              'newStatus': 'refunded',
              'tenders': [],
            },
          }),
          _fail(403, {
            'success': false,
            'code': 'RETURN_NEEDS_MANAGER',
            'reasons': ['store_credit_refund_above_limit'],
          }),
        ]);
        final a = await repo.refundSale('s1', refundTo: 'store_credit');
        expect((sent[0].data as Map)['refundTo'], 'store_credit');
        expect(a.tenders.single.method, 'store_credit');
        await repo.refundSale('s2');
        expect((sent[1].data as Map).containsKey('refundTo'), isFalse);
        final c = await repo.refundSale('s3', refundTo: 'store_credit');
        expect(c.success, isFalse);
        expect(repo.lastErrorCode, 'RETURN_NEEDS_MANAGER');
        expect(repo.lastErrorReasons, ['store_credit_refund_above_limit']);
      },
    );

    test('new sale flags have plain wording', () {
      expect(
        const PosSaleFlag(type: 'expired_lot_sold_offline').description,
        startsWith('Sold from an expired lot while offline'),
      );
      expect(
        const PosSaleFlag(type: 'lots_short').description,
        startsWith('Not enough lot stock recorded'),
      );
    });
  });
}
