import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

/// Renders a [ReceiptData] as raw ESC/POS bytes for a thermal printer. Build the data with
/// `asciiSafeMoney: true` (amounts as `JPY 1,234`, not `¥1,234`) — printers can't print most currency symbols —
/// and text is additionally reduced to what the default code page can print.
///
/// Layout is computed in CHARACTERS for the paper width (58 mm = 32 columns, 80 mm = 48 at the default font): long item names
/// and addresses wrap onto further lines, amounts stay right-aligned, nothing is silently cut off.
class ReceiptEscPosBuilder {
  static int columnsFor(int paperMm) => paperMm <= 58 ? 32 : 48;

  /// Latin-1 only; anything else becomes '?' instead of crashing the print or printing garbage.
  static String printable(String s) => s.replaceAll('×', 'x').replaceAll('\r', '').runes.map((r) => (r < 256 && (r >= 32 || r == 10)) ? String.fromCharCode(r) : (r == 9 ? ' ' : '?')).join();

  /// Word-wraps [text] to [width] columns (hard-breaks a single word longer than the line).
  static List<String> wrap(String text, int width) {
    final out = <String>[];
    for (final para in printable(text).split('\n')) {
      var line = '';
      for (var word in para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
        while (word.length > width) {
          if (line.isNotEmpty) {
            out.add(line);
            line = '';
          }
          out.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          out.add(line);
          line = word;
        }
      }
      out.add(line);
    }
    return out.isEmpty ? [''] : out;
  }

  /// `left` wrapped on the left, `right` flush right on the LAST line of the label (or alone on a new line if it can't fit).
  static List<String> twoColumn(String left, String right, int cols) {
    final r = printable(right);
    final room = cols - r.length - 1;
    if (room < 4) {
      return [...wrap(left, cols), r.padLeft(cols)];
    }
    final lines = wrap(left, room);
    final last = lines.removeLast();
    return [...lines, last.padRight(cols - r.length) + r];
  }

  static Future<List<int>> build({required ReceiptData data, PaperSize paperSize = PaperSize.mm80, int copies = 1, bool openDrawer = false}) async {
    final paperMm = paperSize == PaperSize.mm58 ? 58 : 80;
    final cols = columnsFor(paperMm);
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    final bytes = <int>[];

    void textLines(List<String> lines, {PosAlign align = PosAlign.left, bool bold = false}) {
      for (final l in lines) {
        bytes.addAll(g.text(l, styles: PosStyles(align: align, bold: bold)));
      }
    }

    void row(String label, String value, {bool bold = false}) => textLines(twoColumn(label, value, cols), bold: bold);
    void center(String t, {bool bold = false}) => textLines(wrap(t, cols), align: PosAlign.center, bold: bold);
    void big(String t) {
      // double-width text has half the columns
      for (final l in wrap(t, cols ~/ 2)) {
        bytes.addAll(g.text(l, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
      }
    }

    void one() {
      bytes.addAll(g.reset());
      if (data.banner != null) big('*** ${data.banner} ***');
      if (data.offlineNote != null) center('*** ${data.offlineNote} ***', bold: true);
      if (data.isCopy) center('COPY', bold: true);
      if (data.businessName != null) big(data.businessName!);
      if (data.header != null) center(data.header!);
      if (data.address != null) center(data.address!);
      if (data.taxId != null) center(data.taxId!);
      center('Receipt ${data.receiptNumber}', bold: true);
      if (data.offlineRef != null) center('Offline ref ${data.offlineRef}');
      center(data.dateText);
      if (data.cashier != null) center('Cashier: ${data.cashier}');
      bytes.addAll(g.hr());

      for (final l in data.lines) {
        row(l.name, l.total);
        textLines(wrap('  ${l.qtyAndPrice}${l.note != null ? '  (${l.note})' : ''}', cols));
      }
      bytes.addAll(g.hr());

      row('Subtotal', data.subtotal);
      if (data.discount != null) row(data.discountLabel ?? 'Discount', data.discount!);
      if (data.tax != null) row(data.taxLabel ?? 'Tax', data.tax!);
      bytes.addAll(g.emptyLines(1));
      row('TOTAL', data.total, bold: true);
      bytes.addAll(g.emptyLines(1));
      for (final p in data.payments) {
        row(p.label, p.amount);
        if (p.detail != null) textLines(wrap('  ${p.detail}', cols));
      }
      if (data.change != null) row('Change', data.change!);
      for (final r in data.refunds) {
        row(r.label, r.amount);
      }
      if (data.customer != null) row('Customer', data.customer!);

      if (data.footer != null) {
        bytes.addAll(g.hr());
        center(data.footer!);
      }
      bytes.addAll(g.feed(2));
      bytes.addAll(g.cut());
    }

    if (openDrawer) bytes.addAll(g.drawer()); // kick the cash drawer first so it is open while the receipt prints
    for (var i = 0; i < copies.clamp(1, 5); i++) {
      one();
    }
    return bytes;
  }

  /// A short sheet that proves the connection, the paper width and the wrapping.
  static Future<List<int>> buildTest({PaperSize paperSize = PaperSize.mm80, bool openDrawer = false}) async {
    final paperMm = paperSize == PaperSize.mm58 ? 58 : 80;
    final cols = columnsFor(paperMm);
    final g = Generator(paperSize, await CapabilityProfile.load());
    final b = <int>[];
    b.addAll(g.reset());
    if (openDrawer) b.addAll(g.drawer());
    b.addAll(g.text('Solvexo POS', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    b.addAll(g.text('Test print', styles: const PosStyles(align: PosAlign.center)));
    b.addAll(g.text('Paper: $paperMm mm ($cols columns)', styles: const PosStyles(align: PosAlign.center)));
    b.addAll(g.hr());
    b.addAll(g.text(List.generate(cols, (i) => (i + 1) % 10 == 0 ? '${((i + 1) ~/ 10) % 10}' : '.').join()));
    for (final l in twoColumn('A very long product name that must wrap neatly onto several lines', 'JPY 12,345', cols)) {
      b.addAll(g.text(l));
    }
    for (final l in twoColumn('Total', 'USD 1,234.50', cols)) {
      b.addAll(g.text(l, styles: const PosStyles(bold: true)));
    }
    b.addAll(g.hr());
    b.addAll(g.text('If every line above is complete', styles: const PosStyles(align: PosAlign.center)));
    b.addAll(g.text('and aligned, printing is set up.', styles: const PosStyles(align: PosAlign.center)));
    b.addAll(g.feed(2));
    b.addAll(g.cut());
    return b;
  }
}
