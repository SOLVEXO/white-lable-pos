import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:solvexo_pos/utils/receipt_data.dart';

/// Renders a [ReceiptData] as a receipt-shaped PDF (shareable, no printer needed). Uses the bundled Inter font so
/// currency symbols and non-Latin names/customers render instead of dropping out (the PDF default font is Latin-1).
class ReceiptPdfBuilder {
  static const _accent = PdfColor.fromInt(0xFFD97757);
  static const _red = PdfColor.fromInt(0xFFB3261E);

  static Future<pw.ThemeData?> _theme() async {
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Bold.ttf'));
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      return null; // font assets unavailable (e.g. a bare unit test) — fall back to the PDF default
    }
  }

  static Future<Uint8List> build({required ReceiptData data}) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme);

    pw.Widget center(String t, {double size = 9, bool bold = false, PdfColor? color}) => pw.Center(
          child: pw.Text(t, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
        );

    pw.Widget row(String l, String r, {bool bold = false, double size = 9}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text(l, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
              pw.SizedBox(width: 6),
              pw.Text(r, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (data.banner != null) center('*** ${data.banner} ***', size: 13, bold: true, color: _red),
            if (data.offlineNote != null) center('*** ${data.offlineNote} ***', size: 10, bold: true, color: _red),
            if (data.reprintNumber != null) center('REPRINT #${data.reprintNumber}', size: 9, bold: true) else if (data.isCopy) center('COPY', size: 9, bold: true),
            if (data.businessName != null) center(data.businessName!, size: 14, bold: true),
            if (data.header != null) center(data.header!),
            if (data.address != null) center(data.address!, size: 8),
            if (data.taxId != null) center(data.taxId!, size: 8),
            pw.SizedBox(height: 8),
            center('Receipt ${data.receiptNumber}', size: 11, bold: true, color: _accent),
            if (data.offlineRef != null) center('Offline ref ${data.offlineRef}', size: 8),
            center(data.dateText, size: 8),
            if (data.cashier != null) center('Cashier: ${data.cashier}', size: 8),
            pw.SizedBox(height: 6),
            pw.Divider(),
            for (final l in data.lines) ...[
              row(l.name, l.total),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                child: pw.Text('${l.qtyAndPrice}${l.note != null ? '  (${l.note})' : ''}', style: const pw.TextStyle(fontSize: 8)),
              ),
            ],
            pw.Divider(),
            row('Subtotal', data.subtotal),
            if (data.discount != null) row(data.discountLabel ?? 'Discount', data.discount!),
            if (data.tax != null) row(data.taxLabel ?? 'Tax', data.tax!),
            pw.SizedBox(height: 3),
            row('TOTAL', data.total, bold: true, size: 11),
            pw.SizedBox(height: 6),
            for (final p in data.payments) ...[
              row(p.label, p.amount),
              if (p.detail != null) pw.Padding(padding: const pw.EdgeInsets.only(left: 8), child: pw.Text(p.detail!, style: const pw.TextStyle(fontSize: 8))),
            ],
            if (data.change != null) row('Change', data.change!),
            for (final r in data.refunds) row(r.label, r.amount, size: 9),
            pw.SizedBox(height: 4),
            if (data.customer != null) row('Customer', data.customer!),
            // G4.8 receipt designer: points of this sale, the digital-receipt QR, the receipt-number barcode
            if (data.pointsEarned != null) row('Points earned', '${data.pointsEarned}', size: 9),
            if (data.pointsRedeemed != null) row('Points redeemed', '${data.pointsRedeemed}', size: 9),
            if (data.footer != null) ...[
              pw.SizedBox(height: 10),
              pw.Divider(),
              center(data.footer!, size: 8),
            ],
            if (data.qrPayload != null) ...[
              pw.SizedBox(height: 8),
              pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: data.qrPayload!, width: 72, height: 72)),
            ],
            if (data.barcodeData != null) ...[
              pw.SizedBox(height: 8),
              pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: data.barcodeData!, width: 150, height: 36, drawText: true, textStyle: const pw.TextStyle(fontSize: 7))),
            ],
          ],
        ),
      ),
    );
    return doc.save();
  }
}
