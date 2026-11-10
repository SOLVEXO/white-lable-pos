import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';

/// The attendance report as an A4 PDF to share (print from the share sheet): per person the hours worked (h:mm), days, breaks, late arrivals with the
/// server's grace, missing clock-outs, corrections and rostered vs worked, then the totals. A pure builder: no network, no payroll, no money.
class TeamReportPdf {
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

  /// The rows of the table as text (what the PDF prints; the unit tests compare these): name, days, worked, breaks, late, missing out, corrections, rostered.
  static List<List<String>> rows(TeamReport r) => [
    for (final p in r.people)
      [
        p.employeeName ?? 'Team member',
        '${p.daysWorked}',
        formatHm(p.workedMinutes),
        formatHm(p.breakMinutes),
        p.lateCount == 0 ? '0' : '${p.lateCount} (${p.lateMinutes} min)',
        '${p.missingClockOuts}',
        '${p.corrections}',
        formatHm(p.rosteredMinutes),
      ],
  ];

  static const headers = ['Name', 'Days', 'Worked', 'Breaks', 'Late', 'No clock-out', 'Corrected', 'Rostered'];

  /// [from] and [to] are the first and LAST day of the period (inclusive).
  static Future<Uint8List> build(TeamReport r, {required DateTime from, required DateTime to, String? storeName, DateTime? printedAt}) async {
    final doc = pw.Document(theme: await _theme());
    final f = DateFormat('d MMM yyyy');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if ((storeName ?? '').isNotEmpty) pw.Text(storeName!, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              'ATTENDANCE REPORT',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _accent),
            ),
            pw.Text(
              '${f.format(from)} - ${f.format(to)}   ·   late = more than ${r.lateGraceMinutes} min after the rostered start${printedAt == null ? '' : '   ·   Printed ${DateFormat('yyyy-MM-dd HH:mm').format(printedAt.toLocal())}'}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          if (r.people.isEmpty)
            pw.Text('No attendance in this period.', style: const pw.TextStyle(fontSize: 11))
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows(r),
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight, 0: pw.Alignment.centerLeft},
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5),
              ),
            ),
          pw.SizedBox(height: 14),
          pw.Text(
            'TOTALS',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _accent),
          ),
          pw.Text(
            'Hours worked ${formatHm(r.totalWorkedMinutes)}   ·   Late arrivals ${r.totalLateCount}   ·   Missing clock-outs ${r.totalMissingClockOuts}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
