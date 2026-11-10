import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/utils/daybook_escpos.dart';

/// The daybook as an A4 PDF to share (print from the share sheet): one section per shift with every line and its running balance, the shift summary, a
/// clear "does not reconcile" band when the server says so, and the day's totals. Amounts come from the server's minor-unit figures in its own currency.
class DaybookPdf {
  static const _accent = PdfColor.fromInt(0xFFB5543A);
  static const _warn = PdfColor.fromInt(0xFF8A5A00);

  static Future<pw.ThemeData?> _theme() async {
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/app_fonts/inter/Inter_Bold.ttf'));
      return pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _row(String l, String r, {bool bold = false, double size = 9.5}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          l,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
        pw.Text(
          r,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      ],
    ),
  );

  static Future<Uint8List> build(Daybook d, {String? storeName, DateTime? printedAt}) async {
    final doc = pw.Document(theme: await _theme());
    final cur = d.cur;
    if (cur == null) {
      // no currency stated = no amounts shown (never a guessed one)
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (_) => pw.Text('DAYBOOK\nThe server did not state the currency, so no amounts are shown.')));
      return doc.save();
    }
    final exp = cur.exponent;
    final code = cur.code;
    String m(int v, {bool signed = false}) => DaybookEscPos.amount(v, exp, signed: signed);
    final day = d.from == null ? '' : DateFormat('EEEE d MMMM yyyy').format(d.from!.toLocal());
    final t = d.totals;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if ((storeName ?? '').isNotEmpty) pw.Text(storeName!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              'DAYBOOK',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _accent),
            ),
            pw.Text(
              [day, if (code.isNotEmpty) 'Amounts in $code', if (printedAt != null) 'Printed ${DateFormat('yyyy-MM-dd HH:mm').format(printedAt.toLocal())}'].where((e) => e.isNotEmpty).join('   ·   '),
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (d.ownShiftsOnly) pw.Text('Your own shifts only', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          if (d.shifts.isEmpty) pw.Text('No shifts on this day.', style: const pw.TextStyle(fontSize: 11)),
          for (var i = 0; i < d.shifts.length; i++) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.all(8),
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1EDE7)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Shift ${i + 1}: ${d.shifts[i].registerName ?? 'Register'}${d.shifts[i].employeeName == null ? '' : ' - ${d.shifts[i].employeeName}'}',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '${d.shifts[i].openedAt == null ? '' : DateFormat('HH:mm').format(d.shifts[i].openedAt!.toLocal())} - ${d.shifts[i].closed && d.shifts[i].closedAt != null ? DateFormat('HH:mm').format(d.shifts[i].closedAt!.toLocal()) : 'open'}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.TableHelper.fromTextArray(
              headers: const ['Time', 'Entry', 'Amount', 'Balance'],
              data: [
                for (final l in d.shifts[i].lines) [l.at == null ? '' : DateFormat('HH:mm').format(l.at!.toLocal()), l.label, m(l.amountMinor, signed: true), m(l.runningMinor)],
              ],
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
              columnWidths: {0: const pw.FixedColumnWidth(40), 1: const pw.FlexColumnWidth(), 2: const pw.FixedColumnWidth(80), 3: const pw.FixedColumnWidth(80)},
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
              ),
            ),
            pw.SizedBox(height: 4),
            _row('Expected cash', m(d.shifts[i].expectedCashMinor), bold: true),
            if (d.shifts[i].countedMinor != null) _row('Counted', m(d.shifts[i].countedMinor!)),
            if (d.shifts[i].varianceMinor != null) _row('Variance', m(d.shifts[i].varianceMinor!, signed: true), bold: true),
            if (!d.shifts[i].reconciled)
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 4),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _warn)),
                child: pw.Text(
                  'DOES NOT RECONCILE: the shift\'s own figure differs by ${m(d.shifts[i].unreconciledMinor, signed: true)}',
                  style: pw.TextStyle(fontSize: 10, color: _warn, fontWeight: pw.FontWeight.bold),
                ),
              ),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'TOTALS',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _accent),
          ),
          _row('Cash sales', m(t.cashSalesMinor)),
          _row('Refunds / voids', m(-t.cashRefundsMinor)),
          _row('Cash in', m(t.cashInMinor)),
          _row('Cash out', m(-t.cashOutMinor)),
          _row('Expenses', m(-t.expensesMinor)),
          _row('Supplier payments', m(-t.supplierPaymentsMinor)),
          _row('Variance', m(t.varianceMinor, signed: true), bold: true),
          if (!d.reconciled) _row('Does not reconcile by', m(d.unreconciledMinor, signed: true), bold: true),
        ],
      ),
    );
    return doc.save();
  }
}
