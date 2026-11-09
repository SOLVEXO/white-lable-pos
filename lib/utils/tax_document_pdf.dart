import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Tax invoice and credit note as shareable PDFs (A5-ish, no printer needed). Money is printed from the server's own minor-unit figures.
/// A reserved band under the totals is left for the future fiscal block (FBR invoice number, QR, logo): it prints only once a fiscal number exists.
class TaxDocumentPdf {
  static const _accent = PdfColor.fromInt(0xFFB5543A);

  static Future<pw.ThemeData?> _theme() async {
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Bold.ttf'));
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      return null;
    }
  }

  static String _m(int minor, String currency, int exp) => Money.format(minor / _pow10(exp), currency: currency, exponent: exp);
  static String _tenderLabel(String m) => switch (m) { 'raast_qr' => 'Raast', 'store_credit' => 'Store credit', _ => '${m[0].toUpperCase()}${m.substring(1)}' };
  static num _pow10(int e) => e <= 0 ? 1 : List.filled(e, 10).fold<num>(1, (a, b) => a * b);

  static pw.Widget _row(String l, String r, {bool bold = false, double size = 10}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Expanded(child: pw.Text(l, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))), pw.Text(r, style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))],
        ),
      );

  static List<pw.Widget> _seller(String? name, String? address, String? ntn, String? strn) => [
        if (name != null && name.isNotEmpty) pw.Text(name, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        if (address != null && address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
        if (ntn != null && ntn.isNotEmpty) pw.Text('NTN $ntn', style: const pw.TextStyle(fontSize: 9)),
        if (strn != null && strn.isNotEmpty) pw.Text('STRN $strn', style: const pw.TextStyle(fontSize: 9)),
      ];

  /// [fiscalNumber] stays null until a fiscal integration exists; the band is then simply absent.
  static Future<Uint8List> invoice({required PosSaleModel sale, String? storeName, String? fiscalNumber}) async {
    final doc = pw.Document(theme: await _theme());
    final inv = sale.invoice;
    final exp = sale.currencyExponent;
    String m(double v) => Money.format(v, currency: sale.currency, exponent: exp);
    final when = DateFormat('yyyy-MM-dd HH:mm').format((inv?.issuedAt ?? sale.createdAt).toLocal());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        ..._seller(inv?.sellerName ?? storeName, inv?.sellerAddress, inv?.sellerNtn, inv?.sellerStrn),
        pw.SizedBox(height: 10),
        pw.Text('TAX INVOICE', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _accent)),
        pw.Text(inv?.number ?? sale.saleNumber, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text(when, style: const pw.TextStyle(fontSize: 9)),
        if (inv?.offlineRef != null) pw.Text('Offline ref ${inv!.offlineRef}', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        for (final i in sale.items)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(i.name, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('${i.qty} × ${m(i.price)}${i.hsCode != null ? ' · HS ${i.hsCode}' : ''}', style: const pw.TextStyle(fontSize: 8)),
                ]),
              ),
              pw.Text('${m((i.netMinor ?? 0) / _pow10(exp))}  +  ${m((i.taxMinor ?? 0) / _pow10(exp))} tax', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
        pw.Divider(),
        _row('Subtotal', m(sale.subtotal)),
        if (sale.discount > 0) _row('Discount', '-${m(sale.discount)}'),
        _row('Sales tax', m(sale.tax)),
        _row('Total', m(sale.total), bold: true, size: 12),
        pw.SizedBox(height: 6),
        for (final p in sale.payments) _row(_tenderLabel(p.method), m(p.amount), size: 9),
        // reserved for the fiscal block (invoice number from the tax authority, QR, logo) — printed only when one exists
        if (fiscalNumber != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 10), child: pw.Text('FBR invoice no. $fiscalNumber', style: const pw.TextStyle(fontSize: 9))),
      ]),
    ));
    return doc.save();
  }

  static Future<Uint8List> creditNote({required PosCreditNote note, String? storeName, String? fiscalNumber}) async {
    final doc = pw.Document(theme: await _theme());
    String m(int v) => _m(v, note.currency, note.exponent);
    final when = note.createdAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt!.toLocal());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        ..._seller(note.sellerName ?? storeName, note.sellerAddress, note.sellerNtn, note.sellerStrn),
        pw.SizedBox(height: 10),
        pw.Text('CREDIT NOTE', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _accent)),
        pw.Text(note.number, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text('$when${note.invoiceNumber != null ? ' · against invoice ${note.invoiceNumber}' : ''}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        for (final l in note.lines)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Text('${l.name}  ×${l.qty}${l.hsCode != null ? ' · HS ${l.hsCode}' : ''}', style: const pw.TextStyle(fontSize: 10))),
              pw.Text('${m(l.netMinor)}  +  ${m(l.taxMinor)} tax', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
        pw.Divider(),
        _row('Value excluding tax', m(note.netMinor)),
        _row('Tax reversed', m(note.taxMinor)),
        _row('Credited', m(note.totalMinor), bold: true, size: 12),
        pw.SizedBox(height: 6),
        pw.Text('Refunded to', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        for (final t in note.tenders) _row(_tenderLabel(t.method), m(t.amountMinor), size: 9),
        if (fiscalNumber != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 10), child: pw.Text('FBR invoice no. $fiscalNumber', style: const pw.TextStyle(fontSize: 9))),
      ]),
    ));
    return doc.save();
  }
}
