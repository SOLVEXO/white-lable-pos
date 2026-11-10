import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

/// G4.1 export of a report: the same table becomes a CSV (for a spreadsheet) and an A4 PDF (to share / print). Pure builders — no network.
sealed class RCell {
  const RCell();
}

class RText extends RCell {
  const RText(this.text);
  final String text;
}

/// money in MINOR units; the CSV writes it as a plain decimal with the response's exponent, the PDF through the currency
class RMoney extends RCell {
  const RMoney(this.minor);
  final int minor;
}

class RNum extends RCell {
  const RNum(this.value);
  final num value;
}

class RPct extends RCell {
  const RPct(this.value);
  final double? value;
}

class ReportTable {
  const ReportTable({required this.title, required this.headers, required this.rows, this.summary = const [], this.notes = const []});
  final String title;
  final List<String> headers;
  final List<List<RCell>> rows;

  /// label / value lines above the table (the PDF prints them; the CSV keeps to the table)
  final List<(String, RCell)> summary;
  final List<String> notes;
}

/// A minor amount as a plain decimal for a spreadsheet: no symbol, no thousands separator, `.` as the decimal point (`-1234.50`, exponent 0 → `1234`).
String minorPlain(int minor, int exponent) {
  if (exponent <= 0) return '$minor';
  final neg = minor < 0;
  final digits = minor.abs().toString().padLeft(exponent + 1, '0');
  final whole = digits.substring(0, digits.length - exponent);
  return '${neg ? '-' : ''}$whole.${digits.substring(digits.length - exponent)}';
}

String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
String _pct(double? v) => v == null ? '' : v.toStringAsFixed(1);

String hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';
String hoursMinutes(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// The table of a report (what the CSV and the PDF contain).
ReportTable reportTable(BizReport r) => switch (r) {
  SalesReport s => ReportTable(
    title: 'Sales',
    headers: const ['Day', 'Transactions', 'Sales incl. tax'],
    rows: [
      for (final d in s.byDay) [RText(d.day), RNum(d.transactions), RMoney(d.totalMinor)],
    ],
    summary: [
      ('Transactions', RNum(s.totals.transactions)),
      ('Gross sales (incl. tax)', RMoney(s.totals.grossSalesMinor)),
      ('Tax', RMoney(s.totals.taxMinor)),
      ('Discounts', RMoney(s.totals.discountMinor)),
      ('Returns', RNum(s.totals.returns)),
      ('Returned (incl. tax)', RMoney(s.totals.returnsMinor)),
      ('Net sales (ex tax, after returns)', RMoney(s.totals.netSalesMinor)),
      ('Average basket', RMoney(s.totals.averageBasketMinor)),
      if (s.previous != null) ('Previous period net sales (${s.previousFrom} - ${s.previousTo})', RMoney(s.previous!.netSalesMinor)),
    ],
  ),
  ProfitReport p => ReportTable(
    title: 'Profit',
    headers: const ['Figure', 'Amount'],
    rows: [
      [const RText('Net sales (ex tax)'), RMoney(p.totals.netSalesMinor)],
      [const RText('Cost of goods sold'), RMoney(p.totals.costOfGoodsSoldMinor)],
      [const RText('Gross margin'), RMoney(p.totals.grossMarginMinor)],
      [const RText('Margin %'), RPct(p.totals.marginPercent)],
      [const RText('Cost coverage %'), RPct(p.totals.costCoveragePercent)],
      [const RText('Net sales with unknown cost'), RMoney(p.totals.costUnknownNetMinor)],
      [const RText('Expenses'), RMoney(p.totals.expensesMinor)],
      for (final e in p.totals.expensesByCategoryMinor.entries) [RText('  Expenses: ${e.key.replaceAll('_', ' ')}'), RMoney(e.value)],
      [const RText('After expenses'), RMoney(p.totals.afterExpensesMinor)],
      [const RText('Supplier payments (information only, not subtracted)'), RMoney(p.totals.supplierPaymentsMinor)],
    ],
    notes: [
      ?p.grossMarginLabel,
      ?p.afterExpensesLabel,
      if (p.totals.partialCoverage) 'Only ${_pct(p.totals.costCoveragePercent)} % of net sales have a known cost; the margin covers those sales only.',
      ?p.totals.supplierPaymentsNote,
    ],
  ),
  ProductsReport p => ReportTable(
    title: 'Products',
    headers: const ['Product', 'SKU', 'Qty sold', 'Qty returned', 'Net sales', 'Cost', 'Gross margin', 'Margin %'],
    rows: [
      for (final x in p.products)
        [RText(x.name), RText(x.sku ?? ''), RNum(x.qtySold), RNum(x.qtyReturned), RMoney(x.netSalesMinor), RMoney(x.costMinor), RMoney(x.grossMarginMinor), RPct(x.marginPercent)],
    ],
  ),
  CategoriesReport c => ReportTable(
    title: 'Categories',
    headers: const ['Category', 'Qty', 'Net sales', 'Cost', 'Gross margin', 'Margin %'],
    rows: [
      for (final x in c.categories) [RText(x.name), RNum(x.qty), RMoney(x.netSalesMinor), RMoney(x.costMinor), RMoney(x.grossMarginMinor), RPct(x.marginPercent)],
    ],
  ),
  TaxReport t => ReportTable(
    title: 'Tax',
    headers: const ['Tax category', 'HS code', 'Sales net', 'Sales tax', 'Returns net', 'Returns tax', 'Net', 'Tax'],
    rows: [
      for (final x in t.rows)
        [
          RText(taxCategoryLabel(x.taxCategory)),
          RText(x.hsCode ?? ''),
          RMoney(x.salesNetMinor),
          RMoney(x.salesTaxMinor),
          RMoney(x.returnsNetMinor),
          RMoney(x.returnsTaxMinor),
          RMoney(x.netMinor),
          RMoney(x.taxMinor),
        ],
    ],
    summary: [
      ('Invoices', RNum(t.totals.invoices)),
      ('Tax on invoices', RMoney(t.totals.invoiceTaxMinor)),
      ('Credit notes', RNum(t.totals.creditNotes)),
      ('Tax on credit notes', RMoney(t.totals.creditNoteTaxMinor)),
      ('Net tax', RMoney(t.totals.netTaxMinor)),
    ],
  ),
  PaymentsReport p => ReportTable(
    title: 'Payment mix',
    headers: const ['Method', 'Payments', 'Paid', 'Refunded', 'Net', 'Share %'],
    rows: [
      for (final x in p.methods) [RText(paymentMethodLabel(x.method)), RNum(x.payments), RMoney(x.paidMinor), RMoney(x.refundedMinor), RMoney(x.netMinor), RPct(x.sharePercent)],
    ],
    summary: [('Net taken', RMoney(p.netMinor))],
  ),
  CashiersReport c => ReportTable(
    title: c.ownOnly ? 'My sales' : 'Cashiers',
    headers: const ['Name', 'Transactions', 'Sales', 'Net sales', 'Avg basket', 'Discounts', 'Returns', 'Returned net', 'Voids', 'Voided', 'Hours'],
    rows: [
      for (final x in c.cashiers)
        [
          RText(x.name),
          RNum(x.transactions),
          RMoney(x.salesMinor),
          RMoney(x.netSalesMinor),
          RMoney(x.averageBasketMinor),
          RMoney(x.discountsMinor),
          RNum(x.returnsProcessed),
          RMoney(x.returnsNetMinor),
          RNum(x.voids),
          RMoney(x.voidsMinor),
          RText(hoursMinutes(x.workedMinutes)),
        ],
    ],
  ),
  HourlyReport h => ReportTable(
    title: 'Hourly',
    headers: const ['Hour', 'Transactions', 'Sales'],
    rows: [
      for (final x in h.byHour) [RText(hourLabel(x.hour)), RNum(x.transactions), RMoney(x.totalMinor)],
    ],
    summary: [('Busiest hour', RText(h.busiestHour == null ? 'none' : hourLabel(h.busiestHour!)))],
  ),
};

/// CSV: a header row, then one line per row; money as a plain decimal with the response's exponent, no thousands separators.
class ReportCsv {
  static String _esc(String s) => RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

  static String cell(RCell c, int exponent) => switch (c) {
    RText x => x.text,
    RMoney x => minorPlain(x.minor, exponent),
    RNum x => _num(x.value),
    RPct x => _pct(x.value),
  };

  static String build(ReportTable t, {required int exponent}) {
    final out = StringBuffer()..writeln(t.headers.map(_esc).join(','));
    for (final r in t.rows) {
      out.writeln(r.map((c) => _esc(cell(c, exponent))).join(','));
    }
    return out.toString();
  }

  static Uint8List bytes(ReportTable t, {required int exponent}) => Uint8List.fromList(utf8.encode(build(t, exponent: exponent)));
}

/// The A4 PDF of a report: store, title, period (store days) and the store's TIME ZONE, the summary lines, the table and the notes.
class ReportPdf {
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

  static String text(RCell c, InvCur? cur) => switch (c) {
    RText x => x.text,
    RMoney x => cur == null ? minorPlain(x.minor, 2) : cur.format(x.minor),
    RNum x => _num(x.value),
    RPct x => x.value == null ? '—' : '${_pct(x.value)} %',
  };

  /// The line under the title: `Period 2026-11-02 to 2026-11-04 · Time zone Asia/Karachi`.
  static String periodLine(ReportHead h) => 'Period ${h.from}${h.to == h.from ? '' : ' to ${h.to}'}   ·   Time zone ${h.timeZone ?? 'not stated'}';

  static Future<Uint8List> build(ReportTable t, ReportHead head, {String? storeName, DateTime? printedAt}) async {
    final doc = pw.Document(theme: await _theme());
    final wide = t.headers.length > 6;
    doc.addPage(
      pw.MultiPage(
        pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if ((storeName ?? '').isNotEmpty) pw.Text(storeName!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              '${t.title.toUpperCase()} REPORT',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _accent),
            ),
            pw.Text(
              '${periodLine(head)}${head.cur == null ? '' : '   ·   ${head.cur!.code}'}${printedAt == null ? '' : '   ·   Printed ${DateFormat('yyyy-MM-dd HH:mm').format(printedAt)}'}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          if (t.summary.isNotEmpty) ...[
            for (final (label, value) in t.summary)
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
                  pw.Text(text(value, head.cur), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            pw.SizedBox(height: 10),
          ],
          if (t.rows.isEmpty)
            pw.Text('Nothing in this period.', style: const pw.TextStyle(fontSize: 11))
          else
            pw.TableHelper.fromTextArray(
              headers: t.headers,
              data: [
                for (final r in t.rows) [for (final c in r) text(c, head.cur)],
              ],
              headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellAlignments: {for (var i = 1; i < t.headers.length; i++) i: pw.Alignment.centerRight, 0: pw.Alignment.centerLeft},
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
              ),
            ),
          if (t.notes.isNotEmpty) ...[pw.SizedBox(height: 12), for (final n in t.notes) pw.Text(n, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))],
        ],
      ),
    );
    return doc.save();
  }
}
