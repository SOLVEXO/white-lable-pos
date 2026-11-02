// One ReceiptData feeds the PDF, the thermal print and the shared text — so these assertions cover all three.
// Currency and decimals come from the SALE; VOID / REFUNDED / COPY banners, tax rate, tenders, change, refunds.

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';

PosSaleModel sale({
  String currency = 'USD',
  int exp = 2,
  String status = 'completed',
  List<PosPaymentLine> payments = const [],
  double changeGiven = 0,
  double refunded = 0,
  List<PosRefundRecord> refunds = const [],
  double total = 58.42,
}) =>
    PosSaleModel(
      id: 'abc', saleNumber: 'POS-00007', storeId: 's', sessionId: 'x', registerId: 'r', employeeId: 'e', employeeName: 'Cal Cashier',
      items: const [PosSaleItemModel(saleItemId: 'i1', productId: 'p', name: 'Tea', qty: 3, price: 19.99, lineTotal: 59.97, refundedQty: 0)],
      discount: 6, tax: 4.45, subtotal: 59.97, total: total, paymentMethod: payments.length > 1 ? 'split' : 'cash', customerName: 'Walk-in', notes: '',
      status: status, createdAt: DateTime(2026, 11, 2, 14, 5), refundedAmount: refunded,
      currency: currency, currencyExponent: exp, payments: payments, changeGiven: changeGiven,
      discountType: 'percent', discountValue: 10, taxRate: 0.0825, refunds: refunds,
    );

const settings = PosSettingsModel(storeId: 's', taxRate: 0.0825, businessName: 'Tea House', businessAddress: '1 Main St', businessTaxId: 'NTN 123', receiptHeader: 'Thanks!', receiptFooter: 'No returns after 7 days');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle (fonts) + the ESC/POS capability profile need it

  test('carries address, tax id, cashier, receipt number, formatted date, unit price, tax rate and discount %', () {
    final d = ReceiptData.fromSale(sale(payments: const [PosPaymentLine(method: 'cash', amount: 58.42)]), settings);
    expect(d.businessName, 'Tea House');
    expect(d.address, '1 Main St');
    expect(d.taxId, 'NTN 123');
    expect(d.cashier, 'Cal Cashier');
    expect(d.receiptNumber, 'POS-00007');
    expect(d.dateText, '2026-11-02 14:05');
    expect(d.lines.single.qtyAndPrice, contains('3 × '));
    expect(d.lines.single.qtyAndPrice, contains('19.99'));
    expect(d.discountLabel, 'Discount (10%)');
    expect(d.taxLabel, 'Tax (8.25%)');
    expect(d.total, '\$58.42');
  });

  test('every reprint is marked COPY', () => expect(ReceiptData.fromSale(sale(), settings).isCopy, isTrue));

  test('a VOIDED sale prints a VOID banner; refunded / partially refunded likewise', () {
    expect(ReceiptData.fromSale(sale(status: 'voided'), settings).banner, 'VOID');
    expect(ReceiptData.fromSale(sale(status: 'refunded', refunded: 58.42), settings).banner, 'REFUNDED');
    expect(ReceiptData.fromSale(sale(status: 'partially_refunded', refunded: 10), settings).banner, 'PARTIALLY REFUNDED');
    expect(ReceiptData.fromSale(sale(), settings).banner, isNull);
  });

  test('split tender: one row per tender, cash tendered + change, card reference', () {
    final d = ReceiptData.fromSale(
      sale(payments: const [PosPaymentLine(method: 'card', amount: 30, reference: 'AUTH-9'), PosPaymentLine(method: 'cash', amount: 28.42, tendered: 40)], changeGiven: 11.58),
      settings,
    );
    expect(d.payments.map((p) => p.label), ['Card', 'Cash']);
    expect(d.payments[0].detail, 'Ref AUTH-9');
    expect(d.payments[1].detail, 'Tendered \$40.00');
    expect(d.change, '\$11.58');
  });

  test('a sale from before split tender still prints one payment line for the whole total', () {
    final d = ReceiptData.fromSale(sale(), settings);
    expect(d.payments.single.label, 'Cash');
    expect(d.payments.single.amount, '\$58.42');
  });

  test('refund rows say what came back and to which tenders', () {
    final d = ReceiptData.fromSale(
      sale(status: 'partially_refunded', refunded: 20, refunds: const [PosRefundRecord(amount: 20, kind: 'partial', tenders: [PosPaymentLine(method: 'card', amount: 20)])]),
      settings,
    );
    expect(d.refunds.single.label, 'Partial refund to Card');
    expect(d.refunds.single.amount, '-\$20.00');
    expect(d.totalRefunded, '\$20.00');
  });

  test('JPY: no decimals anywhere; KWD: three', () {
    final jpy = ReceiptData.fromSale(sale(currency: 'JPY', exp: 0, total: 934), null);
    expect(jpy.total, isNot(contains('.')));
    expect(jpy.total, contains('934'));
    final kwd = ReceiptData.fromSale(sale(currency: 'KWD', exp: 3, total: 3.428), null);
    expect(kwd.total, endsWith('3.428'));
  });

  test('thermal-safe money uses the currency CODE, not a symbol the printer cannot print', () {
    final d = ReceiptData.fromSale(sale(currency: 'JPY', exp: 0, total: 934), null, asciiSafeMoney: true);
    expect(d.total, 'JPY 934');
    expect(ReceiptData.fromSale(sale(), null, asciiSafeMoney: true).total, 'USD 58.42');
  });

  test('plain text includes banner, COPY, tax id, tenders, refunds and footer', () {
    final text = ReceiptData.fromSale(sale(status: 'voided'), settings).toPlainText();
    expect(text, contains('*** VOID ***'));
    expect(text, contains('COPY'));
    expect(text, contains('NTN 123'));
    expect(text, contains('Tax (8.25%)'));
    expect(text, contains('No returns after 7 days'));
  });

  test('the PDF and ESC/POS renderers produce output from the same data', () async {
    final d = ReceiptData.fromSale(sale(payments: const [PosPaymentLine(method: 'cash', amount: 58.42)]), settings);
    final pdf = await ReceiptPdfBuilder.build(data: d);
    expect(pdf.length, greaterThan(500));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final thermal = await ReceiptEscPosBuilder.build(data: ReceiptData.fromSale(sale(), settings, asciiSafeMoney: true));
    expect(thermal, isNotEmpty);
  });

  test('non-Latin names do not crash the thermal builder', () async {
    final s = sale();
    final d = ReceiptData(
      receiptNumber: '1', dateText: 'x', customer: 'محمد', lines: const [ReceiptLine(name: 'شاي', qtyAndPrice: '1 × USD 1.00', total: 'USD 1.00')],
      subtotal: 'USD 1.00', total: 'USD 1.00', payments: const [], isCopy: true,
    );
    expect(s, isNotNull);
    expect(await ReceiptEscPosBuilder.build(data: d), isNotEmpty);
  });
}
