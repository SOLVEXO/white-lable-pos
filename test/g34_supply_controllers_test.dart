// G3.4 supply controllers against a mocked PosRepository: money conversion at exponent 0 / 2 / 3, requestId stability on retry, a cashier
// never sends a cost, role-limited lists, the read-only last-synced order list, approvals and the server's error codes in plain words.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_supply_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/pay_supplier_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_return_controller.dart';

import 'support/g34_fixtures.dart';
import 'support/sale_harness.dart' show MockPosRepository;

void main() {
  late MockPosRepository repo;
  late SupplyOrdersCache cache;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = MockPosRepository();
    cache = testSupplyCache();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  Future<void> pause([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

  group('money text <-> minor units', () {
    test('exponent 2: 12.5 is 1250, 12.50 is 1250, 0.05 is 5, comma decimals work', () {
      expect(supplyMinorFromText('12.5', 2), 1250);
      expect(supplyMinorFromText('12.50', 2), 1250);
      expect(supplyMinorFromText('0.05', 2), 5);
      expect(supplyMinorFromText('12,5', 2), 1250);
      expect(supplyMinorFromText('7', 2), 700);
    });
    test('exponent 0 (JPY): whole numbers only', () {
      expect(supplyMinorFromText('500', 0), 500);
      expect(supplyMinorFromText('500.5', 0), isNull);
      expect(supplyMinorFromText('500.', 0), 500);
    });
    test('exponent 3 (KWD): three decimals', () {
      expect(supplyMinorFromText('1.234', 3), 1234);
      expect(supplyMinorFromText('1.2', 3), 1200);
      expect(supplyMinorFromText('1.2345', 3), isNull);
    });
    test('zero, junk, negatives and empty are refused (zero only when allowed)', () {
      expect(supplyMinorFromText('0', 2), isNull);
      expect(supplyMinorFromText('0', 2, allowZero: true), 0);
      expect(supplyMinorFromText('abc', 2), isNull);
      expect(supplyMinorFromText('-5', 2), isNull);
      expect(supplyMinorFromText('', 2), isNull);
    });
    test('minor to text round-trips at every exponent', () {
      for (final e in [0, 2, 3]) {
        for (final v in [0, 5, 1250, 123456]) {
          expect(supplyMinorFromText(supplyMinorToText(v, e), e, allowZero: true), v, reason: 'exp $e value $v');
        }
      }
      expect(supplyMinorToText(1250, 2), '12.50');
      expect(supplyMinorToText(1234, 3), '1.234');
      expect(supplyMinorToText(500, 0), '500');
    });
    test('request ids are unique', () => expect({for (var i = 0; i < 50; i++) newSupplyRequestId()}.length, 50));
  });

  group('PoFormController', () {
    Future<PoFormController> make({InvCur cur = usd, String? orderId}) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()], cur: cur));
      final c = PoFormController(repository: repo, storeId: 'st1', orderId: orderId, searchDebounce: const Duration(milliseconds: 5));
      c.onInit();
      await pause();
      return c;
    }

    for (final (cur, text, minor) in [(usd, '12.5', 1250), (jpy, '700', 700), (kwd, '1.234', 1234)]) {
      test('${cur.code}: cost "$text" is sent as $minor minor units and the quantity as typed', () async {
        final c = await make(cur: cur);
        c.pickSupplier(supplier());
        c.addProduct(invRow(costMinor: null));
        c.lines.single.qty.value = 4;
        c.lines.single.costText.value = text;
        Map<String, dynamic>? sent;
        when(() => repo.createSupplyOrder('st1', any())).thenAnswer((i) async {
          sent = i.positionalArguments[1] as Map<String, dynamic>;
          return (success: true, message: null, code: null, order: po(status: 'draft'));
        });
        final saved = await c.submit();
        expect(saved, isNotNull);
        expect(sent!['supplierId'], 's1');
        expect((sent!['items'] as List).single, {'variantId': 'v1', 'quantityOrdered': 4, 'unitCostMinor': minor});
        expect(sent!.containsKey('expectedAt'), isFalse);
        c.onClose();
      });
    }

    test('a cost with too many decimals blocks the save without calling the server', () async {
      final c = await make(cur: jpy);
      c.pickSupplier(supplier());
      c.addProduct(invRow(costMinor: null));
      c.lines.single.costText.value = '5.5';
      expect(await c.submit(), isNull);
      expect(c.error.value, contains('Check every line'));
      verifyNever(() => repo.createSupplyOrder(any(), any()));
      c.onClose();
    });

    test('adding the same product twice adds one to the quantity; the cost is prefilled from the store cost', () async {
      final c = await make();
      c.addProduct(invRow());
      c.addProduct(invRow());
      expect(c.lines, hasLength(1));
      expect(c.lines.single.qty.value, 2);
      expect(c.lines.single.costText.value, '2.50');
      expect(c.totalMinor, 500);
      c.onClose();
    });

    test('needs a supplier and at least one line', () async {
      final c = await make();
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Choose a supplier.');
      c.pickSupplier(supplier());
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Add at least one product.');
      c.onClose();
    });

    test('edit: loads the order into the form, sends the lines again and clears the expected date', () async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer(
        (_) async => PoDetail(
          order: po(status: 'approved'),
          cur: usd,
        ),
      );
      final c = await make(orderId: 'po1');
      expect(c.supplier.value!.id, 's1');
      expect(c.lines.single.costText.value, '2.50');
      expect(c.lines.single.qty.value, 10);
      c.expectedAt.value = null;
      Map<String, dynamic>? sent;
      when(() => repo.updateSupplyOrder('st1', 'po1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[2] as Map<String, dynamic>;
        return (success: true, message: null, code: null, order: po(status: 'draft'));
      });
      expect(await c.submit(), isNotNull);
      expect(sent!['expectedAt'], isNull);
      expect(sent!.containsKey('expectedAt'), isTrue);
      expect((sent!['items'] as List).single['unitCostMinor'], 250);
      c.onClose();
    });

    test('PO_NOT_EDITABLE from the server is shown in plain words', () async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: po(), cur: usd));
      final c = await make(orderId: 'po1');
      when(() => repo.updateSupplyOrder('st1', 'po1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'PO_NOT_EDITABLE', order: null));
      expect(await c.submit(), isNull);
      expect(c.error.value, contains('Receiving has started'));
      c.onClose();
    });
  });

  group('ReceiveController', () {
    PurchaseOrder lotOrder({bool trackLots = false}) => po(
      items: [
        poLineJson(costs: false, trackLots: trackLots),
        poLineJson(id: 'li2', variantId: 'v2', name: 'Dev Mocha', costs: false, ordered: 4),
      ],
      costs: false,
    );

    Future<ReceiveController> mountPo({String Function()? ids, bool cashier = true, PurchaseOrder? order}) async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: order ?? lotOrder(), cur: usd));
      final c = ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1', requestIdFactory: ids);
      c.onInit();
      await pause();
      return c;
    }

    test('a cashier\'s purchase-order receipt carries NO cost anywhere and addresses lines by poItemId', () async {
      final c = await mountPo();
      c.lines[0].good.value = 6;
      c.lines[0].damaged.value = 1;
      Map<String, dynamic>? sent;
      when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, result: receiveResult(costs: false));
      });
      expect(await c.submit(), isTrue);
      final line = (sent!['lines'] as List).single as Map;
      expect(line, {'poItemId': 'li1', 'qtyGood': 6, 'qtyDamaged': 1});
      expect(sent.toString().toLowerCase().contains('cost'), isFalse);
      expect(sent!['purchaseOrderId'], 'po1');
      expect(sent!['requestId'], isA<String>());
      expect(c.result.value!.receipt.receiptNumber, 'GRN-000001');
      expect(c.result.value!.receipt.totalMinor, isNull);
    });

    test('the same request again (a retry) sends the SAME requestId; a changed request or a finished one gets a new id', () async {
      var n = 0;
      final c = await mountPo(ids: () => 'rid-${++n}');
      c.lines[0].good.value = 3;
      final ids = <String>[];
      var outcome = <({bool success, String? message, String? code, ReceiveResult? result})>[
        (success: false, message: 'Could not reach the server.', code: null, result: null),
        (success: false, message: 'Could not reach the server.', code: null, result: null),
        (success: true, message: null, code: null, result: receiveResult(costs: false)),
        (success: true, message: null, code: null, result: receiveResult(costs: false)),
      ];
      var k = 0;
      when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
        ids.add((i.positionalArguments[1] as Map)['requestId'] as String);
        return outcome[k++];
      });
      expect(await c.submit(), isFalse);
      expect(await c.submit(), isFalse);
      expect(ids, ['rid-1', 'rid-1']);
      c.lines[0].good.value = 4; // the request changed
      expect(await c.submit(), isTrue);
      expect(ids.last, 'rid-2');
      // a brand-new receipt after success gets a fresh id
      c.result.value = null;
      expect(await c.submit(), isTrue);
      expect(ids.last, 'rid-3');
    });

    test('LOT_REQUIRED shows the lot fields on the lines being received and keeps the server sentence', () async {
      final c = await mountPo();
      c.lines[0].good.value = 2;
      expect(c.lines[0].showLot.value, isFalse);
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: false, message: 'Dev Latte tracks lots: enter the lot number.', code: 'LOT_REQUIRED', result: null));
      expect(await c.submit(), isFalse);
      expect(c.lines[0].showLot.value, isTrue);
      expect(c.lines[1].showLot.value, isFalse, reason: 'nothing is being received on the other line');
      expect(c.error.value, 'Dev Latte tracks lots: enter the lot number.');
      c.lines[0].lotNumber.value = ' L-77 ';
      c.lines[0].expiry.value = DateTime(2027, 3, 9);
      Map<String, dynamic>? sent;
      when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, result: receiveResult(costs: false));
      });
      expect(await c.submit(), isTrue);
      expect((sent!['lines'] as List).single, {'poItemId': 'li1', 'qtyGood': 2, 'qtyDamaged': 0, 'lotNumber': 'L-77', 'expiryDate': '2027-03-09'});
    });

    test('lot fields are shown up front when the data says the variant tracks lots', () async {
      final c = await mountPo(order: lotOrder(trackLots: true));
      expect(c.lines[0].showLot.value, isTrue);
      expect(c.lines[1].showLot.value, isFalse);
    });

    test('OVER_RECEIPT shows the server sentence (it names the product and the number left); EXCEEDS via the stepper cap', () async {
      final c = await mountPo();
      c.lines[0].good.value = 9;
      expect(c.maxFor(c.lines[0], good: false), 1);
      when(
        () => repo.receiveSupply('st1', any()),
      ).thenAnswer((_) async => (success: false, message: 'Dev Latte: only 4 more can be received on this purchase order.', code: 'OVER_RECEIPT', result: null));
      await c.submit();
      expect(c.error.value, contains('only 4 more'));
    });

    test('nothing entered: no request is made; fully received lines are not listed', () async {
      final order = po(
        costs: false,
        items: [
          poLineJson(costs: false, received: 10),
          poLineJson(id: 'li2', variantId: 'v2', costs: false),
        ],
      );
      final c = await mountPo(order: order);
      expect(c.lines, hasLength(1));
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Enter a quantity for at least one product.');
      verifyNever(() => repo.receiveSupply(any(), any()));
    });

    for (final (cur, text, minor) in [(usd, '2.5', 250), (jpy, '300', 300), (kwd, '0.125', 125)]) {
      test('direct receipt (${cur.code}): unit cost "$text" goes as $minor minor units with the supplier and variant', () async {
        when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()], cur: cur));
        final c = ReceiveController(repository: repo, storeId: 'st1', requestIdFactory: () => 'rid');
        c.onInit();
        await pause();
        c.pickSupplier(supplier());
        c.addProduct(invRow(trackLots: true, costMinor: null));
        expect(c.lines.single.showLot.value, isTrue, reason: 'the search says the product tracks lots');
        c.lines.single.costTextRx.value = text;
        c.lines.single.lotNumber.value = 'L1';
        Map<String, dynamic>? sent;
        when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
          sent = i.positionalArguments[1] as Map<String, dynamic>;
          return (success: true, message: null, code: null, result: receiveResult());
        });
        expect(await c.submit(), isTrue);
        expect(sent!['supplierId'], 's1');
        expect(sent!.containsKey('purchaseOrderId'), isFalse);
        expect((sent!['lines'] as List).single, {'variantId': 'v1', 'qtyGood': 1, 'qtyDamaged': 0, 'lotNumber': 'L1', 'unitCostMinor': minor});
      });
    }

    test('direct receipt needs a supplier and a valid cost per line', () async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()]));
      final c = ReceiveController(repository: repo, storeId: 'st1')..onInit();
      await pause();
      c.addProduct(invRow(costMinor: null));
      expect(c.canSubmit, isFalse);
      c.pickSupplier(supplier());
      expect(await c.submit(), isFalse);
      expect(c.error.value, contains('unit cost'));
      verifyNever(() => repo.receiveSupply(any(), any()));
    });

    test('COST_NOT_ALLOWED and POS_ACTION_FORBIDDEN are explained', () async {
      final c = await mountPo();
      c.lines[0].good.value = 1;
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: false, message: null, code: 'COST_NOT_ALLOWED', result: null));
      await c.submit();
      expect(c.error.value, contains('cashier receives at the purchase-order cost'));
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: false, message: null, code: 'POS_ACTION_FORBIDDEN', result: null));
      await c.submit();
      expect(c.error.value, 'Your role is not allowed to do this.');
    });

    test('offline: no request, "Needs internet"', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1')..onInit();
      await pause();
      c.lines.add(ReceiveLine(name: 'x', poItemId: 'a'));
      c.lines.single.good.value = 1;
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Needs internet.');
      verifyNever(() => repo.receiveSupply(any(), any()));
    });
  });

  group('PoListController', () {
    PoListController make({String? supplierId}) => PoListController(repository: repo, cache: cache, storeId: 'st1', supplierId: supplierId);

    test('online: loads, remembers the list, and a manager is a manager because the server sent costs', () async {
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson()]));
      final c = make()..onInit();
      await pause();
      expect(c.orders.single.hasCosts, isTrue);
      expect(c.canManage, isTrue);
      expect(c.readOnly, isFalse);
      expect((await cache.load('st1'))!.orders.single.poNumber, 'PO-000001');
      c.onClose();
    });

    test('a status chip asks the server for that status; only the "all" list is remembered', () async {
      when(() => repo.getSupplyOrders('st1', status: any(named: 'status'), supplierId: null)).thenAnswer((_) async => poList([poJson(status: 'draft')]));
      final c = make()..onInit();
      await pause();
      c.setStatus('draft');
      await pause();
      verify(() => repo.getSupplyOrders('st1', status: 'draft', supplierId: null)).called(1);
      c.onClose();
    });

    test('cashier: the server sent no money, so none is known, and the manager chips are not offered', () async {
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson(costs: false)]));
      final c = make()..onInit();
      await pause();
      expect(c.orders.single.hasCosts, isFalse);
      expect(c.orders.single.totalMinor, isNull);
      expect(c.canManage, isFalse);
      c.onClose();
    });

    test('offline: the last remembered list, read only, "as of" set; the chip filters it on the till', () async {
      await cache.save('st1', poList([poJson(), poJson(id: 'po2', number: 'PO-000002', status: 'draft')]));
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = make()..onInit();
      await pause();
      expect(c.readOnly, isTrue);
      expect(c.asOf.value, isNotNull);
      expect(c.orders, hasLength(2));
      c.setStatus('draft');
      expect(c.visible.map((o) => o.poNumber), ['PO-000002']);
      verifyNever(
        () => repo.getSupplyOrders(
          any(),
          status: any(named: 'status'),
          supplierId: any(named: 'supplierId'),
        ),
      );
      c.onClose();
    });

    test('offline with nothing remembered: needs internet; a cashier copy stays money-free', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = make()..onInit();
      await pause();
      expect(c.needsInternet.value, isTrue);
      expect(c.orders, isEmpty);
      await cache.save('st1', poList([poJson(costs: false)]));
      await c.load();
      expect(c.needsInternet.value, isFalse);
      expect(c.orders.single.hasCosts, isFalse);
      c.onClose();
    });

    test('the offline copy is sealed at rest, per store, and a corrupt blob reads as nothing', () async {
      await cache.save('st1', poList([poJson()]));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pos_supply_orders_cache')!.contains('Dev Supplies'), isFalse);
      expect(await cache.load('st2'), isNull);
      SharedPreferences.setMockInitialValues({'pos_supply_orders_cache': 'garbage'});
      expect(await cache.load('st1'), isNull);
    });

    test('a server error with a code (not offline) is an error, not the remembered list', () async {
      await cache.save('st1', poList([poJson()]));
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = make()..onInit();
      await pause();
      expect(c.error.value, 'Your role is not allowed to do this.');
      expect(c.readOnly, isFalse);
      c.onClose();
    });
  });

  group('PoDetailController', () {
    Future<PoDetailController> make(PurchaseOrder o, {Future<String?> Function({required String reason, dynamic repository})? approval, bool manager = true}) async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: o, cur: usd));
      final c = PoDetailController(
        orderId: 'po1',
        repository: repo,
        storeId: 'st1',
        approval: approval == null ? null : ({required String reason, repository}) => approval(reason: reason, repository: repository),
      );
      c.onInit();
      await pause();
      return c;
    }

    test('actions follow the status: draft / approved / sent / partial / received / cancelled', () async {
      Future<List<bool>> flags(String status, {bool editable = true}) async {
        final c = await make(po(status: status, editable: editable));
        return [c.canApprove, c.canSend, c.canEdit, c.canCancel, c.canCloseShort, c.canReceive];
      }

      expect(await flags('draft'), [true, false, true, true, false, false]);
      expect(await flags('approved'), [false, true, true, true, false, true]);
      expect(await flags('sent'), [false, false, true, true, false, true]);
      expect(await flags('partially_received', editable: false), [false, false, false, false, true, true]);
      expect(await flags('received', editable: false), [false, false, false, false, false, false]);
      expect(await flags('cancelled', editable: false), [false, false, false, false, false, false]);
    });

    test('an order with received units cannot be edited or cancelled from the till', () async {
      final c = await make(po(items: [poLineJson(received: 2)]));
      expect(c.canEdit, isFalse);
      expect(c.canCancel, isFalse);
    });

    test('a cashier (no costs from the server) sees Receive only', () async {
      final c = await make(po(costs: false));
      expect(c.canManage, isFalse);
      expect([c.canApprove, c.canSend, c.canEdit, c.canCancel, c.canCloseShort], everyElement(isFalse));
      expect(c.canReceive, isTrue);
    });

    test('approve updates the order from the answer', () async {
      final c = await make(po(status: 'draft'));
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: true, message: null, code: null, order: po(status: 'approved')));
      expect(await c.run('approve'), isTrue);
      expect(c.order!.status, 'approved');
      expect(c.notice.value, 'Purchase order approved.');
    });

    test('POS_OWNER_REQUIRED on approve is a clear message', () async {
      final c = await make(po(status: 'draft'));
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED', order: null));
      expect(await c.run('approve'), isFalse);
      expect(c.actionError.value, contains('store owner must do this'));
      expect(c.order!.status, 'draft');
    });

    test('POS_APPROVAL_REQUIRED asks a manager PIN once and repeats the action with that token', () async {
      String? asked;
      final c = await make(
        po(status: 'draft'),
        approval: ({required reason, repository}) async {
          asked = reason;
          return 'tok-mgr';
        },
      );
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', order: null));
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve', approverToken: 'tok-mgr')).thenAnswer((_) async => (success: true, message: null, code: null, order: po(status: 'approved')));
      expect(await c.run('approve'), isTrue);
      expect(asked, contains('approval'));
    });

    test('a cancelled approval sheet leaves the order alone with the approval message', () async {
      final c = await make(po(status: 'draft'), approval: ({required reason, repository}) async => null);
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', order: null));
      expect(await c.run('approve'), isFalse);
      expect(c.actionError.value, 'A manager must approve this.');
      verifyNever(
        () => repo.supplyOrderAction(
          'st1',
          'po1',
          'approve',
          approverToken: any(named: 'approverToken', that: isNotNull),
        ),
      );
    });

    test('double tap: only one request is in flight', () async {
      final c = await make(po(status: 'approved'));
      when(() => repo.supplyOrderAction('st1', 'po1', 'send')).thenAnswer((_) async {
        await pause(30);
        return (success: true, message: null, code: null, order: po(status: 'sent'));
      });
      final a = c.run('send');
      final b = c.run('send');
      expect(await b, isFalse);
      expect(await a, isTrue);
      verify(() => repo.supplyOrderAction('st1', 'po1', 'send')).called(1);
    });

    test('PO_NOT_PARTIAL / PO_NOT_CANCELLABLE are explained', () async {
      final c = await make(po(status: 'partially_received', editable: false));
      when(() => repo.supplyOrderAction('st1', 'po1', 'cancel')).thenAnswer((_) async => (success: false, message: null, code: 'PO_NOT_CANCELLABLE', order: null));
      await c.run('cancel');
      expect(c.actionError.value, contains('Close the order short'));
    });
  });

  group('PaySupplierController', () {
    PaySupplierController make({
      String? session = 'sess1',
      int exponent = 2,
      int? balance = 5000,
      String Function()? ids,
      Future<String?> Function({required String reason, dynamic repository})? approval,
    }) => PaySupplierController(
      supplierId: 's1',
      exponent: exponent,
      balanceMinor: balance,
      repository: repo,
      storeId: 'st1',
      sessionIdProvider: () async => session,
      requestIdFactory: ids,
      approval: approval == null ? null : ({required String reason, repository}) => approval(reason: reason, repository: repository),
    );

    SupplierPaymentResult paid([int amount = 1000]) => SupplierPaymentResult(amountMinor: amount, method: 'bank', balanceMinor: 4000, cur: usd);

    test('with an open shift cash is allowed (and the default); the session id is sent for cash', () async {
      final c = make()..onInit();
      await pause();
      expect(c.canPayCash, isTrue);
      expect(c.method.value, 'cash');
      c.amountText.value = '12.5';
      when(
        () => repo.paySupplier(
          'st1',
          's1',
          amountMinor: 1250,
          method: 'cash',
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: 'sess1',
          approverToken: null,
        ),
      ).thenAnswer((_) async => (success: true, message: null, code: null, result: paid(1250)));
      expect(await c.submit(), isTrue);
      expect(c.result.value!.balanceMinor, 4000);
    });

    test('no open shift: cash is disabled with the plain reason, bank still works and sends no session', () async {
      final c = make(session: null)..onInit();
      await pause();
      expect(c.canPayCash, isFalse);
      expect(c.method.value, 'bank');
      c.amountText.value = '10';
      c.pickMethod('cash');
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Paying cash from the drawer needs an open shift.');
      verifyNever(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      );
      c.pickMethod('bank');
      when(
        () => repo.paySupplier(
          'st1',
          's1',
          amountMinor: 1000,
          method: 'bank',
          requestId: any(named: 'requestId'),
          reference: 'TT-1',
          sessionId: null,
          approverToken: null,
        ),
      ).thenAnswer((_) async => (success: true, message: null, code: null, result: paid()));
      c.reference.value = 'TT-1';
      expect(await c.submit(), isTrue);
    });

    for (final (exp, text, minor) in [(0, '1500', 1500), (2, '15.75', 1575), (3, '1.005', 1005)]) {
      test('exponent $exp: "$text" is sent as $minor', () async {
        final c = make(session: null, exponent: exp)..onInit();
        await pause();
        c.amountText.value = text;
        when(
          () => repo.paySupplier(
            'st1',
            's1',
            amountMinor: minor,
            method: 'bank',
            requestId: any(named: 'requestId'),
            reference: any(named: 'reference'),
            sessionId: any(named: 'sessionId'),
            approverToken: any(named: 'approverToken'),
          ),
        ).thenAnswer((_) async => (success: true, message: null, code: null, result: paid(minor)));
        expect(await c.submit(), isTrue);
      });
    }

    test('requestId: a retry of the same payment keeps its id, a different amount gets a new one', () async {
      var n = 0;
      final c = make(session: null, ids: () => 'pay-${++n}')..onInit();
      await pause();
      c.amountText.value = '10';
      final ids = <String>[];
      var k = 0;
      final outcomes = [
        (success: false, message: 'Could not reach the server.', code: null, result: null as SupplierPaymentResult?),
        (success: true, message: null, code: null, result: paid() as SupplierPaymentResult?),
        (success: true, message: null, code: null, result: paid(2000) as SupplierPaymentResult?),
      ];
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        ids.add(i.namedArguments[#requestId] as String);
        return outcomes[k++];
      });
      expect(await c.submit(), isFalse);
      expect(await c.submit(), isTrue);
      expect(ids, ['pay-1', 'pay-1']);
      c.amountText.value = '20';
      expect(await c.submit(), isTrue);
      expect(ids.last, 'pay-2');
    });

    test('EXCEEDS_BALANCE and POS_OWNER_REQUIRED are explained in plain words', () async {
      final c = make(session: null)..onInit();
      await pause();
      c.amountText.value = '900';
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'EXCEEDS_BALANCE', result: null));
      await c.submit();
      expect(c.error.value, 'That is more than is owed to this supplier.');
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED', result: null));
      await c.submit();
      expect(c.error.value, contains('store owner must do this'));
    });

    test('POS_APPROVAL_REQUIRED asks a manager PIN and repeats with the SAME requestId and the token', () async {
      final seen = <(String, String?)>[];
      final c = make(session: null, ids: () => 'pay-x', approval: ({required reason, repository}) async => 'tok')..onInit();
      await pause();
      c.amountText.value = '50';
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        seen.add((i.namedArguments[#requestId] as String, i.namedArguments[#approverToken] as String?));
        return seen.length == 1 ? (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', result: null) : (success: true, message: null, code: null, result: paid(5000));
      });
      expect(await c.submit(), isTrue);
      expect(seen, [('pay-x', null), ('pay-x', 'tok')]);
    });

    test('amount must be a positive number within the currency decimals; offline refuses', () async {
      final c = make(session: null, exponent: 0)..onInit();
      await pause();
      c.amountText.value = '5.5';
      expect(c.canSubmit, isFalse);
      c.amountText.value = '5';
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Needs internet.');
    });

    test('full balance text', () => expect(make(balance: 12345).fullBalanceText, '123.45'));
    test('no full balance when nothing is owed', () => expect(make(balance: 0).fullBalanceText, isNull));
  });

  group('SupplierReturnController', () {
    test('sends the receipt, only the lines with a quantity, the lot and fromDamaged, one requestId per request', () async {
      final c = SupplierReturnController(
        receipt: receipt(lot: 'L9'),
        repository: repo,
        storeId: 'st1',
        requestIdFactory: () => 'ret-1',
      )..onInit();
      expect(c.lines.single.max, 10);
      expect(c.canSubmit, isFalse);
      c.lines.single.qty.value = 3;
      c.lines.single.fromDamaged.value = true;
      c.reason.value = 'damaged';
      Map<String, dynamic>? sent;
      when(() => repo.createSupplierReturn('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, result: SupplierReturnResult(id: 'x', returnNumber: 'SR-1', supplierName: 'Dev Supplies', reason: 'damaged', creditMinor: 750, cur: usd));
      });
      expect(await c.submit(), isTrue);
      expect(sent, {
        'receiptId': 'r1',
        'reason': 'damaged',
        'items': [
          {'variantId': 'v1', 'quantity': 3, 'lotId': 'lot1', 'fromDamaged': true},
        ],
        'requestId': 'ret-1',
      });
      expect(c.result.value!.creditMinor, 750);
    });

    test('from a supplier it lists the receipts first, then a pick shows the lines', () async {
      when(() => repo.getSupplyReceipts('st1', supplierId: 's1')).thenAnswer((_) async => [receipt()]);
      final c = SupplierReturnController(supplierId: 's1', repository: repo, storeId: 'st1')..onInit();
      await pause();
      expect(c.receipts, hasLength(1));
      expect(c.picked.value, isNull);
      c.pick(c.receipts.single);
      expect(c.lines, hasLength(1));
    });

    test('EXCEEDS_RECEIPT is explained', () async {
      final c = SupplierReturnController(receipt: receipt(), repository: repo, storeId: 'st1')..onInit();
      c.lines.single.qty.value = 3;
      when(() => repo.createSupplierReturn('st1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'EXCEEDS_RECEIPT', result: null));
      await c.submit();
      expect(c.error.value, contains('left of this receipt'));
    });
  });

  group('SupplierFormController', () {
    test('create sends only filled fields; the name is required', () async {
      final c = SupplierFormController(repository: repo, storeId: 'st1');
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Enter the supplier\'s name.');
      c.name.value = ' Acme ';
      c.ntn.value = '123-4';
      c.leadTimeDays.value = '5';
      Map<String, dynamic>? sent;
      when(() => repo.createSupplier('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, supplier: supplier(name: 'Acme'));
      });
      expect((await c.submit())!.name, 'Acme');
      expect(sent, {'name': 'Acme', 'ntn': '123-4', 'leadTimeDays': 5});
    });

    test('edit sends emptied fields empty so the server clears them; POS_ACTION_FORBIDDEN is explained', () async {
      final c = SupplierFormController(existing: supplier(), repository: repo, storeId: 'st1');
      c.phone.value = '';
      expect(c.fields['phone'], '');
      expect(c.fields['name'], 'Dev Supplies');
      when(() => repo.updateSupplier('st1', 's1', any())).thenAnswer((_) async => (success: false, message: null, code: 'POS_ACTION_FORBIDDEN', supplier: null));
      expect(await c.submit(), isNull);
      expect(c.error.value, 'Your role is not allowed to do this.');
    });
  });

  group('models', () {
    test('a cashier\'s order has no money and a manager\'s has; the currency is the response\'s own', () {
      expect(po(costs: false).totalMinor, isNull);
      expect(po(costs: false).items.single.unitCostMinor, isNull);
      expect(po().totalMinor, 2650);
      expect(po().cur, usd);
      expect(PurchaseOrder.fromJson({...poJson(), 'currency': null, 'currencyExponent': null}).cur, isNull);
    });
    test('list rows take the list\'s currency when the row does not state one', () {
      final l = PoList.fromJson({
        'currency': 'JPY',
        'currencyExponent': 0,
        'orders': [
          {...poJson(), 'currency': null, 'currencyExponent': null},
        ],
      });
      expect(l.orders.single.cur, jpy);
    });
    test('a PO line states trackLots; a line without the field is not lot-tracked', () {
      expect(PoLine.fromJson(poLineJson(trackLots: true)).trackLots, isTrue);
      expect(PoLine.fromJson(poLineJson()).trackLots, isFalse);
      expect(PoLine.fromJson({...poLineJson()}..remove('trackLots')).trackLots, isFalse);
    });
    test('error codes', () {
      for (final code in [
        'OVER_RECEIPT',
        'LOT_REQUIRED',
        'PO_NOT_EDITABLE',
        'EXCEEDS_BALANCE',
        'NO_OPEN_SHIFT',
        'EXCEEDS_RECEIPT',
        'POS_OWNER_REQUIRED',
        'POS_APPROVAL_REQUIRED',
        'POS_ACTION_FORBIDDEN',
        'COST_NOT_ALLOWED',
      ]) {
        expect(supplyErrorMessage(code), isNot(contains('Something went wrong')), reason: code);
      }
      expect(supplyErrorMessage('WHAT', fallback: 'server said'), 'server said');
    });
  });
}
