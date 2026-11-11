// G4.6 on the till: counting the float / drawer note by note (the server checks the notes add up to the amount; a mismatch is said in words), the
// last close of the register shown when the next shift opens, stock transfers (ship / receive / cancel), lots by expiry with write-off, and low stock
// → a draft purchase order. Phone, tablet and dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/components/denomination_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/views/pos_open_register_view.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/controllers/transfers_controller.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/draft_po_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/expiry_view.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/transfers_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class _Repo extends Mock implements PosRepository {}

typedef _W = ({bool success, String? message, String? code, Map<String, dynamic>? data});

const _phone = Size(390, 1600);
const _tablet = Size(1024, 1366);

enum _Env { phone, tablet, dark }

PosEmployeeModel _employee() => PosEmployeeModel(id: 'emp-1', storeId: 'st1', sellerId: 's', name: 'Ayesha', email: 'a@x', role: 'cashier', shiftIds: const ['shift-1'], status: 'active', createdAt: DateTime(2026));

PosSessionModel _session() => PosSessionModel(
  id: 'session-1',
  storeId: 'st1',
  registerId: 'r1',
  employeeId: 'emp-1',
  shiftId: 'shift-1',
  openedAt: DateTime(2026),
  openingCash: 6000,
  expectedCash: 6000,
  cashDifference: 0,
  cashSales: 0,
  cardSales: 0,
  otherSales: 0,
  totalSales: 0,
  totalTransactions: 0,
  totalRefunds: 0,
  status: 'open',
  cashAdjustments: const [],
);

StoreLocationModel _loc(String id, String name) => StoreLocationModel(id: id, storeId: 'st1', sellerId: 's', name: name, status: 'active', createdAt: DateTime(2026));

StockTransfer _transfer(String id, {String status = 'in_transit', int qty = 10, int received = 0}) => StockTransfer.fromJson({
  '_id': id,
  'productName': 'Basmati rice 5kg',
  'variantLabel': null,
  'fromLocationName': 'Main shop',
  'toLocationName': 'Warehouse',
  'quantity': qty,
  'receivedQuantity': received,
  'status': status,
  'createdAt': '2026-11-10T09:00:00Z',
  'transferredByName': 'Bilal',
});

ExpiryBuckets _buckets({bool cost = true, bool empty = false}) => ExpiryBuckets.fromJson({
  'currency': 'PKR',
  'currencyExponent': 2,
  'expired': empty
      ? []
      : [
          {'lotId': 'l1', 'lotNumber': 'B-17', 'variantId': 'v1', 'sku': 'MILK-1', 'productName': 'Milk 1L', 'expiryDate': '2026-11-08T00:00:00Z', 'remaining': 6, 'daysLeft': -3, if (cost) 'valueMinor': 120000},
        ],
  'within7': empty
      ? []
      : [
          {'lotId': 'l2', 'lotNumber': 'Y-02', 'variantId': 'v2', 'productName': 'Yogurt', 'expiryDate': '2026-11-14T00:00:00Z', 'remaining': 12, 'daysLeft': 3, if (cost) 'valueMinor': 96000},
        ],
  'within30': [],
});

void main() {
  late _Repo repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    Money.configure(currency: 'PKR', exponent: 2);
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
  });

  tearDown(() => Money.configure(currency: 'USD', exponent: 2));

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          key: UniqueKey(),
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(name: Routes.posSupplyOrder, page: () => Scaffold(body: Text('PO:${(Get.arguments as Map)['orderId']}'))),
            GetPage(name: Routes.posHome, page: () => const Scaffold(body: Text('HOME'))),
          ],
          home: w,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t);
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  // ── notes & coins ─────────────────────────────────────────────────────────────────────────
  group('notes & coins', () {
    test('known currencies list their notes and coins in minor units; an unknown one has none', () {
      expect(denominationsFor('PKR')!.first, 5000);
      expect(denominationsFor('XYZ'), isNull);
      final rows = <Denomination>[(valueMinor: 500000, count: 2), (valueMinor: 10000, count: 3), (valueMinor: 100, count: 0)];
      expect(denominationTotal(rows), 1030000);
      expect(denominationsJson(rows), [
        {'valueMinor': 500000, 'count': 2},
        {'valueMinor': 10000, 'count': 3},
      ]);
    });

    for (final env in _Env.values) {
      testWidgets('${env.name}: count with +/− or by typing; the total is what is used', (t) async {
        List<Denomination>? got;
        await pump(t, Builder(builder: (_) => Scaffold(body: Center(child: TextButton(key: const Key('go'), onPressed: () async => got = await DenominationSheet.open(currency: 'PKR', exponent: 2), child: const Text('go'))))), env);
        await tapKey(t, 'go');
        expect(find.byKey(const Key('denominationSheet')), findsOneWidget);
        await tapKey(t, 'denomPlus_500000');
        await tapKey(t, 'denomPlus_500000');
        await t.enterText(find.byKey(const Key('denomCount_10000')), '3');
        await settle(t);
        expect(find.text(Money.format(10300, currency: 'PKR', exponent: 2)), findsWidgets);
        await tapKey(t, 'denomMinus_500000');
        await tapKey(t, 'denomUse');
        expect(got, [(valueMinor: 500000, count: 1), (valueMinor: 10000, count: 3)]);
        expect(t.takeException(), isNull);
      });
    }
  });

  // ── open shift ────────────────────────────────────────────────────────────────────────────
  group('open shift', () {
    PosOpenRegisterController ctl() {
      final c = PosOpenRegisterController(posRepository: repo);
      c.employee = _employee();
      c.registerId = 'r1';
      c.registerName = 'Front counter';
      c.storeId = 'st1';
      return c;
    }

    void stubOpen(Future<({bool success, PosSessionModel? session, String? message})> Function() f) => when(
      () => repo.openSession(
        storeId: any(named: 'storeId'),
        registerId: any(named: 'registerId'),
        employeeId: any(named: 'employeeId'),
        shiftId: any(named: 'shiftId'),
        openingCash: any(named: 'openingCash'),
        denominations: any(named: 'denominations'),
      ),
    ).thenAnswer((_) => f());

    for (final env in [_Env.phone, _Env.dark]) {
      testWidgets('${env.name}: the last close of the register (short by 200) and the count button', (t) async {
        when(() => repo.getLastClose('st1', 'r1')).thenAnswer(
          (_) async => LastClose.fromJson({
            'currency': 'PKR',
            'currencyExponent': 2,
            'lastClose': {'closedAt': '2026-11-10T21:00:00Z', 'closedByName': 'Bilal', 'countedMinor': 980000, 'expectedMinor': 1000000, 'varianceMinor': -20000},
          }),
        );
        Get.put(ctl());
        await pump(t, PosOpenRegisterView(), env);
        expect(find.byKey(const Key('lastCloseCard')), findsOneWidget);
        expect(find.text('Short ${Money.format(200, currency: 'PKR', exponent: 2)}'), findsOneWidget);
        expect(find.textContaining('Bilal'), findsOneWidget);
        expect(find.byKey(const Key('countFloat')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a register never closed: no card; an unknown currency: no counter', (t) async {
      when(() => repo.getLastClose('st1', 'r1')).thenAnswer((_) async => null);
      Money.configure(currency: 'XYZ', exponent: 2);
      Get.put(ctl());
      await pump(t, PosOpenRegisterView());
      expect(find.byKey(const Key('lastCloseCard')), findsNothing);
      expect(find.byKey(const Key('countFloat')), findsNothing);
    });

    testWidgets('the counted float is sent with the amount; an edited amount drops the breakdown', (t) async {
      when(() => repo.getLastClose(any(), any())).thenAnswer((_) async => null);
      stubOpen(() async => (success: true, session: _session(), message: null));
      final c = Get.put(ctl());
      await pump(t, const Scaffold());
      c.denominations.assignAll([(valueMinor: 500000, count: 1), (valueMinor: 10000, count: 10)]);
      c.openingCashController.text = '6000';
      await c.openRegister();
      await settle(t);
      expect(
        verify(
          () => repo.openSession(
            storeId: 'st1',
            registerId: 'r1',
            employeeId: 'emp-1',
            shiftId: 'shift-1',
            openingCash: 6000.0,
            denominations: captureAny(named: 'denominations'),
          ),
        ).captured.single,
        [
          {'valueMinor': 500000, 'count': 1},
          {'valueMinor': 10000, 'count': 10},
        ],
      );
      c.openingCashController.text = '6500';
      await c.openRegister();
      await settle(t);
      expect(
        verify(
          () => repo.openSession(storeId: 'st1', registerId: 'r1', employeeId: 'emp-1', shiftId: 'shift-1', openingCash: 6500.0, denominations: captureAny(named: 'denominations')),
        ).captured.single,
        isNull,
      );
    });

    testWidgets('DENOMINATION_MISMATCH: said in words, the count dropped, the shift not opened', (t) async {
      when(() => repo.getLastClose(any(), any())).thenAnswer((_) async => null);
      stubOpen(() async => (success: false, session: null, message: 'x'));
      when(() => repo.lastErrorCode).thenReturn('DENOMINATION_MISMATCH');
      final c = Get.put(ctl());
      await pump(t, const Scaffold());
      c.denominations.assignAll([(valueMinor: 500000, count: 1)]);
      c.openingCashController.text = '5000';
      await c.openRegister();
      await t.pump();
      expect(find.textContaining('do not add up to the float'), findsOneWidget);
      expect(c.denominations, isEmpty);
      expect(Get.currentRoute, isNot(Routes.posHome));
      await t.pump(const Duration(seconds: 4));
    });
  });

  // ── transfers ─────────────────────────────────────────────────────────────────────────────
  group('transfers', () {
    TransfersController ctl({List<StoreLocationModel>? locs}) => Get.put(
      TransfersController(repository: repo, storeId: 'st1', locations: (_) async => locs ?? [_loc('m', 'Main shop'), _loc('w', 'Warehouse')]),
      tag: 't${DateTime.now().microsecondsSinceEpoch}',
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: open transfers with what arrived; received / cancelled are filtered out of "Open"', (t) async {
        when(() => repo.getTransfers('st1', status: 'all')).thenAnswer(
          (_) async => [_transfer('t1'), _transfer('t2', status: 'partially_received', received: 4), _transfer('t3', status: 'received', received: 10)],
        );
        await pump(t, TransfersView(controller: ctl()), env);
        expect(find.byKey(const Key('transfer_t1')), findsOneWidget);
        expect(find.textContaining('4 of 10 arrived'), findsOneWidget);
        expect(find.byKey(const Key('transfer_t3')), findsNothing);
        expect(find.byKey(const Key('transferCancel_t2')), findsNothing, reason: 'part already arrived: cannot cancel');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('receive the rest: the server gets the count; a refusal is said in words', (t) async {
      when(() => repo.getTransfers('st1', status: 'all')).thenAnswer((_) async => [_transfer('t2', status: 'partially_received', received: 4)]);
      when(() => repo.receiveTransfer('st1', 't2', 6)).thenAnswer((_) async => (success: true, message: null, code: null, data: <String, dynamic>{}) as _W);
      final c = ctl();
      await pump(t, TransfersView(controller: c));
      await tapKey(t, 'transferReceive_t2');
      expect(find.byKey(const Key('receiveSheet')), findsOneWidget);
      await tapKey(t, 'receiveConfirm');
      verify(() => repo.receiveTransfer('st1', 't2', 6)).called(1);
      expect(c.notice.value, 'Received in full.');
      expect(await c.receive(_transfer('t2', status: 'partially_received', received: 4), 7), isFalse);
      expect(c.actionError.value, 'Receive between 1 and 6.');
    });

    testWidgets('cancel asks first, then sends; a refusal is said in words', (t) async {
      when(() => repo.getTransfers('st1', status: 'all')).thenAnswer((_) async => [_transfer('t1')]);
      when(() => repo.cancelTransfer('st1', 't1')).thenAnswer((_) async => (success: false, message: 'This transfer is already "received"', code: null, data: null) as _W);
      final c = ctl();
      await pump(t, TransfersView(controller: c));
      await tapKey(t, 'transferCancel_t1');
      await tapKey(t, 'transferCancelConfirm');
      verify(() => repo.cancelTransfer('st1', 't1')).called(1);
      expect(find.byKey(const Key('transferError')), findsOneWidget);
      expect(find.textContaining('already "received"'), findsOneWidget);
    });

    testWidgets('send stock: find, pick from → to, how many; the same location twice is refused here', (t) async {
      when(() => repo.getTransfers('st1', status: 'all')).thenAnswer((_) async => []);
      when(() => repo.searchProducts(storeId: 'st1', q: 'rice')).thenAnswer(
        (_) async => [
          PosProductModel(
            productId: 'p1',
            name: 'Basmati rice 5kg',
            type: 'physical',
            categoryId: '',
            variants: const [PosProductVariant(variantId: 'v1', sku: 'R-5', price: 1500, stock: 40, isDefault: true)],
          ),
        ],
      );
      when(() => repo.shipTransfer('st1', variantId: 'v1', fromLocationId: 'm', toLocationId: 'w', quantity: 5, note: any(named: 'note'))).thenAnswer(
        (_) async => (success: true, message: null, code: null, data: <String, dynamic>{}) as _W,
      );
      final c = ctl();
      await pump(t, TransfersView(controller: c));
      expect(find.byKey(const Key('transferEmpty')), findsOneWidget);
      await tapKey(t, 'transferNew');
      await t.enterText(find.byKey(const Key('shipSearch')), 'rice');
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      await tapKey(t, 'shipProduct_p1');
      await tapKey(t, 'shipFrom');
      await t.tap(find.text('Main shop').last);
      await settle(t);
      await tapKey(t, 'shipTo');
      await t.tap(find.text('Warehouse').last);
      await settle(t);
      await t.enterText(find.byKey(const Key('shipQty')), '5');
      await tapKey(t, 'shipConfirm');
      verify(() => repo.shipTransfer('st1', variantId: 'v1', fromLocationId: 'm', toLocationId: 'w', quantity: 5, note: any(named: 'note'))).called(1);
      expect(await c.ship(variantId: 'v1', fromLocationId: 'm', toLocationId: 'm', quantity: 1), isFalse);
      expect(c.actionError.value, 'Choose two different locations.');
    });

    testWidgets('one location only: the form says transfers need two; offline: needs internet, no request', (t) async {
      when(() => repo.getTransfers('st1', status: 'all')).thenAnswer((_) async => []);
      final c = ctl(locs: [_loc('m', 'Main shop')]);
      await pump(t, TransfersView(controller: c));
      await tapKey(t, 'transferNew');
      expect(find.byKey(const Key('shipNoLocations')), findsOneWidget);
      Get.reset();
      offline();
      await pump(t, TransfersView(controller: ctl()));
      expect(find.textContaining('internet'), findsWidgets);
    });
  });

  // ── expiry ────────────────────────────────────────────────────────────────────────────────
  group('expiry', () {
    ExpiryController ctl() => Get.put(ExpiryController(repository: repo, storeId: 'st1'), tag: 'e${DateTime.now().microsecondsSinceEpoch}');

    for (final env in _Env.values) {
      testWidgets('${env.name}: expired / 7 days / 30 days with value at cost', (t) async {
        when(() => repo.getExpiry('st1')).thenAnswer((_) async => _buckets());
        await pump(t, ExpiryView(controller: ctl()), env);
        expect(find.textContaining('Expired · 1 · ${Money.format(1200, currency: 'PKR', exponent: 2)} at cost'), findsOneWidget);
        expect(find.text('Expired 3 days ago'), findsOneWidget);
        expect(find.text('3 days left'), findsOneWidget);
        expect(find.textContaining('Within 30 days · 0'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a cashier sees no cost; nothing expiring says so', (t) async {
      when(() => repo.getExpiry('st1')).thenAnswer((_) async => _buckets(cost: false));
      await pump(t, ExpiryView(controller: ctl()));
      expect(find.textContaining('at cost'), findsNothing);
      Get.reset();
      when(() => repo.getExpiry('st1')).thenAnswer((_) async => _buckets(empty: true));
      await pump(t, ExpiryView(controller: ctl()));
      expect(find.byKey(const Key('expiryEmpty')), findsOneWidget);
    });

    testWidgets('write off: all of an expired lot by default; part of a lot as damaged; a refusal in words', (t) async {
      when(() => repo.getExpiry('st1')).thenAnswer((_) async => _buckets());
      when(() => repo.writeOffLot('st1', 'l1', quantity: null, reason: 'expired', note: any(named: 'note'))).thenAnswer(
        (_) async => (success: true, message: null, code: null, data: <String, dynamic>{'written': 6}) as _W,
      );
      when(() => repo.writeOffLot('st1', 'l2', quantity: 2, reason: 'damaged', note: any(named: 'note'))).thenAnswer(
        (_) async => (success: false, message: 'x', code: 'POS_ACTION_FORBIDDEN', data: null) as _W,
      );
      final c = ctl();
      await pump(t, ExpiryView(controller: c));
      await tapKey(t, 'writeOff_l1');
      expect(find.byKey(const Key('writeOffSheet')), findsOneWidget);
      await tapKey(t, 'writeOffConfirm');
      verify(() => repo.writeOffLot('st1', 'l1', quantity: null, reason: 'expired', note: any(named: 'note'))).called(1);
      expect(find.byKey(const Key('expiryNotice')), findsOneWidget);
      await tapKey(t, 'writeOff_l2');
      await t.enterText(find.byKey(const Key('writeOffQty')), '2');
      await tapKey(t, 'writeOffConfirm');
      expect(find.text('Your role cannot do this. Ask a manager.'), findsOneWidget);
    });
  });

  // ── low stock → draft PO ──────────────────────────────────────────────────────────────────
  group('draft PO', () {
    Widget host() => Builder(builder: (_) => Scaffold(body: Center(child: TextButton(key: const Key('go'), onPressed: () => DraftPoSheet.open(repository: repo, storeId: 'st1'), child: const Text('go')))));

    for (final env in [_Env.phone, _Env.dark]) {
      testWidgets('${env.name}: pick the supplier → the draft opens in the purchase order screen', (t) async {
        when(() => repo.getSuppliers('st1')).thenAnswer((_) async => SupplierList.fromJson({'suppliers': [
          {'_id': 'sup1', 'name': 'Rice traders', 'status': 'active'},
          {'_id': 'sup2', 'name': 'Old supplier', 'status': 'archived'},
        ]}));
        when(() => repo.draftPoFromLowStock('st1', 'sup1')).thenAnswer((_) async => (success: true, message: null, code: null, order: PurchaseOrder.fromJson({'_id': 'po9', 'poNumber': 'PO-0009', 'supplierId': 'sup1', 'status': 'draft', 'items': []})));
        await pump(t, host(), env);
        await tapKey(t, 'go');
        expect(find.byKey(const Key('draftPoSupplier_sup2')), findsNothing);
        await tapKey(t, 'draftPoSupplier_sup1');
        expect(find.text('PO:po9'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('nothing low for that supplier: the server\'s words; no suppliers: says so', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => SupplierList.fromJson({'suppliers': [{'_id': 'sup1', 'name': 'Rice traders', 'status': 'active'}]}));
      when(() => repo.draftPoFromLowStock('st1', 'sup1')).thenAnswer((_) async => (success: false, message: 'Nothing from Rice traders is low on stock', code: 'NOTHING_LOW', order: null));
      await pump(t, host());
      await tapKey(t, 'go');
      await tapKey(t, 'draftPoSupplier_sup1');
      expect(find.text('Nothing from Rice traders is low on stock'), findsOneWidget);
    });
  });
}
