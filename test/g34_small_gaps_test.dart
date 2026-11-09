// G3.4 "small gaps": a pure store-credit sale is labelled "Store credit" in the Orders list; a points discount is labelled as points on the receipt and the tax invoice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_payment_badge.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'g25_returns_documents_test.dart' show invoiceSale;

PosSaleModel withPoints(int points) {
  final j = {
    '_id': 's1', 'saleNumber': 'S-1', 'storeId': 'st', 'sessionId': 'se', 'registerId': 'r', 'employeeId': 'e', 'status': 'completed', 'currency': 'USD', 'currencyExponent': 2,
    'subtotal': 20.0, 'discount': 5.0, 'tax': 1.5, 'total': 16.5, 'paymentMethod': 'cash', 'customerName': 'Walk-in', 'createdAt': '2026-11-06T10:00:00.000Z',
    'items': [{'_id': 'i1', 'productId': 'p', 'name': 'Tea', 'sku': 'T', 'qty': 2, 'price': 10.0, 'lineTotal': 20.0}],
    'payments': [{'method': 'cash', 'amount': 16.5}],
    if (points > 0) 'loyalty': {'earnedPoints': 1, 'redeemedPoints': points, 'redeemValueMinor': 500},
  };
  return PosSaleModel.fromJson(j);
}

void main() {
  testWidgets('the Orders list badge says "Store credit" for a store-credit sale (and still Cash / Card / Other for the rest)', (t) async {
    for (final (m, label) in [('store_credit', 'Store credit'), ('cash', 'Cash'), ('card', 'Card'), ('split', 'Other')]) {
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => MaterialApp(home: Scaffold(body: PosPaymentBadge(method: m)))));
      expect(find.text(label), findsOneWidget, reason: m);
    }
  });

  test('a discount that is a points redemption is labelled as points on the receipt, the thermal tax invoice and not as a plain "Discount"', () {
    final withPts = ReceiptData.fromSale(withPoints(10), null);
    expect(withPts.discountLabel, 'Points redeemed (10)');
    expect(ReceiptData.fromSale(withPoints(0), null).discountLabel, 'Discount');
    final lines = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(withPoints(10), cols: 48), 48);
    expect(lines, contains('Points (10)'));
    expect(TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(invoiceSale(), cols: 48), 48), contains('Discount'));
  });
}
