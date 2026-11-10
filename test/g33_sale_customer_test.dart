// G3.3 on the till: the store-credit tender and loyalty redemption rules of the sale controller (what is offered, the display
// arithmetic, the sale body, plain error words, offline) against a mocked PosRepository.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/g3_fixtures.dart';

class _MockRepo extends Mock implements PosRepository {}

PosProductModel _product({double price = 10}) => PosProductModel(
  productId: 'p',
  name: 'Yogurt',
  type: 'physical',
  categoryId: 'c',
  variants: [PosProductVariant(variantId: 'p_v', sku: 'S', price: price, stock: 50, isDefault: true)],
);

CustomerConfig _config({bool credit = true, bool loyalty = true, InvCur cur = usd}) => CustomerConfig(
  cur: cur,
  storeCreditTenderEnabled: credit,
  loyalty: LoyaltyRules(enabled: loyalty, earnSpendMinor: 1000, redeemMinorPerPoint: 50),
);

void main() {
  late _MockRepo repo;
  late PosHomeController c;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    Money.configure(currency: 'USD', exponent: 2);
    repo = _MockRepo();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(
      () => repo.quoteSale(
        storeId: any(named: 'storeId'),
        items: any(named: 'items'),
        discountType: any(named: 'discountType'),
        discountValue: any(named: 'discountValue'),
        settingsVersion: any(named: 'settingsVersion'),
        priceBookId: any(named: 'priceBookId'),
        customerId: any(named: 'customerId'),
      ),
    ).thenAnswer((_) async => (quote: null, message: null, code: null));
  });

  tearDown(() {
    c.searchController.dispose();
    c.noteController.dispose();
    c.customerController.dispose();
    c.discountController.dispose();
    c.tenderedController.dispose();
    c.paymentReferenceController.dispose();
    c.productScrollController.dispose();
  });

  /// A controller with a [quantity] x $10 line and the customer attached with the store's rules loaded.
  Future<void> make({int quantity = 2, double price = 10, PosCustomer? who, CustomerConfig? config, double taxRate = 0}) async {
    c = PosHomeController(posRepository: repo);
    c.storeId.value = 'store-1';
    c.sessionId.value = 'session-1';
    c.registerId.value = 'r';
    c.employeeId.value = 'e';
    c.cartItems.add(
      CartItem(
        product: _product(price: price),
        variant: _product(price: price).variants.first,
        qty: quantity,
      ),
    );
    when(() => repo.getCustomerProfile('store-1', any())).thenAnswer((_) async => null);
    when(() => repo.getCustomerConfig('store-1')).thenAnswer((_) async => config ?? _config());
    c.saleCustomer.attach(who ?? customer(), usd);
    await c.saleCustomer.refresh();
  }

  Future<void> pumpApp(WidgetTester t) => t.pumpWidget(
    ResponsiveSizer(
      builder: (_, __, ___) => GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
    ),
  );

  void goOffline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  group('store credit tender', () {
    test('offered only with: store tender on, a customer with a balance, the ledger on, the same currency, and online', () async {
      await make();
      expect(c.storeCreditOffered, isTrue);
      c.saleCustomer.detach();
      expect(c.storeCreditOffered, isFalse, reason: 'no customer');
    });

    test('not offered when the store has not switched the tender on', () async {
      await make(config: _config(credit: false));
      expect(c.storeCreditOffered, isFalse);
    });

    test('not offered without a balance, or when the credit ledger is off (balance unknown)', () async {
      await make(who: customer(credit: 0));
      expect(c.storeCreditOffered, isFalse);
      c.saleCustomer.detach();
      c.saleCustomer.attach(customer(credit: null), usd);
      await c.saleCustomer.refresh();
      expect(c.storeCreditOffered, isFalse);
    });

    test('not offered offline, and not when the response currency is not the sale currency', () async {
      await make();
      goOffline();
      expect(c.storeCreditOffered, isFalse);
      Get.reset();
      await make(
        config: _config(cur: const InvCur('EUR', 2)),
        who: customer(),
      );
      c.saleCustomer.cur.value = const InvCur('EUR', 2);
      expect(c.storeCreditOffered, isFalse);
    });

    test('Use store credit: the whole amount when the balance covers it', () async {
      await make(quantity: 1, who: customer(credit: 2000)); // due 10.00, credit 20.00
      c.useStoreCredit();
      expect(c.isSplitPayment.value, isTrue);
      expect(c.splitLines, hasLength(1));
      expect(c.splitLines.single.method.value, 'store_credit');
      expect(c.splitLines.single.amount.text, '10.00');
      expect(c.paymentCheck.covered, isTrue);
      expect(c.canCharge, isTrue);
    });

    test('Use store credit: the whole balance, the rest left in a cash row (split)', () async {
      await make(quantity: 2, who: customer(credit: 500)); // due 20.00, credit 5.00
      c.useStoreCredit();
      expect(c.splitLines.map((l) => (l.method.value, l.amount.text)), [('store_credit', '5.00'), ('cash', '15.00')]);
      expect(c.paymentCheck.covered, isTrue);
    });

    test('more than the balance is refused with the balance in the words; the Charge button is off', () async {
      await make(quantity: 2, who: customer(credit: 500));
      c.useStoreCredit();
      c.splitLines.first.amount.text = '9.00';
      expect(c.storeCreditIssue, contains('more than the customer'));
      expect(c.storeCreditIssue, contains(r'$5.00'));
      expect(c.canCharge, isFalse);
      c.splitLines.first.amount.text = '5.00';
      expect(c.storeCreditIssue, isNull);
    });

    test('store credit on a sale without a customer, or after going offline, cannot be charged', () async {
      await make(quantity: 1);
      c.useStoreCredit();
      c.saleCustomer.detach();
      expect(c.storeCreditIssue, 'Choose the customer first.');
      expect(c.canCharge, isFalse);
      await c.saleCustomer.refresh();
      c.saleCustomer.attach(customer(), usd);
      expect(c.storeCreditIssue, isNull);
      goOffline();
      expect(c.storeCreditIssue, 'Store credit needs an internet connection.');
      expect(c.canCharge, isFalse);
    });

    test('a store-credit row is offered in a split row once, and stays listed on the row that has it', () async {
      await make();
      c.toggleSplitPayment();
      expect(c.splitChoicesFor(0), contains('store_credit'));
      c.splitLines[0].method.value = 'store_credit';
      expect(c.splitChoicesFor(0), contains('store_credit'));
      expect(c.splitChoicesFor(1), isNot(contains('store_credit')), reason: 'one credit row per sale');
    });

    testWidgets('Charge sends the store_credit line (major units) with the customer id', (t) async {
      await pumpApp(t);
      await make(quantity: 1, who: customer(id: 'cust-9', credit: 2000));
      c.selectedCustomer.value = null;
      c.attachCustomer(customer(id: 'cust-9', credit: 2000), usd);
      await c.saleCustomer.refresh();
      c.useStoreCredit();
      List<Map<String, dynamic>>? payments;
      String? customerId;
      when(
        () => repo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discountType: any(named: 'discountType'),
          discountValue: any(named: 'discountValue'),
          clientTotal: any(named: 'clientTotal'),
          settingsVersion: any(named: 'settingsVersion'),
          clientCreatedAt: any(named: 'clientCreatedAt'),
          paymentMethod: any(named: 'paymentMethod'),
          payments: any(named: 'payments'),
          amountTendered: any(named: 'amountTendered'),
          paymentReference: any(named: 'paymentReference'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((i) async {
        payments = (i.namedArguments[#payments] as List?)?.cast<Map<String, dynamic>>();
        customerId = i.namedArguments[#customerId] as String?;
        return (success: true, sale: null as PosSaleModel?, message: null, queued: false);
      });
      await c.completeSale();
      expect(payments, [
        {'method': 'store_credit', 'amount': 10.0},
      ]);
      expect(customerId, 'cust-9');
      await t.pump(const Duration(seconds: 4));
    });

    for (final (code, words) in const [
      ('STORE_CREDIT_INSUFFICIENT', 'The customer does not have enough store credit for this.'),
      ('STORE_CREDIT_ONLINE_ONLY', 'Store credit needs an internet connection.'),
      ('CUSTOMER_REQUIRED', 'Choose the customer first.'),
      ('STORE_CREDIT_NOT_ENABLED', 'Store credit is not switched on for this store.'),
    ]) {
      testWidgets('the server answering $code is shown in plain words', (t) async {
        await pumpApp(t);
        await make(quantity: 1);
        c.useStoreCredit();
        when(() => repo.lastErrorCode).thenReturn(code);
        when(
          () => repo.createSale(
            storeId: any(named: 'storeId'),
            sessionId: any(named: 'sessionId'),
            registerId: any(named: 'registerId'),
            employeeId: any(named: 'employeeId'),
            items: any(named: 'items'),
            discountType: any(named: 'discountType'),
            discountValue: any(named: 'discountValue'),
            clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'),
            clientCreatedAt: any(named: 'clientCreatedAt'),
            paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'),
            amountTendered: any(named: 'amountTendered'),
            paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'),
            customerId: any(named: 'customerId'),
            notes: any(named: 'notes'),
            status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((_) async => (success: false, sale: null as PosSaleModel?, message: 'raw', queued: false));
        await c.completeSale();
        await t.pump();
        expect(find.text(words), findsOneWidget);
        await t.pump(const Duration(seconds: 4));
      });
    }
  });

  group('redeem points', () {
    test('offered only with: loyalty on with a point value, a customer with points, the same currency', () async {
      await make();
      expect(c.saleCustomer.pointsEnabled, isTrue);
      await make(config: _config(loyalty: false));
      expect(c.saleCustomer.pointsEnabled, isFalse);
      await make(who: customer(points: 0));
      expect(c.saleCustomer.pointsEnabled, isFalse);
      c.saleCustomer.detach();
      expect(c.saleCustomer.pointsEnabled, isFalse);
    });

    test('the most points: what the customer has, and whole points that fit in the subtotal', () async {
      await make(quantity: 2, who: customer(points: 40)); // subtotal 20.00 = 2000 minor, a point is 50 minor → 40 fit
      expect(c.maxRedeemPoints, 40);
      await make(quantity: 1, who: customer(points: 40)); // 10.00 → 20 fit
      expect(c.maxRedeemPoints, 20);
      await make(quantity: 1, who: customer(points: 7));
      expect(c.maxRedeemPoints, 7);
      await make(quantity: 1, price: 0.4, who: customer(points: 40)); // 0.40 → 0 whole points fit
      expect(c.maxRedeemPoints, 0);
    });

    test('the stepper is clamped to 0..max', () async {
      await make(quantity: 1, who: customer(points: 12));
      c.setRedeemPoints(50);
      expect(c.saleCustomer.redeemPoints.value, 12);
      c.setRedeemPoints(-3);
      expect(c.saleCustomer.redeemPoints.value, 0);
    });

    test('live preview: the redemption comes off the sale like a flat discount (tax on what is left)', () async {
      await make(quantity: 2, who: customer(points: 40));
      c.setRedeemPoints(10); // 10 x 0.50 = 5.00
      expect(c.redeemValueMajor, 5.0);
      expect(c.totals.discount, 5.0);
      expect(c.totals.total, 15.0);
      expect(c.saleCustomer.redeemValueMinor, 500);
    });

    test('a coupon or a manual discount switches the redemption off (the server refuses both together)', () async {
      await make(quantity: 2, who: customer(points: 40));
      c.setRedeemPoints(10);
      expect(c.totals.total, 15.0);
      c.discountController.text = '2';
      expect(c.redeemPointsEffective, 0);
      expect(c.totals.discount, 2.0);
      c.discountController.text = '0';
      c.appliedCoupon.value = const PosAppliedCoupon(code: 'X', discountType: 'percentage', discountValue: 10);
      expect(c.redeemPointsEffective, 0);
      expect(c.totals.discount, isNot(5.0));
    });

    test('offline: the stepper does nothing; points chosen before going offline block the charge with an honest message', () async {
      await make(quantity: 2, who: customer(points: 40));
      c.setRedeemPoints(4);
      goOffline();
      c.setRedeemPoints(8);
      expect(c.saleCustomer.redeemPoints.value, 4);
      expect(c.redeemIssue, 'Points can only be redeemed with an internet connection.');
      expect(c.canCharge, isFalse);
    });

    test('changing the customer drops the chosen points', () async {
      await make(quantity: 2, who: customer(points: 40));
      c.setRedeemPoints(4);
      c.saleCustomer.attach(customer(id: 'other'), usd);
      expect(c.saleCustomer.redeemPoints.value, 0);
    });

    testWidgets('Charge sends redeemPoints, NO discount, and the reduced client total; the quote is priced with the same flat amount', (t) async {
      await pumpApp(t);
      await make(quantity: 2, who: customer(points: 40));
      c.selectedPayment.value = PosPaymentMethod.card;
      c.setRedeemPoints(10);
      Map<Symbol, dynamic>? seen;
      when(
        () => repo.createSale(
          storeId: any(named: 'storeId'),
          sessionId: any(named: 'sessionId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          items: any(named: 'items'),
          discountType: any(named: 'discountType'),
          discountValue: any(named: 'discountValue'),
          clientTotal: any(named: 'clientTotal'),
          settingsVersion: any(named: 'settingsVersion'),
          clientCreatedAt: any(named: 'clientCreatedAt'),
          paymentMethod: any(named: 'paymentMethod'),
          payments: any(named: 'payments'),
          amountTendered: any(named: 'amountTendered'),
          paymentReference: any(named: 'paymentReference'),
          customerName: any(named: 'customerName'),
          customerId: any(named: 'customerId'),
          notes: any(named: 'notes'),
          status: any(named: 'status'),
          idempotencyKey: any(named: 'idempotencyKey'),
          couponCode: any(named: 'couponCode'),
          approverToken: any(named: 'approverToken'),
          expiredApproverToken: any(named: 'expiredApproverToken'),
          redeemPoints: any(named: 'redeemPoints'),
        ),
      ).thenAnswer((i) async {
        seen = Map.of(i.namedArguments);
        return (success: true, sale: null as PosSaleModel?, message: null, queued: false);
      });
      await c.completeSale();
      expect(seen![#redeemPoints], 10);
      expect((seen![#discountValue] as num?) ?? 0, 0, reason: 'the server prices the redemption; a discount next to it would be refused');
      expect(seen![#clientTotal], 15.0);
      verify(
        () => repo.quoteSale(
          storeId: 'store-1',
          items: any(named: 'items'),
          discountType: 'amount',
          discountValue: 5.0,
          settingsVersion: any(named: 'settingsVersion'),
          priceBookId: any(named: 'priceBookId'),
          customerId: any(named: 'customerId'),
        ),
      ).called(1);
      await t.pump(const Duration(seconds: 4));
    });

    for (final (code, words) in const [
      ('LOYALTY_INSUFFICIENT_POINTS', 'The customer does not have that many points.'),
      ('LOYALTY_WITH_DISCOUNT', 'Points cannot be combined with a coupon or a discount on the same sale.'),
      ('LOYALTY_EXCEEDS_SALE', 'Those points are worth more than the sale. Use fewer points.'),
      ('LOYALTY_ONLINE_ONLY', 'Points can only be redeemed with an internet connection.'),
      ('LOYALTY_NOT_ENABLED', 'Points cannot be redeemed at the till for this store.'),
    ]) {
      testWidgets('the server answering $code is shown in plain words', (t) async {
        await pumpApp(t);
        await make(quantity: 2, who: customer(points: 40));
        c.selectedPayment.value = PosPaymentMethod.card;
        c.setRedeemPoints(4);
        when(() => repo.lastErrorCode).thenReturn(code);
        when(
          () => repo.createSale(
            storeId: any(named: 'storeId'),
            sessionId: any(named: 'sessionId'),
            registerId: any(named: 'registerId'),
            employeeId: any(named: 'employeeId'),
            items: any(named: 'items'),
            discountType: any(named: 'discountType'),
            discountValue: any(named: 'discountValue'),
            clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'),
            clientCreatedAt: any(named: 'clientCreatedAt'),
            paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'),
            amountTendered: any(named: 'amountTendered'),
            paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'),
            customerId: any(named: 'customerId'),
            notes: any(named: 'notes'),
            status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
            couponCode: any(named: 'couponCode'),
            approverToken: any(named: 'approverToken'),
            expiredApproverToken: any(named: 'expiredApproverToken'),
            redeemPoints: any(named: 'redeemPoints'),
          ),
        ).thenAnswer((_) async => (success: false, sale: null as PosSaleModel?, message: 'raw', queued: false));
        await c.completeSale();
        await t.pump();
        expect(find.text(words), findsOneWidget);
        await t.pump(const Duration(seconds: 4));
      });
    }
  });

  group('the customer on the sale', () {
    test('typing a different name detaches the customer, their balances and the chosen points', () async {
      await make(quantity: 2, who: customer(points: 40));
      c.attachCustomer(customer(), usd);
      await c.saleCustomer.refresh();
      c.setRedeemPoints(4);
      c.onCustomerTextChanged('Someone else');
      expect(c.selectedCustomer.value, isNull);
      expect(c.saleCustomer.customer.value, isNull);
      expect(c.saleCustomer.redeemPoints.value, 0);
    });

    test('clearing the sale detaches the customer too', () async {
      await make();
      c.clearSale();
      expect(c.saleCustomer.attached, isFalse);
    });

    test('the freshest balances replace the search row\'s; a failing profile call leaves what is known and never throws', () async {
      await make(who: customer(credit: 100, points: 1));
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => profile(credit: 2500, points: 33));
      await c.saleCustomer.refresh();
      expect(c.saleCustomer.creditBalanceMinor, 2500);
      expect(c.saleCustomer.points, 33);
      when(() => repo.getCustomerProfile('store-1', 'c1')).thenThrow(StateError('boom'));
      await c.saleCustomer.refresh();
      expect(c.saleCustomer.creditBalanceMinor, 2500);
    });
  });
}
