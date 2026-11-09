// G3.3 return flow: the "Refund to" choice (only for a sale with a customer and the credit ledger on), refundTo on the request, the
// manager-approval retry for store_credit_refund_above_limit, plain error words, and the done screen's "Refunded to store credit".
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/utils/refund_instructions.dart';

import 'support/g3_fixtures.dart';

class _MockRepo extends Mock implements PosRepository {}

typedef _Refund = ({bool success, double? refundedAmount, String? newStatus, String? message, List<PosPaymentLine> tenders});

PosSaleModel creditSale({String? customerId = 'c1', List<Map<String, dynamic>>? payments}) => PosSaleModel.fromJson({
  '_id': 'sale-1',
  'saleNumber': 'POS-00007',
  'storeId': 'store-1',
  'sessionId': 's',
  'registerId': 'r',
  'employeeId': 'e',
  'status': 'completed',
  'currency': 'USD',
  'currencyExponent': 2,
  'subtotal': 10.0,
  'discount': 0,
  'tax': 0,
  'total': 10.0,
  'paymentMethod': 'cash',
  'customerName': 'Dev Customer',
  'customerId': ?customerId,
  'createdAt': '2026-11-06T10:00:00.000Z',
  'items': [
    {'_id': 'i1', 'productId': 'p1', 'variantId': 'v1', 'name': 'Yogurt', 'qty': 2, 'price': 5.0, 'lineTotal': 10.0, 'refundedQty': 0, 'netMinor': 1000, 'taxMinor': 0},
  ],
  'payments':
      payments ??
      [
        {'method': 'cash', 'amount': 10.0},
      ],
});

const _toCredit = (success: true, refundedAmount: 5.0, newStatus: 'partially_refunded', message: null, tenders: <PosPaymentLine>[PosPaymentLine(method: 'store_credit', amount: 5.0)]);

void main() {
  late _MockRepo repo;
  final approvalReasons = <String>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'store-1'});
    Get.reset();
    approvalReasons.clear();
    repo = _MockRepo();
    ReasonPicker.testOverride = (_) async => const PosReasonChoice('wrong_item', 'size');
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
    when(() => repo.lastCreditNote).thenReturn({'id': 'cn1', 'number': 'CN-000001', 'totalMinor': 500});
    when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => profile(credit: 2500));
  });

  tearDown(() {
    Get.reset();
    ReasonPicker.testOverride = null;
  });

  Future<PosReturnController> make({PosSaleModel? sale, bool approve = false}) async {
    when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale ?? creditSale());
    final c = PosReturnController(
      repository: repo,
      saleId: 'sale-1',
      approval: ({required String reason, PosRepository? repository}) async {
        approvalReasons.add(reason);
        return approve ? 'tok-mgr' : null;
      },
    );
    Get.put(c);
    await c.load();
    await Future<void>.delayed(Duration.zero);
    c.setQty('i1', 1);
    return c;
  }

  void stubRefund(Future<_Refund> Function(Invocation) f) => when(
    () => repo.refundSale(
      any(),
      items: any(named: 'items'),
      reasonCode: any(named: 'reasonCode'),
      reason: any(named: 'reason'),
      receiptPresented: any(named: 'receiptPresented'),
      approverToken: any(named: 'approverToken'),
      refundTo: any(named: 'refundTo'),
    ),
  ).thenAnswer(f);

  group('the Refund to choice', () {
    test('shown for a sale with a customer when the credit ledger is on; the default is the original payment method', () async {
      final c = await make();
      expect(c.canChooseRefundTo, isTrue);
      expect(c.refundTo.value, 'original');
    });

    test('hidden for a sale without a customer (and the customer is never asked about)', () async {
      final c = await make(sale: creditSale(customerId: null));
      expect(c.canChooseRefundTo, isFalse);
      verifyNever(() => repo.getCustomerProfile(any(), any()));
    });

    test('hidden when the credit ledger is off (the profile has no credit balance)', () async {
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => CustomerProfile(customer: customer(), cur: usd));
      final c = await make();
      expect(c.canChooseRefundTo, isFalse);
    });

    test('hidden when the profile cannot be read (offline, or a failure)', () async {
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => null);
      expect((await make()).canChooseRefundTo, isFalse);
      Get.reset();
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      clearInteractions(repo);
      expect((await make()).canChooseRefundTo, isFalse);
      verifyNever(() => repo.getCustomerProfile(any(), any()));
    });

    test('a sale paid entirely with store credit: nothing to choose, it goes back to credit', () async {
      final c = await make(
        sale: creditSale(
          payments: [
            {'method': 'store_credit', 'amount': 10.0},
          ],
        ),
      );
      expect(c.paidAllWithCredit, isTrue);
      expect(c.canChooseRefundTo, isFalse);
      c.setRefundTo('store_credit');
      expect(c.refundTo.value, 'original', reason: 'no choice is made when none is offered');
    });

    test('a failing profile call never throws into the return', () async {
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenThrow(StateError('boom'));
      expect((await make()).canChooseRefundTo, isFalse);
    });
  });

  group('refund request', () {
    test('Original payment method: refundTo is not sent; the instruction is the usual one', () async {
      final c = await make();
      expect(c.plan().single, contains('cash'));
      stubRefund((_) async => (success: true, refundedAmount: 5.0, newStatus: 'partially_refunded', message: null, tenders: const [PosPaymentLine(method: 'cash', amount: 5.0)]));
      expect(await c.confirm(), isTrue);
      verify(
        () => repo.refundSale(
          'sale-1',
          items: any(named: 'items'),
          reasonCode: 'wrong_item',
          reason: 'size',
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: any(named: 'approverToken'),
          refundTo: null,
        ),
      ).called(1);
      expect(c.resultCreditText.value, isNull);
    });

    test('Store credit: refundTo = store_credit is sent and the plan says it goes to credit', () async {
      final c = await make();
      c.setRefundTo('store_credit');
      expect(c.plan().single, "Add \$5.00 to the customer's store credit");
      stubRefund((_) async => _toCredit);
      expect(await c.confirm(), isTrue);
      verify(
        () => repo.refundSale(
          'sale-1',
          items: any(named: 'items'),
          reasonCode: 'wrong_item',
          reason: 'size',
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: any(named: 'approverToken'),
          refundTo: 'store_credit',
        ),
      ).called(1);
    });

    test('the done screen says how much went to store credit and the new balance', () async {
      final c = await make();
      c.setRefundTo('store_credit');
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => profile(credit: 3000));
      stubRefund((_) async => _toCredit);
      await c.confirm();
      expect(c.resultCreditText.value, '\$5.00');
      expect(c.resultBalanceText.value, '\$30.00');
      expect(c.resultInstructions.single, "Add \$5.00 to the customer's store credit");
    });

    test('the new balance is left out when it cannot be read; the credit amount still shows', () async {
      final c = await make();
      c.setRefundTo('store_credit');
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => null);
      stubRefund((_) async => _toCredit);
      await c.confirm();
      expect(c.resultCreditText.value, '\$5.00');
      expect(c.resultBalanceText.value, isNull);
    });

    test('a sale paid with store credit returns that part to credit (the server tender is shown) without any choice', () async {
      final c = await make(
        sale: creditSale(
          payments: [
            {'method': 'store_credit', 'amount': 10.0},
          ],
        ),
      );
      stubRefund((_) async => _toCredit);
      await c.confirm();
      verify(
        () => repo.refundSale(
          'sale-1',
          items: any(named: 'items'),
          reasonCode: any(named: 'reasonCode'),
          reason: any(named: 'reason'),
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: any(named: 'approverToken'),
          refundTo: null,
        ),
      ).called(1);
      expect(c.resultCreditText.value, '\$5.00');
    });
  });

  group('approval and errors', () {
    test('store_credit_refund_above_limit: a manager is asked (with the reason in words) and the SAME refund is sent again with their token', () async {
      final c = await make(approve: true);
      c.setRefundTo('store_credit');
      var calls = 0;
      stubRefund((_) async {
        calls++;
        return calls == 1 ? (success: false, refundedAmount: null, newStatus: null, message: 'x', tenders: const <PosPaymentLine>[]) : _toCredit;
      });
      when(() => repo.lastErrorCode).thenReturn('RETURN_NEEDS_MANAGER');
      when(() => repo.lastErrorReasons).thenReturn(const ['store_credit_refund_above_limit']);
      expect(await c.confirm(), isTrue);
      expect(approvalReasons.single, contains('store credit is above the limit'));
      verify(
        () => repo.refundSale(
          'sale-1',
          items: any(named: 'items'),
          reasonCode: any(named: 'reasonCode'),
          reason: any(named: 'reason'),
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: 'tok-mgr',
          refundTo: 'store_credit',
        ),
      ).called(1);
    });

    test('the approval text names the store-credit limit', () {
      expect(PosReturnController.approvalText(const ['store_credit_refund_above_limit']), 'A manager must approve this return: the amount going to store credit is above the limit.');
    });

    test('a cancelled approval sends nothing more', () async {
      final c = await make();
      c.setRefundTo('store_credit');
      stubRefund((_) async => (success: false, refundedAmount: null, newStatus: null, message: 'x', tenders: const <PosPaymentLine>[]));
      when(() => repo.lastErrorCode).thenReturn('RETURN_NEEDS_MANAGER');
      when(() => repo.lastErrorReasons).thenReturn(const ['store_credit_refund_above_limit']);
      expect(await c.confirm(), isFalse);
      verify(
        () => repo.refundSale(
          any(),
          items: any(named: 'items'),
          reasonCode: any(named: 'reasonCode'),
          reason: any(named: 'reason'),
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: any(named: 'approverToken'),
          refundTo: any(named: 'refundTo'),
        ),
      ).called(1);
    });

    for (final (code, words) in const [
      ('CUSTOMER_REQUIRED_FOR_CREDIT', 'Refunding to store credit needs a customer on the sale.'),
      ('STORE_CREDIT_NOT_ENABLED', 'Store credit is not switched on for this store.'),
    ]) {
      test('$code is shown in plain words', () async {
        final c = await make();
        c.setRefundTo('store_credit');
        stubRefund((_) async => (success: false, refundedAmount: null, newStatus: null, message: 'raw', tenders: const <PosPaymentLine>[]));
        when(() => repo.lastErrorCode).thenReturn(code);
        expect(await c.confirm(), isFalse);
        expect(c.error.value, words);
        expect(c.processing.value, isFalse);
      });
    }

    test('double tap: one request in flight', () async {
      final c = await make();
      c.setRefundTo('store_credit');
      stubRefund((_) async => _toCredit);
      final a = c.confirm();
      final b = await c.confirm();
      expect(b, isFalse);
      await a;
      verify(
        () => repo.refundSale(
          any(),
          items: any(named: 'items'),
          reasonCode: any(named: 'reasonCode'),
          reason: any(named: 'reason'),
          receiptPresented: any(named: 'receiptPresented'),
          approverToken: any(named: 'approverToken'),
          refundTo: any(named: 'refundTo'),
        ),
      ).called(1);
    });
  });

  test('a store_credit refund instruction reads plainly', () {
    expect(posRefundInstructions([const PosRefundSplit('store_credit', 8)], currency: 'USD', exponent: 2).single, "Add \$8.00 to the customer's store credit");
  });
}
