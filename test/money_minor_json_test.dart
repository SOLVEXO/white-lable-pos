// G1b step e (app): the `<name>Minor` reader, the response models that use it, the minor twins added to the sale payload, and the
// guarantee that a sale queued by an OLDER build (decimals only) still replays verbatim while a new one keeps its minor keys.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/sale_payload_minor.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/money_json.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockPosRepository extends Mock implements PosRepository {}

const RawResult _ok = (
  success: true,
  connectivityError: false,
  retryable: false,
  message: null,
  code: null,
);
typedef RawResult = ({
  bool success,
  bool connectivityError,
  bool retryable,
  String? message,
  String? code,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  setUp(() => Money.configure(currency: 'USD', exponent: 2));

  group('MoneyJson reader', () {
    test(
      'prefers the minor twin, falls back to the decimal, then to 0 / null',
      () {
        expect(
          MoneyJson.read({'total': 12.34, 'totalMinor': 1234}, 'total', exp: 2),
          12.34,
        );
        expect(
          MoneyJson.read({'total': 99.99, 'totalMinor': 1234}, 'total', exp: 2),
          12.34,
          reason: 'minor wins when present',
        );
        expect(MoneyJson.read({'total': 12.34}, 'total', exp: 2), 12.34);
        expect(MoneyJson.read({}, 'total', exp: 2), 0);
        expect(MoneyJson.read(null, 'total'), 0);
        expect(MoneyJson.readNullable({}, 'closingCash'), isNull);
        expect(
          MoneyJson.readNullable({
            'closingCash': null,
            'closingCashMinor': null,
          }, 'closingCash'),
          isNull,
        );
        expect(
          MoneyJson.readNullable(
            {'closingCashMinor': 0},
            'closingCash',
            exp: 2,
          ),
          0.0,
        );
      },
    );

    test(
      'handles int / integral num / non-integral and non-numeric minor values safely',
      () {
        expect(MoneyJson.read({'a': 0, 'aMinor': 500}, 'a', exp: 2), 5.0);
        expect(
          MoneyJson.read({'aMinor': 500.0}, 'a', exp: 2),
          5.0,
          reason: 'a JSON 500.0 is still an integral number',
        );
        expect(
          MoneyJson.read({'a': 7.5, 'aMinor': 12.5}, 'a', exp: 2),
          7.5,
          reason: 'a non-integral minor is ignored, the decimal is used',
        );
        expect(MoneyJson.read({'a': 7.5, 'aMinor': '750'}, 'a', exp: 2), 7.5);
        expect(
          MoneyJson.read({'a': 7.5, 'aMinor': double.nan}, 'a', exp: 2),
          7.5,
        );
        expect(
          MoneyJson.read({'aMinor': -250}, 'a', exp: 2),
          -2.5,
          reason: 'signed (variance) values',
        );
      },
    );

    test('exponent 0, 2 and 3', () {
      expect(MoneyJson.read({'aMinor': 1500}, 'a', exp: 0), 1500.0);
      expect(MoneyJson.read({'aMinor': 1500}, 'a', exp: 2), 15.0);
      expect(MoneyJson.read({'aMinor': 1500}, 'a', exp: 3), 1.5);
      expect(MoneyJson.read({'aMinor': 1999}, 'a', exp: 2), 19.99);
      expect(
        MoneyJson.read({'aMinor': 330}, 'a', exp: 2),
        3.3,
        reason: 'exact — no 3.3000000000000007 drift',
      );
      Money.configure(exponent: 3);
      expect(
        MoneyJson.read({'aMinor': 1234}, 'a'),
        1.234,
        reason: 'no explicit exp → the store exponent',
      );
    });

    test('the largest safe value converts without losing a unit', () {
      expect(
        MoneyJson.minorOf({'aMinor': 9007199254740991}, 'a'),
        9007199254740991,
      );
    });
  });

  group('models: with and without the minor twins give the same doubles', () {
    final legacySale = <String, dynamic>{
      '_id': 's1',
      'saleNumber': 'POS-1',
      'currency': 'USD',
      'currencyExponent': 2,
      'status': 'partially_refunded',
      'items': [
        {
          '_id': 'i1',
          'productId': 'p',
          'name': 'Tea',
          'qty': 3,
          'price': 1.1,
          'lineTotal': 3.3,
        },
      ],
      'subtotal': 3.3,
      'discount': 0.3,
      'tax': 0.3,
      'total': 3.3,
      'changeGiven': 6.7,
      'refundedAmount': 1.1,
      'discountType': 'amount',
      'discountValue': 0.3,
      'payments': [
        {'method': 'cash', 'amount': 3.3, 'tendered': 10},
      ],
      'refunds': [
        {
          'amount': 1.1,
          'kind': 'partial',
          'tenders': [
            {'method': 'cash', 'amount': 1.1},
          ],
        },
      ],
    };
    final newSale = <String, dynamic>{
      ...legacySale,
      'subtotalMinor': 330,
      'discountMinor': 30,
      'taxMinor': 30,
      'totalMinor': 330,
      'changeGivenMinor': 670,
      'refundedAmountMinor': 110,
      'discountValueMinor': 30,
      'items': [
        {
          '_id': 'i1',
          'productId': 'p',
          'name': 'Tea',
          'qty': 3,
          'price': 1.1,
          'priceMinor': 110,
          'lineTotal': 3.3,
          'lineTotalMinor': 330,
        },
      ],
      'payments': [
        {
          'method': 'cash',
          'amount': 3.3,
          'amountMinor': 330,
          'tendered': 10,
          'tenderedMinor': 1000,
        },
      ],
      'refunds': [
        {
          'amount': 1.1,
          'amountMinor': 110,
          'kind': 'partial',
          'tenders': [
            {'method': 'cash', 'amount': 1.1, 'amountMinor': 110},
          ],
        },
      ],
    };

    test(
      'sale: identical values; the legacy JSON parses exactly as before',
      () {
        for (final j in [legacySale, newSale]) {
          final s = PosSaleModel.fromJson(j);
          expect(
            [
              s.subtotal,
              s.discount,
              s.tax,
              s.total,
              s.changeGiven,
              s.refundedAmount,
              s.discountValue,
            ],
            [3.3, 0.3, 0.3, 3.3, 6.7, 1.1, 0.3],
          );
          expect([s.items.single.price, s.items.single.lineTotal], [1.1, 3.3]);
          expect(
            [s.payments.single.amount, s.payments.single.tendered],
            [3.3, 10.0],
          );
          expect(
            [s.refunds.single.amount, s.refunds.single.tenders.single.amount],
            [1.1, 1.1],
          );
        }
      },
    );

    test(
      'minor wins over a drifting decimal (the 3.3000000000000007 case)',
      () {
        final drifting = {
          ...newSale,
          'total': 3.3000000000000007,
          'refundedAmount': 1.1000000000000001,
        };
        final s = PosSaleModel.fromJson(drifting);
        expect(s.total, 3.3);
        expect(s.refundedAmount, 1.1);
      },
    );

    test(
      'a percentage discountValue is NOT money (no minor twin, read as the number it is)',
      () {
        final s = PosSaleModel.fromJson({
          ...legacySale,
          'discountType': 'percent',
          'discountValue': 10,
        });
        expect(s.discountValue, 10.0);
      },
    );

    test(
      'a zero-decimal currency (JPY) and a three-decimal one (KWD) use their own exponent',
      () {
        final jpy = PosSaleModel.fromJson({
          'currency': 'JPY',
          'currencyExponent': 0,
          'total': 1500,
          'totalMinor': 1500,
          'subtotalMinor': 1500,
        });
        expect([jpy.total, jpy.subtotal], [1500.0, 1500.0]);
        final kwd = PosSaleModel.fromJson({
          'currency': 'KWD',
          'currencyExponent': 3,
          'total': 1.234,
          'totalMinor': 1234,
        });
        expect(kwd.total, 1.234);
      },
    );

    test('session: counters, signed variance and cash adjustments', () {
      final legacy = {
        '_id': 'sess',
        'openedAt': '2026-11-04T08:00:00.000Z',
        'currencyExponent': 2,
        'openingCash': 100,
        'closingCash': 108,
        'expectedCash': 107.7,
        'cashDifference': 0.3,
        'cashSales': 7.7,
        'cardSales': 3.3,
        'otherSales': 0,
        'totalSales': 11,
        'totalRefunds': 5.5,
        'cashAdjustments': [
          {'type': 'cash_in', 'amount': 20, 'reason': 'float'},
        ],
      };
      final minor = {
        ...legacy,
        'openingCashMinor': 10000,
        'closingCashMinor': 10800,
        'expectedCashMinor': 10770,
        'cashDifferenceMinor': 30,
        'cashSalesMinor': 770,
        'cardSalesMinor': 330,
        'otherSalesMinor': 0,
        'totalSalesMinor': 1100,
        'totalRefundsMinor': 550,
        'cashAdjustments': [
          {
            'type': 'cash_in',
            'amount': 20,
            'amountMinor': 2000,
            'reason': 'float',
          },
        ],
      };
      for (final j in [legacy, minor]) {
        final s = PosSessionModel.fromJson(j);
        expect(
          [
            s.openingCash,
            s.closingCash,
            s.expectedCash,
            s.cashDifference,
            s.cashSales,
            s.cardSales,
            s.otherSales,
            s.totalSales,
            s.totalRefunds,
          ],
          [100.0, 108.0, 107.7, 0.3, 7.7, 3.3, 0.0, 11.0, 5.5],
        );
        expect(s.cashAdjustments.single.amount, 20.0);
      }
      final drift = PosSessionModel.fromJson({
        ...minor,
        'cardSales': 3.3000000000000007,
      });
      expect(drift.cardSales, 3.3);
      expect(
        PosSessionModel.fromJson({
          '_id': 'x',
          'openedAt': '2026-11-04T08:00:00.000Z',
        }).closingCash,
        isNull,
        reason: 'still null when absent',
      );
    });

    test('reports: daily / range / session summaries and the cash flow', () {
      final dailyLegacy = {
        'date': 'd',
        'summary': {
          'totalTransactions': 3,
          'totalRevenue': 100.5,
          'netRevenue': 90.25,
          'avgTransactionValue': 30.08,
          'totalDiscount': 5,
          'totalTax': 10,
          'refundsTotal': 10.25,
        },
      };
      final dailyMinor = {
        'date': 'd',
        'summary': {
          ...(dailyLegacy['summary'] as Map<String, dynamic>),
          'totalRevenueMinor': 10050,
          'netRevenueMinor': 9025,
          'avgTransactionValueMinor': 3008,
          'totalDiscountMinor': 500,
          'totalTaxMinor': 1000,
          'refundsTotalMinor': 1025,
        },
      };
      for (final j in [dailyLegacy, dailyMinor]) {
        final d = PosDailyReportModel.fromJson(j);
        expect(
          [
            d.totalRevenue,
            d.netRevenue,
            d.avgTransactionValue,
            d.totalDiscount,
            d.totalTax,
            d.refundsTotal,
          ],
          [100.5, 90.25, 30.08, 5.0, 10.0, 10.25],
        );
      }
      final rangeLegacy = {
        'from': 'a',
        'to': 'b',
        'summary': {
          'totalRevenue': 500,
          'netRevenue': 480.5,
          'avgTransactionValue': 20.02,
          'refundsTotal': 19.5,
        },
      };
      final rangeMinor = {
        'from': 'a',
        'to': 'b',
        'summary': {
          'totalRevenue': 500,
          'netRevenue': 480.5,
          'avgTransactionValue': 20.02,
          'refundsTotal': 19.5,
          'netRevenueMinor': 48050,
          'avgTransactionValueMinor': 2002,
          'refundsTotalMinor': 1950,
          'totalRevenueMinor': 50000,
        },
      };
      for (final j in [rangeLegacy, rangeMinor]) {
        final r = PosRangeReportModel.fromJson(j);
        expect(
          [r.totalRevenue, r.netRevenue, r.avgTransactionValue, r.refundsTotal],
          [500.0, 480.5, 20.02, 19.5],
        );
      }
      final sessLegacy = {
        'session': {'_id': 's', 'openedAt': '2026-11-04T08:00:00.000Z'},
        'summary': {
          'totalSales': 65.5,
          'refundsTotal': 5.5,
          'cashFlow': {
            'openingCash': 100,
            'cashSales': 40.5,
            'cashIn': 20,
            'cashOut': 5,
            'expectedCash': 155.5,
            'closingCash': 155,
            'cashDifference': -0.5,
          },
        },
      };
      final sessMinor = {
        'session': {'_id': 's', 'openedAt': '2026-11-04T08:00:00.000Z'},
        'summary': {
          'totalSales': 65.5,
          'totalSalesMinor': 6550,
          'refundsTotal': 5.5,
          'refundsTotalMinor': 550,
          'cashFlow': {
            'openingCash': 100,
            'openingCashMinor': 10000,
            'cashSales': 40.5,
            'cashSalesMinor': 4050,
            'cashIn': 20,
            'cashInMinor': 2000,
            'cashOut': 5,
            'cashOutMinor': 500,
            'expectedCash': 155.5,
            'expectedCashMinor': 15550,
            'closingCash': 155,
            'closingCashMinor': 15500,
            'cashDifference': -0.5,
            'cashDifferenceMinor': -50,
          },
        },
      };
      for (final j in [sessLegacy, sessMinor]) {
        final r = PosSessionReportModel.fromJson(j);
        expect([r.totalSales, r.refundsTotal], [65.5, 5.5]);
        final f = r.cashFlow;
        expect(
          [
            f.openingCash,
            f.cashSales,
            f.cashIn,
            f.cashOut,
            f.expectedCash,
            f.closingCash,
            f.cashDifference,
          ],
          [100.0, 40.5, 20.0, 5.0, 155.5, 155.0, -0.5],
        );
      }
    });

    test('quote: minor twins read, decimals still work', () {
      final legacy = {
        'subtotal': 20,
        'discount': 2,
        'tax': 0.9,
        'total': 18.9,
        'taxRate': 0.05,
        'currency': 'USD',
        'currencyExponent': 2,
        'settingsVersion': 4,
        'lines': [
          {'variantId': 'v', 'price': 20},
        ],
      };
      final minor = {
        ...legacy,
        'subtotalMinor': 2000,
        'discountMinor': 200,
        'taxMinor': 90,
        'totalMinor': 1890,
        'lines': [
          {'variantId': 'v', 'price': 20, 'priceMinor': 2000},
        ],
      };
      for (final j in [legacy, minor]) {
        final q = PosQuote.fromJson(j);
        expect(
          [q.subtotal, q.discount, q.tax, q.total],
          [20.0, 2.0, 0.9, 18.9],
        );
        expect(q.unitPrices['v'], 20.0);
      }
    });
  });

  group('withMinorTwins — the sale payload', () {
    Map<String, dynamic> base() => {
      'storeId': 's',
      'sessionId': 'x',
      'items': [
        {'productId': 'p', 'variantId': 'v', 'qty': 2, 'unitPrice': 9.99},
        {'productId': 'q', 'qty': 1, 'unitPrice': 0.05},
      ],
      'discountType': 'amount',
      'discountValue': 2.5,
      'clientTotal': 18.9,
      'paymentMethod': 'card',
      'payments': [
        {'method': 'card', 'amount': 15, 'reference': 'A1'},
        {'method': 'cash', 'amount': 3.9},
      ],
      'amountTendered': 5,
      'status': 'completed',
    };

    test(
      'split + discounted sale (exp 2): minor keys appear NEXT TO the decimals, which are unchanged',
      () {
        final p = base();
        final out = withMinorTwins(p, exp: 2);
        expect(out['clientTotal'], 18.9);
        expect(out['clientTotalMinor'], 1890);
        expect(out['amountTendered'], 5);
        expect(out['amountTenderedMinor'], 500);
        expect(out['discountValue'], 2.5);
        expect(out['discountValueMinor'], 250);
        final items = out['items'] as List;
        expect((items[0] as Map)['unitPrice'], 9.99);
        expect((items[0] as Map)['unitPriceMinor'], 999);
        expect((items[1] as Map)['unitPriceMinor'], 5);
        final pays = out['payments'] as List;
        expect(pays.map((e) => (e as Map)['amount']), [15, 3.9]);
        expect(pays.map((e) => (e as Map)['amountMinor']), [1500, 390]);
        expect((pays[0] as Map)['reference'], 'A1');
        // every other key is untouched, and the input map was not mutated
        for (final k in ['storeId', 'sessionId', 'paymentMethod', 'status']) {
          expect(out[k], p[k]);
        }
        expect(p.containsKey('clientTotalMinor'), isFalse);
        expect(
          (p['items'] as List).first.containsKey('unitPriceMinor'),
          isFalse,
        );
      },
    );

    test(
      'a percentage discount gets NO discountValueMinor (it is not money)',
      () {
        final out = withMinorTwins({
          ...base(),
          'discountType': 'percent',
          'discountValue': 10,
        }, exp: 2);
        expect(out['discountValue'], 10);
        expect(out.containsKey('discountValueMinor'), isFalse);
        expect(
          withMinorTwins({
            'items': const [],
            'clientTotal': 1.0,
          }, exp: 2).containsKey('discountValueMinor'),
          isFalse,
        );
      },
    );

    test('absent decimals produce no twins (nothing invented)', () {
      final out = withMinorTwins({
        'storeId': 's',
        'items': [
          {'productId': 'p', 'qty': 1},
        ],
        'paymentMethod': 'cash',
      }, exp: 2);
      expect(out.keys.where((k) => k.endsWith('Minor')), isEmpty);
      expect(
        ((out['items'] as List).first as Map).containsKey('unitPriceMinor'),
        isFalse,
      );
    });

    test('exponent 0 (JPY) and 3 (KWD)', () {
      final jpy = withMinorTwins({
        'clientTotal': 1500.0,
        'amountTendered': 2000,
        'items': [
          {'unitPrice': 750},
        ],
        'payments': [
          {'method': 'cash', 'amount': 1500},
        ],
      }, exp: 0);
      expect(
        [
          jpy['clientTotalMinor'],
          jpy['amountTenderedMinor'],
          (jpy['items'] as List).first['unitPriceMinor'],
          (jpy['payments'] as List).first['amountMinor'],
        ],
        [1500, 2000, 750, 1500],
      );
      final kwd = withMinorTwins({
        'clientTotal': 1.234,
        'items': [
          {'unitPrice': 0.617},
        ],
        'payments': [
          {'method': 'card', 'amount': 1.234},
        ],
      }, exp: 3);
      expect(
        [
          kwd['clientTotalMinor'],
          (kwd['items'] as List).first['unitPriceMinor'],
          (kwd['payments'] as List).first['amountMinor'],
        ],
        [1234, 617, 1234],
      );
    });

    test(
      'defaults to the store exponent and rounds half away from zero like the server',
      () {
        Money.configure(currency: 'KWD');
        expect(
          withMinorTwins({'clientTotal': 1.2345})['clientTotalMinor'],
          1235,
        );
        Money.configure(currency: 'USD');
        expect(
          withMinorTwins({'clientTotal': 0.1 + 0.2})['clientTotalMinor'],
          30,
          reason: 'float noise never leaks into the integer',
        );
      },
    );
  });

  group('offline queue: old and new payloads replay', () {
    late Directory tmp;
    late MockPosRepository repo;
    late PendingSaleLocalStore store;
    late PendingSaleSyncService svc;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('pos_minor_queue_');
      repo = MockPosRepository();
      store = PendingSaleLocalStore(
        dbPath: '${tmp.path}/q.db',
        cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 9))),
      );
      svc = PendingSaleSyncService(
        posRepository: repo,
        localStore: store,
        currentStoreId: () async => 's1',
        clock: () => DateTime(2026, 11, 4, 12),
        persistLastSync: false,
      );
    });
    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    Future<Map<String, dynamic>> replay(Map<String, dynamic> payload) async {
      await store.enqueue(payload['idempotencyKey'] as String, payload);
      Map<String, dynamic>? sent;
      when(
        () => repo.submitRawSale(
          any(),
          employeeToken: any(named: 'employeeToken'),
        ),
      ).thenAnswer((i) async {
        sent = i.positionalArguments.first as Map<String, dynamic>;
        return _ok;
      });
      await svc.syncNow();
      expect(
        await store.getAll(),
        isEmpty,
        reason: 'synced rows leave the queue',
      );
      expect(svc.unresolvedCount.value, 0);
      return sent!;
    }

    test(
      'a sale queued by an OLDER build (decimals only) is sent exactly as stored — no minor keys injected',
      () async {
        final legacy = <String, dynamic>{
          'idempotencyKey': 'old-1',
          'storeId': 's1',
          'sessionId': 'A',
          'registerId': 'r',
          'employeeId': 'e',
          'items': [
            {'productId': 'p', 'variantId': 'v', 'qty': 2, 'unitPrice': 9.99},
          ],
          'clientTotal': 19.98,
          'paymentMethod': 'cash',
          'amountTendered': 20,
          'status': 'completed',
          'clientCreatedAt': '2026-11-02T10:00:00.000Z',
          'settingsVersion': 3,
          'offline': true,
        };
        final sent = await replay(legacy);
        expect(sent, legacy, reason: 'byte-for-byte the stored payload');
        expect(sent.keys.where((k) => k.endsWith('Minor')), isEmpty);
        expect(
          ((sent['items'] as List).first as Map).keys.where(
            (k) => k.toString().endsWith('Minor'),
          ),
          isEmpty,
        );
      },
    );

    test('a NEW-shaped payload replays with its minor keys intact', () async {
      final fresh = withMinorTwins(<String, dynamic>{
        'idempotencyKey': 'new-1',
        'storeId': 's1',
        'sessionId': 'A',
        'registerId': 'r',
        'employeeId': 'e',
        'items': [
          {'productId': 'p', 'variantId': 'v', 'qty': 2, 'unitPrice': 9.99},
        ],
        'discountType': 'amount',
        'discountValue': 1.0,
        'clientTotal': 18.98,
        'paymentMethod': 'card',
        'payments': [
          {'method': 'card', 'amount': 10},
          {'method': 'cash', 'amount': 8.98},
        ],
        'status': 'completed',
        'clientCreatedAt': '2026-11-04T10:00:00.000Z',
        'settingsVersion': 3,
        'offline': true,
      }, exp: 2);
      final sent = await replay(fresh);
      expect(sent, fresh);
      expect(sent['clientTotalMinor'], 1898);
      expect(sent['discountValueMinor'], 100);
      expect(((sent['items'] as List).first as Map)['unitPriceMinor'], 999);
      expect(
        ((sent['payments'] as List).map((p) => (p as Map)['amountMinor'])),
        [1000, 898],
      );
    });

    test(
      'a definite rejection of a minor/decimal disagreement (400 MONEY_FIELD_MISMATCH) is KEPT as failed for a manager, never dropped',
      () async {
        final p = withMinorTwins({
          'idempotencyKey': 'bad-1',
          'storeId': 's1',
          'sessionId': 'A',
          'items': [
            {'productId': 'p', 'qty': 1, 'unitPrice': 5.0},
          ],
          'clientTotal': 5.0,
          'paymentMethod': 'cash',
          'status': 'completed',
          'offline': true,
        }, exp: 2);
        await store.enqueue('bad-1', p);
        when(
          () => repo.submitRawSale(
            any(),
            employeeToken: any(named: 'employeeToken'),
          ),
        ).thenAnswer(
          (_) async => (
            success: false,
            connectivityError: false,
            retryable: false,
            message: 'Amounts disagree',
            code: 'MONEY_FIELD_MISMATCH',
          ),
        );
        await svc.syncNow();
        final row = (await store.getById('bad-1'))!;
        expect(row.status, 'failed');
        expect(row.errorCode, 'MONEY_FIELD_MISMATCH');
        expect(svc.unresolvedCount.value, 1);
      },
    );
  });
}
