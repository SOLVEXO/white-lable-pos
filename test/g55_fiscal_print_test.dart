// G5.5: the fiscal block on prints — the tax authority's number + QR once confirmed, "Fiscal pending" until then (and on every offline receipt when
// the store fiscalises); nothing when the store does not fiscalise.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'g25_returns_documents_test.dart' show invoiceSale;

PosSaleModel _sale(Map<String, dynamic>? fiscal) => PosSaleModel.fromJson({
      '_id': 'sale-1', 'saleNumber': 'POS-00007', 'storeId': 'store-1', 'sessionId': 's', 'registerId': 'r', 'employeeId': 'e', 'status': 'completed',
      'currency': 'PKR', 'currencyExponent': 2, 'subtotal': 10.0, 'discount': 0, 'tax': 0, 'total': 10.0, 'paymentMethod': 'cash', 'customerName': 'Walk-in',
      'createdAt': '2026-11-12T10:00:00.000Z',
      'invoice': {'number': 'INV-000007', 'issuedAt': '2026-11-12T10:00:00.000Z', if (fiscal != null) 'fiscal': fiscal},
      'items': [{'_id': 'i1', 'productId': 'p1', 'variantId': 'v1', 'name': 'Tea', 'sku': 'TEA', 'qty': 1, 'price': 10.0, 'lineTotal': 10.0, 'netMinor': 1000, 'taxMinor': 0}],
      'payments': [{'method': 'cash', 'amount': 10.0}],
    });

void main() {
  const confirmed = {'status': 'confirmed', 'externalInvoiceNumber': 'FBR-123456-0001', 'qrPayload': 'qr:FBR-123456-0001', 'attempts': 1, 'lastError': null};
  const pending = {'status': 'pending', 'externalInvoiceNumber': null, 'qrPayload': null, 'attempts': 0, 'lastError': null};

  test('models read the fiscal block (documents invoice, credit note, sale invoice)', () {
    final docs = PosSaleDocuments.fromJson({'saleNumber': 'POS-1', 'status': 'completed', 'invoice': {'number': 'INV-1', 'fiscal': confirmed}, 'creditNotes': [{'_id': 'c1', 'number': 'CN-1', 'kind': 'return', 'scope': 'full', 'currency': 'PKR', 'currencyExponent': 2, 'fiscal': pending}]});
    expect(docs.invoiceFiscal!.confirmed, isTrue);
    expect(docs.creditNotes.single.fiscal!.pending, isTrue);
    expect(_sale(confirmed).invoice!.fiscalConfirmed, isTrue);
    expect(_sale(null).invoice!.fiscalStatus, 'not_enabled');
  });

  test('tax invoice: confirmed → number + QR; pending → "Fiscal pending"; not enabled → nothing', () {
    String render(Map<String, dynamic>? f) => TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(invoiceSale(), cols: 48, fiscal: PosDocumentsController.slotsOf(PosFiscalInfo.fromJson(f))), 48);
    expect(render(confirmed), contains('FBR-123456-0001'));
    expect(render(pending), contains('Fiscal pending'));
    final off = render({'status': 'not_enabled'});
    expect(off, isNot(contains('Fiscal pending')));
    expect(off, isNot(contains('FBR Invoice No')));
  });

  test('sale receipt: confirmed block / pending / nothing; offline receipt is pending when the store fiscalises', () {
    final r1 = ReceiptData.fromSale(_sale(confirmed), null, asciiSafeMoney: true);
    // G6.1: the receipt carries the server's fiscal block (no display lines here → the number alone; pending → "Fiscal pending")
    expect([r1.fiscalPrint.textLines, r1.fiscalPrint.qr], [['FBR-123456-0001'], 'qr:FBR-123456-0001']);
    expect(ReceiptData.fromSale(_sale(pending), null).fiscalPrint.textLines, ['Fiscal pending']);
    expect(ReceiptData.fromSale(_sale(null), null).fiscalPrint.isEmpty, isTrue);
    final off = ReceiptData.forOfflineSale(provisionalNumber: 'OFF-1', madeAt: DateTime(2026, 11, 12), currency: 'PKR', exponent: 2, items: const [(name: 'Tea', qty: 1, unitPrice: 10)], subtotal: 10, discount: 0, tax: 0, total: 10, payments: const [(method: 'cash', amount: 10, reference: null)], change: 0, fiscalPending: true);
    expect(off.fiscalPending, isTrue);
    expect(ReceiptData.fromJson(off.toJson()).fiscalPending, isTrue); // survives the saved-receipt round trip
  });

  test('thermal bytes carry the words', () async {
    final pend = ReceiptData.fromSale(_sale(pending), null, asciiSafeMoney: true);
    final bytes = await ReceiptEscPosBuilder.build(data: pend);
    expect(latin1.decode(bytes, allowInvalid: true), contains('Fiscal pending'));
    final conf = ReceiptData.fromSale(_sale(confirmed), null, asciiSafeMoney: true);
    expect(latin1.decode(await ReceiptEscPosBuilder.build(data: conf), allowInvalid: true), contains('FBR-123456-0001'));
  });
}
