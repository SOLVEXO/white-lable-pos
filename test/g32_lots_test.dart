// G3.2 on the till: the remembered first-expiry-first-out suggestion (cache), the cart lines' lot advisor (online, debounce, offline,
// not lot-tracked), and the manager-approved "sell expired stock" flow of the sale controller.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/cart_lot_advisor.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';

class _MockRepo extends Mock implements PosRepository {}

LotPreview _preview(String variantId, {int qty = 1, int shortBy = 0, int expired = 0, List<LotAllocation>? allocations, bool tracked = true}) => LotPreview(
  variantId: variantId,
  trackLots: tracked,
  qty: qty,
  shortBy: shortBy,
  expiredUnits: expired,
  allocations: allocations ?? [LotAllocation(lotId: 'l1', lotNumber: 'LOT-SOON', take: qty, daysLeft: 3)],
  asOf: DateTime.utc(2026, 11, 9, 10),
);

PosProductModel _product(String id, {bool unlimited = false}) => PosProductModel(
  productId: id,
  name: 'Yogurt',
  type: 'physical',
  categoryId: 'c',
  variants: [PosVariantFixture.make('${id}_v', unlimited: unlimited)],
);

class PosVariantFixture {
  static PosProductVariant make(String id, {bool unlimited = false}) => PosProductVariant(variantId: id, sku: 'SKU-$id', price: 4, stock: 12, unlimitedStock: unlimited, isDefault: true);
}

void main() {
  late _MockRepo repo;
  late LotPreviewCache cache;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    repo = _MockRepo();
    cache = LotPreviewCache();
  });

  group('LotPreviewCache', () {
    test('remembers the latest answer per item, marked with when it was received', () async {
      final clock = DateTime.utc(2026, 11, 9, 12);
      final c = LotPreviewCache(clock: () => clock);
      await c.put(LotPreview(variantId: 'v1', trackLots: true, qty: 2, allocations: const []));
      expect(c.get('v1')!.asOf, clock);
      await c.put(_preview('v1', qty: 3));
      expect(c.get('v1')!.qty, 3);
      expect(c.length, 1);
    });

    test('is capped at 200 entries: the oldest answers go first', () async {
      for (var i = 0; i < 205; i++) {
        await cache.put(_preview('v$i'));
      }
      expect(cache.length, LotPreviewCache.maxEntries);
      expect(cache.get('v0'), isNull);
      expect(cache.get('v204'), isNotNull);
    });

    test('is persisted: a fresh instance reads the earlier answers back; a corrupt blob is ignored', () async {
      await cache.put(_preview('v1', qty: 5));
      final again = LotPreviewCache();
      await again.load();
      expect(again.get('v1')!.qty, 5);
      expect(again.get('v1')!.first!.lotNumber, 'LOT-SOON');

      SharedPreferences.setMockInitialValues({'pos_lot_preview_cache': '{not json'});
      final broken = LotPreviewCache();
      await broken.load();
      expect(broken.length, 0);
    });
  });

  group('CartLotAdvisor', () {
    var online = true;
    late CartLotAdvisor advisor;
    DateTime now = DateTime.utc(2026, 11, 9, 10);

    setUp(() {
      online = true;
      now = DateTime.utc(2026, 11, 9, 10);
      advisor = CartLotAdvisor(repository: repo, cache: cache, isOnline: () => online, storeId: () => 'st1', debounce: const Duration(milliseconds: 40), clock: () => now);
    });
    tearDown(() => advisor.dispose());

    Future<void> pause([int ms = 80]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('online: asks the server for the line\'s quantity and shows the live answer; custom and unlimited items are skipped', () async {
      when(() => repo.getLotPreview('st1', 'a_v', 2)).thenAnswer((_) async => _preview('a_v', qty: 2));
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first, qty: 2);
      advisor.request(item);
      await pause();
      expect(item.lotPreview.value!.headline, 'Lot LOT-SOON · expires in 3 d');
      expect(item.lotPreviewLive.value, isTrue);
      expect(cache.get('a_v'), isNotNull);

      final unlimited = CartItem(product: _product('u', unlimited: true), variant: _product('u', unlimited: true).variants.first);
      advisor.request(unlimited);
      advisor.request(CartItem.custom(id: 'x', name: 'x', price: 1));
      await pause();
      verifyNever(() => repo.getLotPreview(any(), 'u_v', any()));
    });

    test('quick quantity taps fold into one trailing request with the NEWEST quantity; a stale answer never overwrites it', () async {
      final answers = <int, Completer<LotPreview?>>{};
      when(() => repo.getLotPreview('st1', 'a_v', any())).thenAnswer((i) => (answers[i.positionalArguments[2] as int] = Completer<LotPreview?>()).future);
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first);
      advisor.request(item); // first look: immediate, qty 1
      await pause(5);
      item.quantity.value = 2;
      advisor.request(item);
      item.quantity.value = 3;
      advisor.request(item);
      await pause(120); // the trailing request (qty 3) went out
      verifyNever(() => repo.getLotPreview('st1', 'a_v', 2));
      verify(() => repo.getLotPreview('st1', 'a_v', 3)).called(1);
      answers[3]!.complete(_preview('a_v', qty: 3));
      await pause(10);
      answers[1]!.complete(
        _preview(
          'a_v',
          qty: 1,
          allocations: [const LotAllocation(lotId: 'x', lotNumber: 'STALE', take: 1)],
        ),
      );
      await pause(10);
      expect(item.lotPreview.value!.qty, 3); // the stale qty-1 answer arrived last and was dropped
    });

    test('offline: shows the remembered suggestion marked "not live" and never calls the server', () async {
      await cache.put(_preview('a_v'));
      online = false;
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first);
      advisor.request(item);
      await pause();
      expect(item.lotPreview.value!.first!.lotNumber, 'LOT-SOON');
      expect(item.lotPreviewLive.value, isFalse);
      expect(item.lotPreview.value!.asOf, isNotNull);
      verifyNever(() => repo.getLotPreview(any(), any(), any()));
    });

    test('the server cannot be reached: the line keeps what it had, nothing throws', () async {
      await cache.put(_preview('a_v'));
      when(() => repo.getLotPreview(any(), any(), any())).thenAnswer((_) async => null);
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first);
      advisor.request(item);
      await pause();
      expect(item.lotPreview.value!.first!.lotNumber, 'LOT-SOON');
      expect(item.lotPreviewLive.value, isFalse);
    });

    test('an item that is not lot-tracked shows nothing and is not asked about again for a while', () async {
      when(() => repo.getLotPreview(any(), any(), any())).thenAnswer((_) async => _preview('a_v', tracked: false, allocations: const []));
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first);
      advisor.request(item);
      await pause();
      expect(item.lotPreview.value, isNull);
      advisor.request(item);
      await pause();
      verify(() => repo.getLotPreview(any(), any(), any())).called(1);
      now = now.add(const Duration(hours: 2)); // later it is asked again
      advisor.request(item);
      await pause();
      verify(() => repo.getLotPreview(any(), any(), any())).called(1);
    });

    test('the sell-expired approval is dropped once the sellable units cover the quantity again', () async {
      when(() => repo.getLotPreview('st1', 'a_v', 1)).thenAnswer((_) async => _preview('a_v', qty: 1));
      final item = CartItem(product: _product('a'), variant: _product('a').variants.first);
      item.sellExpired.value = true;
      advisor.request(item);
      await pause();
      expect(item.sellExpired.value, isFalse);
    });
  });

  group('sell expired stock (sale controller)', () {
    late PosHomeController c;
    final approvals = <String>[];

    Future<void> pumpApp(WidgetTester t) => t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
      ),
    );

    PosHomeController make({Future<String?> Function({required String reason, PosRepository? repository})? approval, CartLotAdvisor? advisor}) {
      c = PosHomeController(
        posRepository: repo,
        approval: approval,
        lotAdvisor: advisor ?? CartLotAdvisor(repository: repo, cache: cache, isOnline: () => true, storeId: () => 'store-1'),
      );
      c.storeId.value = 'store-1';
      c.sessionId.value = 'session-1';
      c.registerId.value = 'r';
      c.employeeId.value = 'e';
      c.selectedPayment.value = PosPaymentMethod.card;
      return c;
    }

    CartItem line() {
      final p = _product('a');
      final item = CartItem(product: p, variant: p.variants.first, qty: 4);
      item.lotPreview.value = _preview('a_v', qty: 4, shortBy: 2, expired: 4);
      item.lotPreviewLive.value = true;
      c.cartItems.add(item);
      return item;
    }

    setUp(() {
      approvals.clear();
      when(
        () => repo.quoteSale(
          storeId: any(named: 'storeId'),
          items: any(named: 'items'),
          discountType: any(named: 'discountType'),
          discountValue: any(named: 'discountValue'),
          settingsVersion: any(named: 'settingsVersion'),
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

    test('a manager approves: the line is marked and the approval is asked once even on a double tap', () async {
      final gate = Completer<String?>();
      make(
        approval: ({required String reason, PosRepository? repository}) {
          approvals.add(reason);
          return gate.future;
        },
      );
      final item = line();
      final a = c.approveSellExpired(item);
      final b = c.approveSellExpired(item); // double tap while the sheet is open
      expect(await b, isFalse);
      gate.complete('tok-mgr');
      expect(await a, isTrue);
      expect(approvals, hasLength(1));
      expect(item.sellExpired.value, isTrue);
    });

    test('cancelled approval changes nothing; no override when nothing expired is needed', () async {
      make(approval: ({required String reason, PosRepository? repository}) async => null);
      final item = line();
      expect(await c.approveSellExpired(item), isFalse);
      expect(item.sellExpired.value, isFalse);
      item.lotPreview.value = _preview('a_v', qty: 4); // shortBy 0
      expect(await c.approveSellExpired(item), isFalse);
    });

    test('offline: the override is refused and nothing is asked', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      make(
        approval: ({required String reason, PosRepository? repository}) async {
          approvals.add(reason);
          return 'tok';
        },
      );
      expect(await c.approveSellExpired(line()), isFalse);
      expect(approvals, isEmpty);
    });

    testWidgets('Charge sends sellExpired on the line and the manager token as expiredApproverToken', (t) async {
      await pumpApp(t);
      make(approval: ({required String reason, PosRepository? repository}) async => 'tok-mgr');
      final item = line();
      await c.approveSellExpired(item);
      List<Map<String, dynamic>>? items;
      String? token;
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
        ),
      ).thenAnswer((i) async {
        items = (i.namedArguments[#items] as List).cast<Map<String, dynamic>>();
        token = i.namedArguments[#expiredApproverToken] as String?;
        return (success: true, sale: null as PosSaleModel?, message: null, queued: false);
      });
      await c.completeSale();
      expect(items!.single['sellExpired'], isTrue);
      expect(token, 'tok-mgr');
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('a line that was never approved sends no sellExpired and no token', (t) async {
      await pumpApp(t);
      make();
      line();
      final seen = <Map<Symbol, dynamic>>[];
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
        seen.add(Map.of(i.namedArguments));
        return (success: true, sale: null as PosSaleModel?, message: null, queued: false);
      });
      await c.completeSale();
      expect(seen.single[#expiredApproverToken], isNull);
      expect(((seen.single[#items] as List).single as Map).containsKey('sellExpired'), isFalse);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('the server refusing the approval takes it back and says so in plain words', (t) async {
      await pumpApp(t);
      make(approval: ({required String reason, PosRepository? repository}) async => 'tok-stale');
      final item = line();
      await c.approveSellExpired(item);
      when(() => repo.lastErrorCode).thenReturn('POS_APPROVAL_REQUIRED');
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
        ),
      ).thenAnswer((_) async => (success: false, sale: null as PosSaleModel?, message: 'needs a manager', queued: false));
      await c.completeSale();
      expect(item.sellExpired.value, isFalse);
      await t.pump(const Duration(seconds: 4));
    });
  });
}
