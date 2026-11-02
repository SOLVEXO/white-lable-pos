import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

/// Renders a [ReceiptData] as raw ESC/POS bytes for a thermal printer. Build the data with
/// `asciiSafeMoney: true` (amounts as `JPY 1,234`, not `¥1,234`) — printers can't print most currency symbols —
/// and text is additionally reduced to what the default code page can print.
class ReceiptEscPosBuilder {
  /// Latin-1 only; anything else becomes '?' instead of crashing the print or printing garbage.
  static String _printable(String s) => s.replaceAll('×', 'x').runes.map((r) => r < 256 ? String.fromCharCode(r) : '?').join();

  static Future<List<int>> build({required ReceiptData data, PaperSize paperSize = PaperSize.mm80}) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(paperSize, profile);
    final bytes = <int>[];

    void row(String label, String value, {bool bold = false}) {
      bytes.addAll(g.row([
        PosColumn(text: _printable(label), width: 7, styles: PosStyles(bold: bold)),
        PosColumn(text: _printable(value), width: 5, styles: PosStyles(bold: bold, align: PosAlign.right)),
      ]));
    }

    void center(String t, {bool bold = false, PosTextSize size = PosTextSize.size1}) =>
        bytes.addAll(g.text(_printable(t), styles: PosStyles(align: PosAlign.center, bold: bold, height: size, width: size)));

    bytes.addAll(g.reset());
    if (data.banner != null) center('*** ${data.banner} ***', bold: true, size: PosTextSize.size2);
    if (data.isCopy) center('COPY', bold: true);
    if (data.businessName != null) center(data.businessName!, bold: true, size: PosTextSize.size2);
    if (data.header != null) center(data.header!);
    if (data.address != null) center(data.address!);
    if (data.taxId != null) center(data.taxId!);
    center('Receipt ${data.receiptNumber}', bold: true);
    center(data.dateText);
    if (data.cashier != null) center('Cashier: ${data.cashier}');
    bytes.addAll(g.hr());

    for (final l in data.lines) {
      row(l.name, l.total);
      bytes.addAll(g.text(_printable('  ${l.qtyAndPrice}${l.note != null ? '  (${l.note})' : ''}')));
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
      if (p.detail != null) bytes.addAll(g.text(_printable('  ${p.detail}')));
    }
    if (data.change != null) row('Change', data.change!);
    for (final r in data.refunds) {
      row(r.label, r.amount);
    }
    row('Customer', data.customer);

    if (data.footer != null) {
      bytes.addAll(g.hr());
      center(data.footer!);
    }
    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }
}
