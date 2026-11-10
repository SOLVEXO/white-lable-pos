// G3.6 attendance report PDF (a pure builder): hours as h:mm, the table text, the late grace, empty and long reports.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/utils/team_report_pdf.dart';

import 'support/g36_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the table prints hours as h:mm, late as "count (minutes)", and keeps the column order', () {
    final rows = TeamReportPdf.rows(report());
    expect(TeamReportPdf.headers, ['Name', 'Days', 'Worked', 'Breaks', 'Late', 'No clock-out', 'Corrected', 'Rostered']);
    expect(rows[0], ['Sam', '5', '40:15', '2:30', '2 (35 min)', '0', '1', '40:00']);
    expect(rows[1], ['Ali', '3', '24:05', '1:30', '0', '1', '0', '24:00']);
  });

  test('a person with no name is a "Team member"; zero is 0:00', () {
    final r = TeamReport(people: const [ReportPerson(employeeId: 'x')]);
    expect(TeamReportPdf.rows(r).single, ['Team member', '0', '0:00', '0:00', '0', '0', '0', '0:00']);
  });

  test('A4 landscape PDF bytes for a normal report, an empty one and a long one', () async {
    final many = TeamReport(
      people: [for (var i = 0; i < 60; i++) ReportPerson(employeeId: 'e$i', employeeName: 'Person $i', workedMinutes: 60 * i, daysWorked: i % 7)],
      totalWorkedMinutes: 1000,
    );
    for (final r in [report(), const TeamReport(people: []), many]) {
      final bytes = await TeamReportPdf.build(r, from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 9), storeName: 'Dev Store', printedAt: DateTime(2026, 11, 10, 9));
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(800));
    }
  });
}
