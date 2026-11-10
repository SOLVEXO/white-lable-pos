// G3.5 daybook print builders (pure): the thermal layout at 58 mm (32 columns) and 80 mm (48), money at exponent 0 / 2 / 3, no line wider than the paper,
// the reconcile warning, the empty day and the PDF. The same DocLine list drives the ESC/POS bytes and the text, so what is asserted here is what prints.
import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/utils/daybook_escpos.dart';
import 'package:solvexo_pos/utils/daybook_pdf.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'support/g35_fixtures.dart';

String text(Daybook d, int cols, {String? store, DateTime? printed}) => TaxDocumentEscPos.render(DaybookEscPos.lines(d, cols: cols, storeName: store, printedAt: printed), cols);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('amounts', () {
    test('exponent 2 / 0 / 3 group thousands and keep the currency\'s own decimals', () {
      expect(DaybookEscPos.amount(123456, 2), '1,234.56');
      expect(DaybookEscPos.amount(123456, 0), '123,456');
      expect(DaybookEscPos.amount(123456, 3), '123.456');
      expect(DaybookEscPos.amount(5, 2), '0.05');
      expect(DaybookEscPos.amount(0, 2), '0.00');
    });
    test('a minus is always shown, a plus only when asked for', () {
      expect(DaybookEscPos.amount(-500, 2), '-5.00');
      expect(DaybookEscPos.amount(500, 2, signed: true), '+5.00');
      expect(DaybookEscPos.amount(500, 2), '5.00');
      expect(DaybookEscPos.amount(0, 2, signed: true), '0.00');
    });
  });

  group('thermal layout', () {
    for (final cols in [32, 48]) {
      test('$cols columns: no line is wider than the paper, with a long entry name and a huge amount', () {
        final d = daybook(
          shifts: [
            shift(
              employee: 'Muhammad Abdul-Rahman Al-Farouq Bin Abdullah',
              lines: [
                DaybookLine(type: 'opening', label: 'Opening float', amountMinor: 99999999999, runningMinor: 99999999999, at: DateTime(2026, 11, 9, 9)),
                DaybookLine(
                  type: 'expense',
                  label: 'Expense EXP-000123 — transport (Very Long Payee Name Trading Company Pvt Ltd)',
                  amountMinor: -123456789,
                  runningMinor: 99876543210,
                  at: DateTime(2026, 11, 9, 13),
                ),
              ],
            ),
          ],
        );
        final out = text(d, cols, store: 'A Rather Long Store Name Of The Neighbourhood Shop', printed: DateTime(2026, 11, 9, 17, 5));
        for (final l in out.split('\n')) {
          expect(l.length, lessThanOrEqualTo(cols), reason: '"$l"');
        }
        expect(out, contains('DAYBOOK'));
        expect(out, contains('Mon 9 Nov 2026'));
        expect(out, contains('Printed 2026-11-09 17:05'));
      });
    }

    test('58 mm: description + signed amount, then the running balance under it; every figure is the server\'s minor amount in the stated exponent', () {
      final out = text(daybook(), 32);
      expect(out, contains('All amounts in USD'));
      expect(out, contains('Shift 1: Main till - Sam'));
      expect(out, contains('Opened 09:00  Closed 18:00'));
      expect(out, contains('09:30 Sale S-0001'));
      expect(out, contains('+25.00'));
      expect(out, contains('bal 125.00'));
      expect(out, contains('-5.00'));
      expect(out, contains('bal 107.00'));
      expect(RegExp(r'Expected cash\s+107\.00').hasMatch(out), isTrue);
      expect(RegExp(r'Counted\s+106\.50').hasMatch(out), isTrue);
      expect(RegExp(r'Variance\s+-0\.50').hasMatch(out), isTrue);
      expect(RegExp(r'Cash out\s+-20\.00').hasMatch(out), isTrue);
      expect(out, isNot(contains('RECONCILE')));
    });

    test('80 mm: one row per entry with the amount and the balance in their own columns', () {
      final out = text(daybook(), 48);
      final row = out.split('\n').firstWhere((l) => l.contains('Sale S-0001'));
      expect(row.length, 48);
      expect(row.trimRight(), endsWith('125.00'));
      expect(row, contains('+25.00'));
      expect(out, isNot(contains('bal ')), reason: 'the balance is a column, not a second line');
    });

    for (final (code, _, minor, shown) in [('JPY', 0, 1234567, '1,234,567'), ('KWD', 3, 1234567, '1,234.567'), ('USD', 2, 1234567, '12,345.67')]) {
      test('$code: the opening float $minor prints as $shown and the header names the currency', () {
        final cur = code == 'JPY' ? jpy : (code == 'KWD' ? kwd : usd);
        final d = daybook(
          cur: cur,
          shifts: [
            shift(
              lines: [DaybookLine(type: 'opening', label: 'Opening float', amountMinor: minor, runningMinor: minor, at: DateTime(2026, 11, 9, 9))],
            ),
          ],
        );
        for (final cols in [32, 48]) {
          final out = text(d, cols);
          expect(out, contains(shown), reason: '$cols columns');
          expect(out, contains('All amounts in $code'));
        }
      });
    }

    test('does not reconcile: a visible warning and the difference, per shift and in the totals; a reconciled day has none', () {
      final bad = text(daybook(shifts: [shift(reconciled: false, unreconciled: -300)]), 32);
      expect(bad.split('!! DOES NOT RECONCILE !!').length - 1, 2, reason: 'once for the shift, once in the totals');
      expect(RegExp(r'Difference\s+-3\.00').hasMatch(bad), isTrue);
      expect(text(daybook(), 32), isNot(contains('RECONCILE')));
    });

    test('an open shift says so and has no counted / variance rows; an empty day says so; a cashier\'s day says whose', () {
      final open = text(daybook(shifts: [shift(closed: false)]), 32);
      expect(open, contains('(open)'));
      expect(open, isNot(contains('Counted')));
      expect(open, isNot(contains('Variance\n')));
      final empty = text(daybook(shifts: const []), 32);
      expect(empty, contains('No shifts on this day.'));
      expect(text(daybook(own: true), 32), contains('Your own shifts only'));
    });

    test('several shifts are numbered, and the totals add them up', () {
      final out = text(
        daybook(
          shifts: [
            shift(id: 'a'),
            shift(id: 'b', employee: 'Ali'),
          ],
        ),
        48,
      );
      expect(out, contains('Shift 1: Main till - Sam'));
      expect(out, contains('Shift 2: Main till - Ali'));
      expect(RegExp(r'Cash sales\s+50\.00').hasMatch(out.substring(out.indexOf('TOTALS'))), isTrue);
    });

    test('no currency stated: no amounts are printed at all', () {
      final out = text(daybook(cur: null), 32);
      expect(out.replaceAll(RegExp(r'\s+'), ' '), contains('did not state the currency'));
      expect(out, isNot(contains('Sale S-0001')));
    });

    test('the ESC/POS bytes are produced for both paper sizes and start with the printer reset', () async {
      for (final (size, cols) in [(PaperSize.mm58, 32), (PaperSize.mm80, 48)]) {
        final bytes = await TaxDocumentEscPos.bytes(
          DaybookEscPos.lines(daybook(), cols: cols, storeName: 'Dev'),
          paperSize: size,
        );
        expect(bytes.length, greaterThan(200));
        expect(bytes.take(2), [0x1B, 0x40]);
      }
    });
  });

  group('PDF', () {
    test('A4 PDF bytes for a normal day, a day that does not reconcile and an empty day', () async {
      for (final d in [
        daybook(),
        daybook(shifts: [shift(reconciled: false, unreconciled: 300)]),
        daybook(shifts: const []),
        daybook(cur: null),
      ]) {
        final bytes = await DaybookPdf.build(d, storeName: 'Dev Store', printedAt: DateTime(2026, 11, 9, 17));
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        expect(bytes.length, greaterThan(800));
      }
    });
  });
}
