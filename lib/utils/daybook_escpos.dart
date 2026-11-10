import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

/// The daybook as a thermal receipt: pure builders, no printer needed. The same [DocLine] list becomes ESC/POS bytes ([TaxDocumentEscPos.bytes]) and plain text
/// ([TaxDocumentEscPos.render]) for the snapshot tests, so the 58 mm (32 columns) and 80 mm (48 columns) layouts are pinned. Amounts are written with the
/// response's own currency and exponent, never a configured one; on 80 mm each entry is ONE row (description, amount, running balance), on 58 mm two.
class DaybookEscPos {
  /// `1,234.50` / `1,235` (exponent 0) / `1.234` (exponent 3); [signed] adds `+` for money in (a minus is always shown).
  static String amount(int minor, int exp, {bool signed = false}) {
    final p = exp <= 0 ? 1 : List.filled(exp, 10).fold<int>(1, (a, b) => a * b);
    final text = NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: exp < 0 ? 0 : exp).format(minor.abs() / p);
    if (minor < 0) return '-$text';
    return signed && minor > 0 ? '+$text' : text;
  }

  static String _time(DateTime? d) => d == null ? '--:--' : DateFormat('HH:mm').format(d.toLocal());

  static List<DocLine> _centered(String t, int cols, {bool bold = false, bool big = false}) => [
    for (final l in ReceiptEscPosBuilder.wrap(t, big ? cols ~/ 2 : cols)) DocLine(l, align: PosAlign.center, bold: bold, big: big),
  ];
  static List<DocLine> _two(String l, String r, int cols, {bool bold = false}) => [for (final x in ReceiptEscPosBuilder.twoColumn(l, r, cols)) DocLine(x, bold: bold)];

  /// One daybook line. 80 mm: `09:12 Sale S-0001        +25.00     125.00` (description wraps in its own column); 58 mm: description + amount, then the balance.
  static List<DocLine> _entry(DaybookLine l, int cols, int exp) {
    final desc = '${_time(l.at)} ${l.label}';
    final amt = amount(l.amountMinor, exp, signed: true);
    final bal = amount(l.runningMinor, exp);
    if (cols >= 48) {
      const amtW = 11, balW = 12;
      final room = cols - amtW - balW - 1;
      final wrapped = ReceiptEscPosBuilder.wrap(desc, room);
      final out = <DocLine>[];
      for (var i = 0; i < wrapped.length; i++) {
        out.add(DocLine(i == wrapped.length - 1 ? wrapped[i].padRight(room + 1) + amt.padLeft(amtW) + bal.padLeft(balW) : wrapped[i]));
      }
      return out;
    }
    return [..._two(desc, amt, cols), DocLine('bal ${amount(l.runningMinor, exp)}', align: PosAlign.right)];
  }

  /// [from] is the day (local); a range is written `from - to`. [printedAt] is when it is printed.
  static List<DocLine> lines(Daybook d, {required int cols, String? storeName, DateTime? printedAt}) {
    final cur = d.cur;
    // no currency stated = no amounts printed (never a guessed one)
    if (cur == null) return [const DocLine('DAYBOOK', align: PosAlign.center, bold: true), ..._centered('The server did not state the currency, so no amounts are printed.', cols)];
    final code = cur.code;
    final exp = cur.exponent;
    String m(int v, {bool signed = false}) => amount(v, exp, signed: signed);
    final day = d.from == null ? '' : DateFormat('EEE d MMM yyyy').format(d.from!.toLocal());
    final out = <DocLine>[
      if ((storeName ?? '').isNotEmpty) ..._centered(storeName!, cols, bold: true, big: true),
      const DocLine('DAYBOOK', align: PosAlign.center, bold: true),
      if (day.isNotEmpty) DocLine(day, align: PosAlign.center),
      if (code.isNotEmpty) DocLine('All amounts in $code', align: PosAlign.center),
      if (printedAt != null) DocLine('Printed ${DateFormat('yyyy-MM-dd HH:mm').format(printedAt.toLocal())}', align: PosAlign.center),
      if (d.ownShiftsOnly) const DocLine('Your own shifts only', align: PosAlign.center),
      const DocLine.rule(),
    ];
    if (d.shifts.isEmpty) {
      out.addAll([const DocLine('No shifts on this day.', align: PosAlign.center), const DocLine.rule()]);
      return out;
    }
    for (var i = 0; i < d.shifts.length; i++) {
      final s = d.shifts[i];
      out.addAll([
        ...[for (final l in ReceiptEscPosBuilder.wrap('Shift ${i + 1}: ${s.registerName ?? 'Register'}${s.employeeName == null ? '' : ' - ${s.employeeName}'}', cols)) DocLine(l, bold: true)],
        DocLine('Opened ${_time(s.openedAt)}${s.closed ? '  Closed ${_time(s.closedAt)}' : '  (open)'}'),
        const DocLine.blank(),
        for (final l in s.lines) ..._entry(l, cols, exp),
        const DocLine.rule(),
        ..._two('Cash sales', m(s.cashSalesMinor), cols),
        ..._two('Refunds / voids', m(-s.cashRefundsMinor), cols),
        ..._two('Cash in', m(s.cashInMinor), cols),
        ..._two('Cash out', m(-s.cashOutMinor), cols),
        ..._two('Expenses', m(-s.expensesMinor), cols),
        ..._two('Supplier payments', m(-s.supplierPaymentsMinor), cols),
        ..._two('Expected cash', m(s.expectedCashMinor), cols, bold: true),
        if (s.countedMinor != null) ..._two('Counted', m(s.countedMinor!), cols),
        if (s.varianceMinor != null) ..._two('Variance', m(s.varianceMinor!, signed: true), cols, bold: true),
        if (!s.reconciled) ...[const DocLine('!! DOES NOT RECONCILE !!', align: PosAlign.center, bold: true), ..._two('Difference', m(s.unreconciledMinor, signed: true), cols)],
        const DocLine.rule(),
      ]);
    }
    final t = d.totals;
    out.addAll([
      const DocLine('TOTALS', align: PosAlign.center, bold: true),
      ..._two('Cash sales', m(t.cashSalesMinor), cols),
      ..._two('Refunds / voids', m(-t.cashRefundsMinor), cols),
      ..._two('Cash in', m(t.cashInMinor), cols),
      ..._two('Cash out', m(-t.cashOutMinor), cols),
      ..._two('Expenses', m(-t.expensesMinor), cols),
      ..._two('Supplier payments', m(-t.supplierPaymentsMinor), cols),
      ..._two('Variance', m(t.varianceMinor, signed: true), cols, bold: true),
      if (!d.reconciled) ...[const DocLine('!! DOES NOT RECONCILE !!', align: PosAlign.center, bold: true), ..._two('Difference', m(d.unreconciledMinor, signed: true), cols)],
      const DocLine.rule(),
    ]);
    return out;
  }
}
