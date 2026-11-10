// REAL end-to-end for G3.4 Supply on the iOS simulator against the dev stack (real repositories, real API):
//   manager creates a supplier + a purchase order (DEV-YOGURT, lot-tracked) → approves → sends
//   a CASHIER sees the PO without any cost and receives part of it WITH a lot (and cannot send a cost or exceed the order)
//   the manager receives the rest into a second lot → PO received, the supplier is billed → a sale takes the EARLIEST-expiry lot first (FEFO)
//   supplier return from the receipt (right lot, credit) → pay part of the bill in CASH from the drawer → the shift report shows the cash-out, expected cash dropped
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g34_supply_flow_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    SoundUtil.enabled = false;
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'g34 supply probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  testWidgets('G3.4 supply: PO → approve → cashier partial receive with lot → rest → FEFO sale → supplier return → pay cash from the drawer', (tester) async {
    var t = await till(managerEmail, managerPin);
    final yogurt = (await t.variantsBySku())['DEV-YOGURT']!;
    final vid = yogurt.variantId;
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final lotA = 'G34A-$stamp', lotB = 'G34B-$stamp';

    // ── a · supplier + purchase order (manager) ──────────────────────────────────────────────────────────────────────────────
    final made = await t.repo.createSupplier(storeId, {'name': 'G34 Dairy $stamp', 'ntn': '1234567-8', 'paymentTerms': 'Net 30'});
    expect(made.success, isTrue, reason: 'supplier: ${made.message}');
    final supplier = made.supplier!;
    final po = await t.repo.createSupplyOrder(storeId, {
      'supplierId': supplier.id,
      'items': [
        {'variantId': vid, 'quantityOrdered': 10, 'unitCostMinor': 200},
      ],
    });
    expect(po.success, isTrue, reason: 'po: ${po.message}');
    expect(po.order!.status, PoStatus.draft);
    expect(po.order!.totalMinor, 2000);
    final approved = await t.repo.supplyOrderAction(storeId, po.order!.id, 'approve');
    expect(approved.success, isTrue, reason: 'approve: ${approved.message}');
    expect(approved.order!.status, PoStatus.approved);
    final sent = await t.repo.supplyOrderAction(storeId, po.order!.id, 'send');
    expect(sent.order!.status, PoStatus.sent);
    final poId = po.order!.id;
    final lineId = sent.order!.items.single.id;
    print('a ok: supplier ${supplier.id}, ${sent.order!.poNumber} sent');
    await t.dispose();

    // ── b · a cashier receives part of it, with a lot; sees no cost ──────────────────────────────────────────────────────────
    t = await till(cashierEmail, cashierPin);
    final list = await t.repo.getSupplyOrders(storeId);
    final seen = list!.orders.firstWhere((o) => o.id == poId);
    expect(seen.hasCosts, isFalse, reason: 'a cashier gets no costs');
    expect(seen.items.single.unitCostMinor, isNull);
    final sneaky = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': newSupplyRequestId(),
      'lines': [
        {'poItemId': lineId, 'qtyGood': 1, 'unitCostMinor': 1, 'lotNumber': 'X'},
      ],
    });
    expect(sneaky.success, isFalse);
    expect(sneaky.code, 'COST_NOT_ALLOWED');
    final noLot = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': newSupplyRequestId(),
      'lines': [
        {'poItemId': lineId, 'qtyGood': 6},
      ],
    });
    expect(noLot.code, 'LOT_REQUIRED', reason: 'a lot-tracked product needs its lot number');
    final stockBefore = await t.stockOf('DEV-YOGURT');
    final req1 = newSupplyRequestId();
    final partial = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': req1,
      'lines': [
        {'poItemId': lineId, 'qtyGood': 6, 'lotNumber': lotA, 'expiryDate': DateTime.now().add(const Duration(days: 2)).toIso8601String()},
      ],
    });
    expect(partial.success, isTrue, reason: 'partial: ${partial.message}');
    expect(partial.result!.order!.status, PoStatus.partiallyReceived);
    expect(partial.result!.receipt.totalMinor, isNull, reason: 'the cashier sees no money on the receipt');
    final again = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': req1,
      'lines': [
        {'poItemId': lineId, 'qtyGood': 6, 'lotNumber': lotA},
      ],
    });
    expect(again.result!.duplicate, isTrue, reason: 'a retried submit is not applied twice');
    expect(await t.stockOf('DEV-YOGURT'), stockBefore + 6);
    final over = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': newSupplyRequestId(),
      'lines': [
        {'poItemId': lineId, 'qtyGood': 5, 'lotNumber': 'OVER'},
      ],
    });
    expect(over.code, 'OVER_RECEIPT');
    expect(await t.stockOf('DEV-YOGURT'), stockBefore + 6, reason: 'the refused receipt changed nothing');
    final payAttempt = await t.repo.getPayables(storeId);
    expect(payAttempt, isNull, reason: 'a cashier cannot read payables');
    print('b ok: cashier received 6 into $lotA, no cost visible, over-receipt refused');
    await t.dispose();

    // ── c · the manager receives the rest into a second lot ───────────────────────────────────────────────────────────────────
    t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final rest = await t.repo.receiveSupply(storeId, {
      'purchaseOrderId': poId,
      'requestId': newSupplyRequestId(),
      'supplierInvoiceNumber': 'INV-$stamp',
      'lines': [
        {'poItemId': lineId, 'qtyGood': 3, 'qtyDamaged': 1, 'lotNumber': lotB, 'expiryDate': DateTime.now().add(const Duration(days: 40)).toIso8601String()},
      ],
    });
    expect(rest.success, isTrue, reason: 'rest: ${rest.message}');
    expect(rest.result!.order!.status, PoStatus.received);
    final ledger0 = await t.repo.getSupplierLedger(storeId, supplier.id);
    expect(ledger0!.aging.balanceMinor, 2000, reason: '10 units × 2.00 billed (the damaged one is credited back by a return)');
    print('c ok: PO received, supplier owed ${ledger0.aging.balanceMinor} minor');

    // ── d · FEFO: a sale takes the earliest expiry (lot A, 2 days) first ──────────────────────────────────────────────────────
    final productId = (await t.productIdBySku())['DEV-YOGURT']!;
    final sale = await t.repo.createSale(
      storeId: storeId,
      sessionId: session.id,
      registerId: registerId,
      employeeId: t.employee!.id,
      items: [
        {'productId': productId, 'variantId': vid, 'qty': 4},
      ],
      paymentMethod: 'card',
      status: 'completed',
    );
    expect(sale.success, isTrue, reason: 'sale: ${sale.message}');
    final lots = sale.sale!.items.single.lots.map((l) => '${l.lotNumber}x${l.qty}').toList();
    final soldFromA = sale.sale!.items.single.lots.where((l) => l.lotNumber == lotA).fold<int>(0, (s, l) => s + l.qty.toInt()); // an older run's lot may expire a little earlier and go first
    expect(lots.first, startsWith('G34A-'), reason: 'earliest expiry first: $lots');
    final detail = (await t.repo.getInventoryVariant(storeId, vid))!;
    expect({for (final l in detail.lots) l.lotNumber: l.remaining}[lotA], 6 - soldFromA, reason: '6 received − what the sale took from it');
    print('d ok: sold from ${lots.join(' + ')}');

    // ── e · supplier return from the receipt: the right lot, a credit ────────────────────────────────────────────────────────
    final receiptId = rest.result!.receipt.id;
    final firstReceipts = await t.repo.getSupplyReceipts(storeId, purchaseOrderId: poId);
    final firstReceipt = firstReceipts!.firstWhere((r) => r.id != receiptId);
    final lotAId = firstReceipt.lines.single.lotId!;
    final ret = await t.repo.createSupplierReturn(storeId, {
      'receiptId': firstReceipt.id,
      'requestId': newSupplyRequestId(),
      'reason': 'defective',
      'items': [
        {'variantId': vid, 'quantity': 1, 'lotId': lotAId},
      ],
    });
    expect(ret.success, isTrue, reason: 'return: ${ret.message}');
    expect(ret.result!.creditMinor, 200);
    final detail2 = (await t.repo.getInventoryVariant(storeId, vid))!;
    expect({for (final l in detail2.lots) l.lotNumber: l.remaining}[lotA], 6 - soldFromA - 1, reason: 'the return took the unit out of lot A');
    final ledger1 = await t.repo.getSupplierLedger(storeId, supplier.id);
    expect(ledger1!.aging.balanceMinor, 1800);
    print('e ok: returned 1 from $lotA, credit ${ret.result!.creditMinor}');

    // ── f · pay part of the bill in cash from the drawer → the shift shows the cash-out ──────────────────────────────────────
    final reportBefore = (await t.repo.getSessionReport(session.id))!;
    final over2 = await t.repo.paySupplier(storeId, supplier.id, amountMinor: 1801, method: 'cash', requestId: newSupplyRequestId(), sessionId: session.id);
    expect(over2.code, 'EXCEEDS_BALANCE');
    final payId = newSupplyRequestId();
    final paid = await t.repo.paySupplier(storeId, supplier.id, amountMinor: 500, method: 'cash', requestId: payId, reference: 'cash-$stamp', sessionId: session.id);
    expect(paid.success, isTrue, reason: 'pay: ${paid.message}');
    expect(paid.result!.balanceMinor, 1300);
    final retry = await t.repo.paySupplier(storeId, supplier.id, amountMinor: 500, method: 'cash', requestId: payId, reference: 'cash-$stamp', sessionId: session.id);
    expect(retry.result!.duplicate, isTrue);
    final reportAfter = (await t.repo.getSessionReport(session.id))!;
    expect(reportAfter.cashFlow.cashOut, closeTo(reportBefore.cashFlow.cashOut + 5.0, 0.001), reason: 'the 5.00 left the drawer');
    // expected cash is computed at close: opening 100.00 + cash sales 0 (the sale was card) − the 5.00 supplier payment
    final closed = await t.repo.closeSession(sessionId: session.id, closingCash: 95.0);
    expect(closed.success, isTrue, reason: 'close: ${closed.message}');
    expect(closed.session!.expectedCash, closeTo(95.0, 0.001), reason: 'expected cash is lower by exactly the payment');
    print('f ok: paid 5.00 cash; shift cash-out ${reportAfter.cashFlow.cashOut}, expected ${closed.session!.expectedCash}');
    await t.dispose();
  });
}
