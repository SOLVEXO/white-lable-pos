// G4.0 / G4.1 models (every report parses with its own currency + exponent and the store time zone), the date strip (store days) and the export:
// CSV (header row, plain decimals with the exponent, no thousands separators) and the A4 PDF with the period and the time zone, for exponents 0 / 2 / 3.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/utils/report_export.dart';

import 'support/g40_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('models', () {
    test('every report reads its head: currency + exponent, time zone, period', () {
      for (final k in ReportKind.values) {
        final r = report(k);
        expect(r.kind, k);
        expect([r.head.cur?.code, r.head.cur?.exponent, r.head.timeZone, r.head.from], ['PKR', 2, 'Asia/Karachi', '2026-11-02'], reason: k.name);
      }
    });

    test('no currency stated → no money shown', () {
      final h = ReportHead.fromJson({
        'period': {'from': '2026-11-01', 'to': '2026-11-01'},
      });
      expect(h.cur, isNull);
      expect(h.money(100), '—');
    });

    test('sales: totals, the previous period and the days', () {
      final s = SalesReport.fromJson(salesJson(compare: true));
      expect([s.totals.transactions, s.totals.netSalesMinor, s.previous!.netSalesMinor, s.previousFrom, s.previousTo], [4, 9000, 6000, '2026-10-30', '2026-11-01']);
      expect(s.byDay.map((d) => d.day), ['2026-11-02', '2026-11-03', '2026-11-04']);
      expect(SalesReport.fromJson(salesJson()).previous, isNull);
    });

    test('profit: coverage below 100 % is flagged; the supplier note is kept verbatim', () {
      final p = ProfitReport.fromJson(profitJson());
      expect(p.totals.partialCoverage, isTrue);
      expect(p.totals.supplierPaymentsNote, startsWith('Supplier payments are not expenses'));
      expect(p.totals.expensesByCategoryMinor, {'utilities': 500});
      expect(ProfitReport.fromJson(profitJson(coverage: 100)).totals.partialCoverage, isFalse);
    });

    test('hourly: the weekday × hour grid and the busiest hour', () {
      final h = HourlyReport.fromJson(hourlyJson());
      expect([h.heat.length, h.heat.first.length, h.heat[0][10], h.heat[1][15], h.busiestHour, h.isEmpty], [7, 24, 3300, 6600, 15, false]);
      expect(HourlyReport.fromJson(hourlyJson(empty: true)).isEmpty, isTrue);
    });

    test('pulse, time zone, labels and error words', () {
      final p = pulse();
      expect(
        [p.today.netSalesMinor, p.lastWeek.netSalesMinor, p.change['netSalesMinor'], p.change['cardMinor'], p.lowStockCount, p.clockedInNow, p.comparedDay],
        [2000, 1000, 100.0, null, 3, 2, '2026-11-03'],
      );
      expect([zone().timeZone, zone().today], ['Asia/Karachi', '2026-11-10']);
      expect([paymentMethodLabel('cash'), paymentMethodLabel('raast_qr'), taxCategoryLabel('standard'), taxCategoryLabel('zero_rated')], ['Cash', 'Raast QR', 'Standard rate', 'Zero rated']);
      expect(reportErrorMessage('INVALID_TIME_ZONE'), contains('Asia/Karachi'));
      expect(reportErrorMessage('POS_ACTION_FORBIDDEN'), 'Your role is not allowed to see this.');
      expect(reportErrorMessage('RANGE_TOO_LONG'), contains('366'));
    });

    test('store-day keys and the query', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(parseDayKey('2026-11-10'), DateTime(2026, 11, 10));
      expect(parseDayKey('junk'), isNull);
      expect(const ReportQuery(from: '2026-11-01', to: '2026-11-07', compare: true, registerId: 'r1').toQuery(), {'from': '2026-11-01', 'to': '2026-11-07', 'compare': 'previous', 'registerId': 'r1'});
      expect(const ReportQuery(from: '2026-11-01', to: '2026-11-01').toQuery(), {'from': '2026-11-01', 'to': '2026-11-01'});
    });
  });

  group('the date strip counts STORE days from the store\'s today', () {
    final today = DateTime(2026, 11, 11); // a Wednesday
    test('every range', () {
      String r(ReportRange x) {
        final (a, b) = x.days(today, customFrom: DateTime(2026, 10, 1), customTo: DateTime(2026, 10, 15));
        return '${dayKey(a)}..${dayKey(b)}';
      }

      expect(r(ReportRange.today), '2026-11-11..2026-11-11');
      expect(r(ReportRange.yesterday), '2026-11-10..2026-11-10');
      expect(r(ReportRange.thisWeek), '2026-11-09..2026-11-11', reason: 'Monday to today');
      expect(r(ReportRange.last7), '2026-11-05..2026-11-11');
      expect(r(ReportRange.thisMonth), '2026-11-01..2026-11-11');
      expect(r(ReportRange.last30), '2026-10-13..2026-11-11');
      expect(r(ReportRange.custom), '2026-10-01..2026-10-15');
    });
    test('across a month and a year boundary', () {
      final (a, b) = ReportRange.last7.days(DateTime(2026, 1, 3));
      expect([dayKey(a), dayKey(b)], ['2025-12-28', '2026-01-03']);
      final (c, d) = ReportRange.yesterday.days(DateTime(2026, 3, 1));
      expect([dayKey(c), dayKey(d)], ['2026-02-28', '2026-02-28']);
    });
  });

  group('CSV', () {
    test('minor → plain decimal for exponents 0, 2 and 3 (no separators, sign kept)', () {
      expect([minorPlain(123456, 0), minorPlain(-5, 0)], ['123456', '-5']);
      expect([minorPlain(123456, 2), minorPlain(5, 2), minorPlain(-1050, 2), minorPlain(0, 2)], ['1234.56', '0.05', '-10.50', '0.00']);
      expect([minorPlain(1234567, 3), minorPlain(7, 3), minorPlain(-1000, 3)], ['1234.567', '0.007', '-1.000']);
    });

    test('a header row, then one line per row; money with the response exponent', () {
      final t = reportTable(report(ReportKind.payments));
      final lines = const LineSplitter().convert(ReportCsv.build(t, exponent: 2));
      expect(lines.first, 'Method,Payments,Paid,Refunded,Net,Share %');
      expect(lines[1], 'Cash,3,88.00,11.00,77.00,77.8');
      expect(lines, hasLength(3));
      final zero = const LineSplitter().convert(ReportCsv.build(t, exponent: 0));
      expect(zero[1], 'Cash,3,8800,1100,7700,77.8');
      final three = const LineSplitter().convert(ReportCsv.build(t, exponent: 3));
      expect(three[1], 'Cash,3,8.800,1.100,7.700,77.8');
    });

    test('commas and quotes are escaped; every report has a table with a header row', () {
      const t = ReportTable(
        title: 'x',
        headers: ['Name', 'Net'],
        rows: [
          [RText('Tea, green "fine"'), RMoney(123456789)],
        ],
      );
      expect(ReportCsv.build(t, exponent: 2).split('\n')[1], '"Tea, green ""fine""",1234567.89');
      for (final k in ReportKind.values) {
        final table = reportTable(report(k));
        final csv = ReportCsv.build(table, exponent: 2);
        expect(csv.split('\n').first, table.headers.join(','), reason: k.name);
        expect(csv, isNot(contains('Rs')), reason: 'no currency symbol in a CSV');
      }
    });

    test('the profit table keeps the supplier payments as information and the coverage note', () {
      final t = reportTable(report(ReportKind.profit));
      expect(t.rows.map((r) => (r.first as RText).text), contains('Supplier payments (information only, not subtracted)'));
      expect(t.notes.join(' '), contains('88.9 %'));
      expect(t.notes.last, startsWith('Supplier payments are not expenses'));
    });
  });

  group('PDF', () {
    test('an A4 document with the period and the store time zone printed', () async {
      for (final k in ReportKind.values) {
        final r = report(k);
        final bytes = await ReportPdf.build(reportTable(r), r.head, storeName: 'Dev Store', printedAt: DateTime(2026, 11, 10, 15));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: k.name);
      }
      expect(ReportPdf.periodLine(report(ReportKind.sales).head), 'Period 2026-11-02 to 2026-11-04   ·   Time zone Asia/Karachi');
    });

    test('cells: money through the currency for exponents 0 / 2 / 3; percentages; unknown as a dash', () {
      final pkr = report(ReportKind.sales).head.cur!;
      expect(ReportPdf.text(const RMoney(123456), pkr), pkr.format(123456));
      final h0 = ReportHead.fromJson(head(currency: 'JPY', exponent: 0));
      final h3 = ReportHead.fromJson(head(currency: 'KWD', exponent: 3));
      expect(ReportPdf.text(const RMoney(1500), h0.cur), h0.cur!.format(1500));
      expect(ReportPdf.text(const RMoney(1500), h3.cur), h3.cur!.format(1500));
      expect(h0.cur!.format(1500), contains('1,500'));
      expect(h3.cur!.format(1500), contains('1.500'));
      expect([ReportPdf.text(const RPct(52.5), null), ReportPdf.text(const RPct(null), null), ReportPdf.text(const RNum(3), null)], ['52.5 %', '—', '3']);
    });
  });
}
