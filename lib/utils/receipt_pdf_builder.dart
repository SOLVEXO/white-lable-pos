import 'dart:typed_data';

import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a simple, printable-shaped PDF receipt for a completed sale — the
/// in-app + shareable-PDF fallback scoped for Phase 1 in the absence of any
/// thermal/ESC-POS printer hardware integration. Uses the store's own
/// receiptHeader/receiptFooter/businessName (Settings → Receipt) and the
/// resolved currency symbol, so nothing here is hardcoded per store.
class ReceiptPdfBuilder {
  static const _accent = PdfColor.fromInt(0xFFD97757); // clay/terracotta

  static Future<Uint8List> build({
    required PosSaleModel sale,
    required String currencySymbol,
    PosSettingsModel? settings,
  }) async {
    final doc = pw.Document();
    String money(double v) => '$currencySymbol${v.toStringAsFixed(2)}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // narrow receipt-shaped page
        margin: const pw.EdgeInsets.all(16),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if ((settings?.businessName ?? '').isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    settings!.businessName!,
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              if ((settings?.receiptHeader ?? '').isNotEmpty)
                pw.Center(
                  child: pw.Text(settings!.receiptHeader!, style: const pw.TextStyle(fontSize: 9)),
                ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _accent),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  sale.createdAt.toLocal().toString(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(),
              ...sale.items.map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item.name} x${item.qty}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Text(money(item.lineTotal), style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
              pw.Divider(),
              _totalRow('Subtotal', money(sale.subtotal)),
              if (sale.discount > 0) _totalRow('Discount', '-${money(sale.discount)}'),
              if (sale.tax > 0) _totalRow('Tax', '+${money(sale.tax)}'),
              pw.SizedBox(height: 4),
              _totalRow('Total', money(sale.total), bold: true),
              pw.SizedBox(height: 8),
              _totalRow('Payment', sale.paymentMethod.toUpperCase()),
              _totalRow(
                'Customer',
                sale.customerName.isEmpty ? 'Walk-in' : sale.customerName,
              ),
              if (sale.refundedAmount > 0)
                _totalRow('Refunded', money(sale.refundedAmount)),
              if ((settings?.receiptFooter ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.Center(
                  child: pw.Text(settings!.receiptFooter!, style: const pw.TextStyle(fontSize: 8)),
                ),
              ],
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 10 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }
}
