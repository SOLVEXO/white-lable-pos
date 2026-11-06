// G2.5 on the till: the return maths (same as the server), the return flow (restock, receipt, manager approval, open shift, double submit),
// the tax invoice and credit note screens, the document PDFs, the held sale's coupon code, offline-ref in the queued payload.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/tax_invoice_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_complete_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/return_math.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';

import 'support/sale_harness.dart';

PosSaleModel invoiceSale({String status = 'completed', int refunded = 0, bool withInvoice = true, List<PosPaymentLine>? payments, bool extraLine = false}) => PosSaleModel.fromJson({
      '_id': 'sale-1',
      'saleNumber': 'POS-00007',
      'storeId': 'store-1',
      'sessionId': 's',
      'registerId': 'r',
      'employeeId': 'e',
      'status': status,
      'currency': 'USD',
      'currencyExponent': 2,
      'subtotal': 30.0,
      'discount': 3.0,
      'tax': 2.7,
      'total': 29.7,
      'paymentMethod': 'cash',
      'customerName': 'Walk-in',
      'createdAt': '2026-11-06T10:00:00.000Z',
      if (withInvoice) 'invoice': {'number': 'INV-000007', 'issuedAt': '2026-11-06T10:00:00.000Z', 'seller': {'legalName': 'Test Traders Ltd', 'address': '12 Mall Road', 'ntn': '1234567-8', 'strn': '3277876'}},
      'items': [
        {'_id': 'i1', 'productId': 'p1', 'variantId': 'v1', 'name': 'Tea', 'sku': 'TEA', 'qty': 3, 'price': 10.0, 'lineTotal': 30.0, 'refundedQty': refunded, 'netMinor': 2700, 'taxMinor': 270, 'hsCode': '09024090'},
        if (extraLine) {'_id': 'i2', 'productId': 'p2', 'variantId': 'v2', 'name': 'Coffee', 'sku': 'COF', 'qty': 1, 'price': 5.0, 'lineTotal': 5.0, 'refundedQty': 0, 'netMinor': 450, 'taxMinor': 45},
      ],
      'payments': [
        for (final p in payments ?? [const PosPaymentLine(method: 'cash', amount: 29.7)]) {'method': p.method, 'amount': p.amount},
      ],
    });

PosCreditNote note({String number = 'CN-000001', int total = 990, bool restock = true}) => PosCreditNote.fromJson({
      '_id': 'cn1',
      'number': number,
      'invoiceNumber': 'INV-000007',
      'kind': 'return',
      'scope': 'partial',
      'reasonCode': 'wrong_item',
      'reason': 'size',
      'currency': 'USD',
      'currencyExponent': 2,
      'netMinor': 900,
      'taxMinor': 90,
      'totalMinor': total,
      'createdAt': '2026-11-06T11:00:00.000Z',
      'approvedBy': 'm1',
      'approvalReasons': ['no_original_receipt'],
      'seller': {'legalName': 'Test Traders Ltd', 'ntn': '1234567-8'},
      'tenders': [
        {'method': 'cash', 'amountMinor': total}
      ],
      'lines': [
        {'name': 'Tea', 'sku': 'TEA', 'hsCode': '09024090', 'qty': 1, 'netMinor': 900, 'taxMinor': 90, 'totalMinor': total, 'restock': restock, 'restockReason': restock ? null : 'spilled'}
      ],
    });

PosEmployeeModel manager() => PosEmployeeModel(id: 'm1', storeId: 'store-1', sellerId: 's', name: 'Mia', email: 'mia@x.pk', role: 'manager', shiftIds: const [], status: 'active', createdAt: DateTime(2026));

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  SaleHarness.setUpAllShared();
  setUp(() => SharedPreferences.setMockInitialValues({'store_id': 'store-1'}));
  tearDown(() {
    Get.reset();
    ReasonPicker.testOverride = null;
  });

  group('return maths (the server\'s proration, in integer minor units)', () {
    test('cumulative share ends exactly at the total and is monotone', () {
      var prev = 0;
      for (var n = 0; n <= 7; n++) {
        final s = cumulativeShare(1001, 7, n);
        expect(s, greaterThanOrEqualTo(prev));
        prev = s;
      }
      expect(cumulativeShare(1001, 7, 7), 1001);
    });
    test('returning a line one unit at a time credits exactly what it cost (net and tax separately)', () {
      const line = LineAmounts(2701, 458);
      var net = 0, tax = 0;
      for (var r = 0; r < 3; r++) {
        final c = returnCredit(line, 3, r, 1);
        net += c.netMinor;
        tax += c.taxMinor;
      }
      expect([net, tax], [2701, 458]);
    });
    test('the same figures as the server\'s tests: 3 × 10.00, 10% off, 10% tax → 2700 + 270; one unit credits 900 + 90', () {
      final c = returnCredit(const LineAmounts(2700, 270), 3, 0, 1);
      expect([c.netMinor, c.taxMinor, c.totalMinor], [900, 90, 990]);
    });
    test('a chunk of 2 then 1 equals 3 singles', () {
      const line = LineAmounts(2701, 458);
      final a = returnCredit(line, 3, 0, 2), b = returnCredit(line, 3, 2, 1);
      expect(a.totalMinor + b.totalMinor, line.totalMinor);
    });
  });

  group('documents: models and PDFs', () {
    test('a sale carries its invoice (number, date, seller as registered) and its lines their tax + HS code', () {
      final s = invoiceSale();
      expect(s.invoice!.number, 'INV-000007');
      expect([s.invoice!.sellerName, s.invoice!.sellerNtn, s.invoice!.sellerStrn], ['Test Traders Ltd', '1234567-8', '3277876']);
      expect([s.items.first.netMinor, s.items.first.taxMinor, s.items.first.hsCode], [2700, 270, '09024090']);
      expect(invoiceSale(withInvoice: false).invoice, isNull);
    });
    test('a held sale remembers its coupon code', () {
      expect(PosSaleModel.fromJson({'_id': 'h', 'status': 'held', 'heldCouponCode': 'SAVE10', 'items': []}).heldCouponCode, 'SAVE10');
    });
    test('a credit note parses lines, tenders, approval and the seller snapshot', () {
      final n = note();
      expect([n.number, n.invoiceNumber, n.totalMinor, n.lines.single.restock, n.tenders.single.method, n.approvalReasons, n.sellerNtn], ['CN-000001', 'INV-000007', 990, true, 'cash', ['no_original_receipt'], '1234567-8']);
    });
    test('the invoice and credit-note PDFs render (non-empty, PDF header), with or without an invoice number', () async {
      for (final bytes in [await TaxDocumentPdf.invoice(sale: invoiceSale()), await TaxDocumentPdf.invoice(sale: invoiceSale(withInvoice: false), storeName: 'Shop'), await TaxDocumentPdf.creditNote(note: note())]) {
        expect(bytes.length, greaterThan(500));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });

  group('return flow (controller)', () {
    late MockPosRepository repo;
    setUp(() {
      repo = MockPosRepository();
      ReasonPicker.testOverride = (_) async => const PosReasonChoice('wrong_item', 'size');
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.lastErrorReasons).thenReturn(const []);
      when(() => repo.lastCreditNote).thenReturn({'id': 'cn1', 'number': 'CN-000001', 'totalMinor': 990});
    });

    PosReturnController make({PosSaleModel? sale}) {
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale ?? invoiceSale());
      final c = PosReturnController(repository: repo, saleId: 'sale-1');
      Get.put(c);
      return c;
    }

    void stubRefund(Future<({bool success, double? refundedAmount, String? newStatus, String? message, List<PosPaymentLine> tenders})> Function(Invocation) f) {
      when(() => repo.refundSale(any(), items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).thenAnswer(f);
    }

    const ok = (success: true, refundedAmount: 9.9, newStatus: 'partially_refunded', message: null, tenders: <PosPaymentLine>[PosPaymentLine(method: 'cash', amount: 9.9)]);

    test('picking a quantity shows the credit the server will give (its own net + tax proration) and how it is paid back', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      expect(c.estimateMinor, 990);
      expect(c.plan().single, contains('9.90'));
      c.setQty('i1', 99); // clamped to what is left
      expect(c.qty['i1'], 3);
      c.setQty('i1', 0);
      expect(c.hasSelection, isFalse);
      expect(c.estimateMinor, isNull);
    });

    test('units already returned come off the maximum, and the next credit is the cumulative difference', () async {
      final c = make(sale: invoiceSale(status: 'partially_refunded', refunded: 2));
      await c.load();
      c.setQty('i1', 5);
      expect(c.qty['i1'], 1);
      expect(c.estimateMinor, 990); // the last unit: what is left of the line
    });

    test('a line NOT going back on the shelf needs a reason before it can be sent', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      c.setRestock('i1', false);
      expect(c.restockReasonsComplete, isFalse);
      expect(await c.confirm(), isFalse);
      expect(c.error.value, contains('not restocked'));
      c.restockReason['i1'] = 'spilled';
      expect(c.restockReasonsComplete, isTrue);
    });

    test('confirm sends the lines, restock flag + reason, receipt flag and the picked reason; the credit note comes back', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      c.setRestock('i1', false);
      c.restockReason['i1'] = 'spilled';
      c.receiptPresented.value = true;
      stubRefund((_) async => ok);
      expect(await c.confirm(), isTrue);
      final call = verify(() => repo.refundSale('sale-1', items: captureAny(named: 'items'), reasonCode: 'wrong_item', reason: 'size', receiptPresented: captureAny(named: 'receiptPresented'), approverToken: captureAny(named: 'approverToken'))).captured;
      expect(call[0], [
        {'saleItemId': 'i1', 'qty': 1, 'restock': false, 'restockReason': 'spilled'}
      ]);
      expect(call[1], isNull); // receipt presented: not sent
      expect(call[2], isNull);
      expect(c.result.value!['number'], 'CN-000001');
      expect(c.resultAmount, 9.9);
      expect(c.resultInstructions.single, contains('9.90'));
    });

    test('no original receipt is sent as receiptPresented:false', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      c.receiptPresented.value = false;
      stubRefund((_) async => ok);
      await c.confirm();
      verify(() => repo.refundSale('sale-1', items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: false, approverToken: any(named: 'approverToken'))).called(1);
    });

    test('"Return everything" sends no item list', () async {
      final c = make();
      await c.load();
      stubRefund((_) async => ok);
      expect(await c.confirm(all: true), isTrue);
      verify(() => repo.refundSale('sale-1', items: null, reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).called(1);
    });

    test('cancelling the reason picker sends nothing', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      ReasonPicker.testOverride = (_) async => null;
      expect(await c.confirm(), isFalse);
      verifyNever(() => repo.refundSale(any(), items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken')));
    });

    test('OPEN_SHIFT_REQUIRED is explained in plain words, not as a server error', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      when(() => repo.lastErrorCode).thenReturn('OPEN_SHIFT_REQUIRED');
      stubRefund((_) async => (success: false, refundedAmount: null, newStatus: null, message: 'Open a shift on this register before paying a cash refund', tenders: const <PosPaymentLine>[]));
      expect(await c.confirm(), isFalse);
      expect(c.error.value, 'Open a shift on this register before paying a cash refund.');
    });

    test('double tap: while the first confirm is in flight a second does nothing', () async {
      final c = make();
      await c.load();
      c.setQty('i1', 1);
      final gate = Completer<({bool success, double? refundedAmount, String? newStatus, String? message, List<PosPaymentLine> tenders})>();
      stubRefund((_) => gate.future);
      final first = c.confirm();
      await Future<void>.delayed(Duration.zero);
      final second = await c.confirm();
      expect(second, isFalse);
      gate.complete(ok);
      expect(await first, isTrue);
      verify(() => repo.refundSale('sale-1', items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).called(1);
    });
  });

  group('return screens', () {
    late MockPosRepository repo;
    Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(390, 900), ThemeData? theme}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: theme ?? AppTheme.light, home: w)));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    PosReturnController make(PosSaleModel sale) {
      repo = MockPosRepository();
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale);
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.lastErrorReasons).thenReturn(const []);
      when(() => repo.lastCreditNote).thenReturn({'id': 'cn1', 'number': 'CN-000001', 'totalMinor': 990});
      ReasonPicker.testOverride = (_) async => const PosReasonChoice('wrong_item', '');
      final c = PosReturnController(repository: repo, saleId: 'sale-1');
      Get.put(c);
      return c;
    }

    testWidgets('lines with steppers; choosing a quantity shows the credit and the per-tender plan; restock off asks why; no receipt warns', (t) async {
      final c = make(invoiceSale());
      await pump(t, PosReturnView(controller: c));
      expect(find.byKey(const Key('returnHeader')), findsOneWidget);
      expect(find.text('INV-000007  ·  \$29.70'), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('returnSelected'))).onPressed, isNull);
      c.setQty('i1', 1);
      await t.pump();
      expect(find.byKey(const Key('returnEstimate')), findsOneWidget);
      expect(find.byKey(const Key('returnPlanLine')), findsWidgets);
      expect(find.byKey(const Key('restock_i1')), findsOneWidget);
      await t.tap(find.byKey(const Key('restock_i1')));
      await t.pump();
      expect(find.byKey(const Key('restockReason_i1')), findsOneWidget);
      await t.tap(find.byKey(const Key('receiptSwitch')));
      await t.pump();
      expect(find.byKey(const Key('noReceiptNote')), findsOneWidget);
    });

    testWidgets('a sale that cannot be returned says so; a missing sale shows the error', (t) async {
      await pump(t, PosReturnView(controller: make(invoiceSale(status: 'voided'))));
      expect(find.byKey(const Key('returnNotAllowed')), findsOneWidget);
      Get.reset();
      final repo2 = MockPosRepository();
      when(() => repo2.getSaleById('sale-1')).thenAnswer((_) async => null);
      final c2 = PosReturnController(repository: repo2, saleId: 'sale-1');
      Get.put(c2);
      await pump(t, PosReturnView(controller: c2));
      expect(find.byKey(const Key('returnError')), findsOneWidget);
    });

    testWidgets('a fully returned line is marked Returned and has no stepper', (t) async {
      final c = make(invoiceSale(status: 'partially_refunded', refunded: 3, extraLine: true));
      await pump(t, PosReturnView(controller: c));
      expect(find.text('Returned'), findsOneWidget);
      expect(find.byKey(const Key('returnStepper_i1')), findsNothing);
    });

    testWidgets('Return selected → the sheet for a manager (RETURN_NEEDS_MANAGER) → retry with the manager\'s token → Return recorded with the credit note number', (t) async {
      final c = make(invoiceSale());
      await pump(t, PosReturnView(controller: c), size: const Size(800, 1400));
      var calls = 0;
      when(() => repo.lastErrorCode).thenAnswer((_) => calls == 1 ? 'RETURN_NEEDS_MANAGER' : null);
      when(() => repo.lastErrorReasons).thenReturn(const ['no_original_receipt']);
      when(() => repo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin'))).thenAnswer((_) async => (success: true, employee: manager(), activeSession: null, employeeToken: 'mgr-token', message: null));
      when(() => repo.refundSale(any(), items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).thenAnswer((inv) async {
        calls++;
        return inv.namedArguments[#approverToken] == null
            ? (success: false, refundedAmount: null, newStatus: null, message: 'x', tenders: const <PosPaymentLine>[])
            : (success: true, refundedAmount: 9.9, newStatus: 'partially_refunded', message: null, tenders: const [PosPaymentLine(method: 'cash', amount: 9.9)]);
      });
      c.setQty('i1', 1);
      await t.pump();
      await t.tap(find.byKey(const Key('returnSelected')));
      await settle(t);
      expect(find.byKey(const Key('approverEmail')), findsOneWidget);
      expect(find.textContaining('has no original receipt'), findsOneWidget);
      await t.enterText(find.byKey(const Key('approverEmail')), 'mia@x.pk');
      for (final d in ['1', '1', '1', '1']) {
        await t.tap(find.text(d).last);
        await t.pump();
      }
      await settle(t);
      expect(find.byKey(const Key('returnDoneTitle')), findsOneWidget);
      expect(find.text('Credit note CN-000001'), findsOneWidget);
      expect(find.byKey(const Key('returnDoneInstruction')), findsWidgets);
      verify(() => repo.refundSale('sale-1', items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: 'mgr-token')).called(1);
    });

    testWidgets('a refused return (open shift) shows the reason and stays on the screen', (t) async {
      final c = make(invoiceSale());
      await pump(t, PosReturnView(controller: c));
      c.setQty('i1', 1);
      await t.pump();
      when(() => repo.lastErrorCode).thenReturn('OPEN_SHIFT_REQUIRED');
      when(() => repo.refundSale(any(), items: any(named: 'items'), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'), receiptPresented: any(named: 'receiptPresented'), approverToken: any(named: 'approverToken'))).thenAnswer((_) async => (success: false, refundedAmount: null, newStatus: null, message: 'm', tenders: const <PosPaymentLine>[]));
      await t.tap(find.byKey(const Key('returnSelected')));
      await settle(t);
      expect(find.byKey(const Key('returnProblem')), findsOneWidget);
      expect(find.text('Open a shift on this register before paying a cash refund.'), findsOneWidget);
      expect(find.byKey(const Key('returnDoneTitle')), findsNothing);
    });

    testWidgets('tablet + dark render', (t) async {
      final c = make(invoiceSale());
      await pump(t, PosReturnView(controller: c), size: const Size(1100, 800), theme: AppTheme.dark);
      expect(find.byKey(const Key('returnHeader')), findsOneWidget);
    });

    testWidgets('Return recorded: amount, credit note badge, what to hand over, Done', (t) async {
      final c = make(invoiceSale());
      c.result.value = {'number': 'CN-000004'};
      c.resultAmount = 12.5;
      c.resultInstructions.assignAll(['Cash: take \$5.00 from the drawer', 'Card: refund \$7.50 on the card machine']);
      await c.load();
      await pump(t, PosReturnCompleteView(c: c));
      expect(find.byKey(const Key('returnDoneAmount')), findsOneWidget);
      expect(find.text('Credit note CN-000004'), findsOneWidget);
      expect(find.byKey(const Key('returnDoneInstruction')), findsNWidgets(2));
      expect(find.byKey(const Key('openCreditNote')), findsOneWidget);
    });
  });

  group('tax invoice and credit note screens', () {
    late MockPosRepository repo;
    final shared = <ShareParams>[];
    PosDocumentsController make({PosSaleModel? sale, List<PosCreditNote> notes = const [], String? link = 'https://api.test/r/TOKEN'}) {
      repo = MockPosRepository();
      shared.clear();
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale ?? invoiceSale());
      when(() => repo.getSaleDocuments('sale-1')).thenAnswer((_) async => PosSaleDocuments(saleNumber: 'POS-00007', status: 'completed', creditNotes: notes));
      when(() => repo.getReceiptLink('sale-1')).thenAnswer((_) async => link);
      final c = PosDocumentsController(repository: repo, saleId: 'sale-1', share: (p) async => shared.add(p));
      Get.put(c);
      return c;
    }

    Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(390, 1000), ThemeData? theme}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(GetMaterialApp(theme: theme ?? AppTheme.light, home: w));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('the invoice shows its number, the seller as registered, per-line value + tax, HS code, totals and how it was paid', (t) async {
      await pump(t, TaxInvoiceView(controller: make()));
      expect(find.text('INV-000007'), findsOneWidget);
      expect(find.text('Test Traders Ltd'), findsOneWidget);
      expect(find.text('NTN 1234567-8'), findsOneWidget);
      expect(find.text('STRN 3277876'), findsOneWidget);
      expect(find.textContaining('HS 09024090'), findsOneWidget);
      expect(find.text('+ \$2.70 tax'), findsOneWidget);
      expect(find.text('Sales tax'), findsOneWidget);
      expect(find.byKey(const Key('invoiceTotal')), findsOneWidget);
    });

    testWidgets('a sale from before invoices were numbered says so (and still shows its lines)', (t) async {
      await pump(t, TaxInvoiceView(controller: make(sale: invoiceSale(withInvoice: false))));
      expect(find.byKey(const Key('invoiceLegacy')), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
    });

    testWidgets('credit notes are listed (number, kind, amount) and open their own screen with tax reversed and restock status', (t) async {
      final c = make(notes: [note(), note(number: 'CN-000002', total: 500, restock: false)]);
      await pump(t, TaxInvoiceView(controller: c));
      await t.scrollUntilVisible(find.byKey(const Key('note_CN-000001')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('note_CN-000002')), findsOneWidget);
      await t.tap(find.byKey(const Key('note_CN-000001')));
      await settle(t);
      expect(find.byKey(const Key('noteNumber')), findsOneWidget);
      expect(find.text('Against invoice INV-000007'), findsOneWidget);
      expect(find.text('Tax reversed'), findsOneWidget);
      expect(find.text('Back on the shelf'), findsOneWidget);
      expect(find.byKey(const Key('noteApproved')), findsOneWidget);
    });

    testWidgets('a credit note that was NOT restocked says why', (t) async {
      final c = make(notes: [note(restock: false)]);
      await c.load();
      await pump(t, CreditNoteView(controller: c, number: 'CN-000001'));
      expect(find.textContaining('Not restocked — spilled'), findsOneWidget);
    });

    testWidgets('Print / share PDF shares a PDF file; Share link shares the /invoice page of the receipt link; a credit note shares its own page', (t) async {
      final c = make(notes: [note()]);
      await pump(t, TaxInvoiceView(controller: c));
      await t.runAsync(() async {
        await c.shareInvoicePdf();
        await c.shareLink();
        await c.shareLink(creditNoteNumber: 'CN-000001');
        await c.shareCreditNotePdf(c.creditNotes.first);
      });
      expect([shared[0].files!.single.mimeType, shared[0].subject], ['application/pdf', 'Tax invoice INV-000007']);
      expect(shared[1].text, 'https://api.test/r/TOKEN/invoice');
      expect(shared[2].text, 'https://api.test/r/TOKEN/credit-note/CN-000001');
      expect([shared[3].files!.single.mimeType, shared[3].subject], ['application/pdf', 'Credit note CN-000001']);
    });

    testWidgets('no link (offline) shows a clear message and shares nothing', (t) async {
      final c = make(link: null);
      await pump(t, TaxInvoiceView(controller: c));
      await t.runAsync(c.shareLink);
      await t.pump();
      expect(shared, isEmpty);
      expect(c.error.value, contains('link could not be created'));
    });

    testWidgets('double tap on share is ONE share', (t) async {
      final c = make();
      await pump(t, TaxInvoiceView(controller: c));
      await t.runAsync(() async {
        final a = c.shareLink();
        final b = c.shareLink();
        await Future.wait([a, b]);
      });
      expect(shared, hasLength(1));
    });

    testWidgets('tablet + dark render', (t) async {
      final c = make(notes: [note()]);
      await pump(t, TaxInvoiceView(controller: c), size: const Size(1100, 800), theme: AppTheme.dark);
      expect(find.byKey(const Key('invoiceTotal')), findsOneWidget);
    });
  });
}
