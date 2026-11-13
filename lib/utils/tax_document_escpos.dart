import 'package:solvexo_pos/utils/fiscal_print.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';

/// One printed line of a tax document, independent of the printer: the same list is turned into ESC/POS bytes AND into plain text for the
/// layout snapshot tests (so the 58 mm and 80 mm layouts are pinned without a printer).
class DocLine {
  const DocLine(this.text, {this.align = PosAlign.left, this.bold = false, this.big = false}) : kind = DocLineKind.text;
  const DocLine.rule() : text = '', align = PosAlign.left, bold = false, big = false, kind = DocLineKind.rule;
  const DocLine.blank() : text = '', align = PosAlign.left, bold = false, big = false, kind = DocLineKind.blank;
  const DocLine.qr(this.text) : align = PosAlign.center, bold = false, big = false, kind = DocLineKind.qr;
  final String text;
  final PosAlign align;
  final bool bold;
  final bool big;
  final DocLineKind kind;
  bool get isRule => kind == DocLineKind.rule;
  bool get isBlank => kind == DocLineKind.blank;
  bool get isQr => kind == DocLineKind.qr;
}

enum DocLineKind { text, rule, blank, qr }

/// G6.1 — the fiscal band of a printed document, from the server's contract (FISCAL_CONTRACT.md) via [FiscalPrint]: each display line as given
/// (label line + bold value), the QR under the totals, the authority logo (from the till's logo cache). Empty → nothing printed.
class FiscalSlots {
  const FiscalSlots({this.invoiceNumber, this.qrPayload, this.logo, this.pending = false, this.print});
  factory FiscalSlots.of(FiscalPrint p) => FiscalSlots(print: p, qrPayload: p.qr);
  /// legacy (G5.5) fields — used only when [print] is null
  final String? invoiceNumber;
  final bool pending;
  final String? qrPayload;
  final List<int>? logo;
  final FiscalPrint? print;
  FiscalPrint get effective => print ??
      FiscalPrint(
        lines: invoiceNumber != null ? [FiscalLine('', invoiceNumber!)] : (pending ? const [FiscalLine('', FiscalPrint.pendingText)] : const []),
        qr: qrPayload,
      );
}

/// The thermal layouts of the three documents that are not the sale receipt: tax invoice, credit note and return receipt. Same layout rules as
/// [ReceiptEscPosBuilder]: characters per paper width (58 mm = 32, 80 mm = 48), long names wrap, amounts flush right, nothing cut off.
/// Amounts are written `PKR 1,234.00` (printers cannot print most currency symbols).
class TaxDocumentEscPos {
  static String _money(int minor, String currency, int exp) {
    final v = minor / (exp <= 0 ? 1 : List.filled(exp, 10).fold<num>(1, (a, b) => a * b));
    return '$currency ${NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: exp).format(v)}';
  }

  static String _tender(String m) => switch (m) { 'cash' => 'Cash', 'card' => 'Card', 'raast_qr' => 'Raast', 'store_credit' => 'Store credit', _ => 'Bank / Other' };

  /// [taxIds]: the server's labelled seller tax identifiers (G6.1; older servers → NTN / STRN from the model)
  static List<DocLine> _seller(int cols, {String? name, String? address, List<FiscalLine> taxIds = const []}) => [
        if ((name ?? '').isNotEmpty) ..._centered(name!, cols ~/ 2, bold: true, big: true),
        if ((address ?? '').isNotEmpty) ..._centered(address!, cols),
        for (final t in taxIds) ..._centered(t.label.isEmpty ? t.value : '${t.label} ${t.value}', cols),
      ];

  static List<DocLine> _centered(String t, int width, {bool bold = false, bool big = false}) =>
      [for (final l in ReceiptEscPosBuilder.wrap(t, width)) DocLine(l, align: PosAlign.center, bold: bold, big: big)];

  static List<DocLine> _two(String l, String r, int cols, {bool bold = false}) => [for (final x in ReceiptEscPosBuilder.twoColumn(l, r, cols)) DocLine(x, bold: bold)];

  static List<DocLine> _wrapped(String t, int cols, {String indent = ''}) => [for (final l in ReceiptEscPosBuilder.wrap(t, cols - indent.length)) DocLine('$indent$l')];

  static List<DocLine> _fiscalNumber(FiscalSlots f) => [
        for (final l in f.effective.lines) ...[
          if (l.label.isNotEmpty) DocLine(l.label, align: PosAlign.center),
          DocLine(l.value, align: PosAlign.center, bold: true),
        ],
      ];

  static List<DocLine> _fiscalQr(FiscalSlots f) => f.effective.qr == null ? const [] : [const DocLine.blank(), DocLine.qr(f.effective.qr!)];

  /// G4.8 / G4.9: which print this is — the server's ORIGINAL (the first print), REPRINT #n, or COPY (offline: it could not be recorded).
  static List<DocLine> _printLabel(int? reprintNumber, {required bool original, required bool copy}) {
    final t = reprintNumber != null && reprintNumber > 0 ? 'REPRINT #$reprintNumber' : original ? 'ORIGINAL' : copy ? 'COPY' : null;
    return t == null ? const [] : [DocLine(t, align: PosAlign.center, bold: true)];
  }

  static List<DocLine> invoice(PosSaleModel sale, {required int cols, FiscalSlots fiscal = const FiscalSlots(), String? storeName, int? reprintNumber, bool original = false, bool copy = false}) {
    final inv = sale.invoice;
    final exp = sale.currencyExponent;
    String m(int minor) => _money(minor, sale.currency, exp);
    int minorOf(double v) => (v * (exp <= 0 ? 1 : List.filled(exp, 10).fold<num>(1, (a, b) => a * b))).round();
    final when = DateFormat('yyyy-MM-dd HH:mm').format((inv?.issuedAt ?? sale.createdAt).toLocal());
    return [
      ..._seller(cols, name: inv?.sellerName ?? storeName, address: inv?.sellerAddress, taxIds: inv?.sellerTaxLines ?? const []),
      const DocLine.rule(),
      DocLine('TAX INVOICE', align: PosAlign.center, bold: true),
      ..._printLabel(reprintNumber, original: original, copy: copy),
      DocLine(inv?.number ?? sale.saleNumber, align: PosAlign.center, bold: true),
      ..._fiscalNumber(fiscal),
      if (inv?.offlineRef != null) DocLine('Offline ref ${inv!.offlineRef}', align: PosAlign.center),
      DocLine(when, align: PosAlign.center),
      const DocLine.rule(),
      for (final i in sale.items) ...[
        ..._two(i.name, m(minorOf(i.lineTotal)), cols),
        ..._wrapped('${i.qty} x ${m(minorOf(i.price))}${i.hsCode != null ? '  HS ${i.hsCode}' : ''}', cols, indent: '  '),
        if (i.netMinor != null && i.taxMinor != null) ...[..._two('  excl. tax', m(i.netMinor!), cols), ..._two('  tax', m(i.taxMinor!), cols)],
      ],
      const DocLine.rule(),
      ..._two('Subtotal', m(minorOf(sale.subtotal)), cols),
      if (sale.discount > 0) ..._two((sale.loyalty?.redeemedPoints ?? 0) > 0 ? 'Points (${sale.loyalty!.redeemedPoints})' : 'Discount', '-${m(minorOf(sale.discount))}', cols),
      ..._two('Sales tax', m(minorOf(sale.tax)), cols),
      const DocLine.blank(),
      ..._two('TOTAL', m(minorOf(sale.total)), cols, bold: true),
      const DocLine.blank(),
      for (final p in sale.payments) ..._two(_tender(p.method), m(minorOf(p.amount)), cols),
      ..._fiscalQr(fiscal),
    ];
  }

  static List<DocLine> creditNote(PosCreditNote n, {required int cols, FiscalSlots fiscal = const FiscalSlots(), String? storeName, int? reprintNumber, bool original = false, bool copy = false}) {
    String m(int minor) => _money(minor, n.currency, n.exponent);
    final when = n.createdAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(n.createdAt!.toLocal());
    return [
      ..._seller(cols, name: n.sellerName ?? storeName, address: n.sellerAddress, taxIds: n.sellerTaxLines),
      const DocLine.rule(),
      DocLine('CREDIT NOTE', align: PosAlign.center, bold: true),
      ..._printLabel(reprintNumber, original: original, copy: copy),
      DocLine(n.number, align: PosAlign.center, bold: true),
      ..._fiscalNumber(fiscal),
      if (n.invoiceNumber != null) ..._centered('Against invoice ${n.invoiceNumber}', cols),
      if (when.isNotEmpty) DocLine(when, align: PosAlign.center),
      const DocLine.rule(),
      for (final l in n.lines) ...[
        ..._two('${l.name} x${l.qty}', m(l.totalMinor), cols),
        if (l.hsCode != null) ..._wrapped('HS ${l.hsCode}', cols, indent: '  '),
        ..._two('  excl. tax', m(l.netMinor), cols),
        ..._two('  tax', m(l.taxMinor), cols),
      ],
      const DocLine.rule(),
      ..._two('Value excl. tax', m(n.netMinor), cols),
      ..._two('Tax reversed', m(n.taxMinor), cols),
      const DocLine.blank(),
      ..._two('CREDITED', m(n.totalMinor), cols, bold: true),
      const DocLine.blank(),
      if (n.tenders.isNotEmpty) const DocLine('Refunded to', bold: true),
      for (final t in n.tenders) ..._two(_tender(t.method), m(t.amountMinor), cols),
      ..._fiscalQr(fiscal),
    ];
  }

  /// The slip handed to the customer with their refund: what came back, how much, how it was paid out. No tax columns (the credit note has them).
  static List<DocLine> returnReceipt(PosCreditNote n, {required int cols, String? storeName, String? saleNumber}) {
    String m(int minor) => _money(minor, n.currency, n.exponent);
    final when = n.createdAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(n.createdAt!.toLocal());
    return [
      ..._seller(cols, name: n.sellerName ?? storeName),
      const DocLine.rule(),
      DocLine(n.kind == 'void' ? 'SALE VOIDED' : 'RETURN RECEIPT', align: PosAlign.center, bold: true),
      DocLine('Credit note ${n.number}', align: PosAlign.center),
      if (n.invoiceNumber != null || saleNumber != null) ..._centered('Sale ${n.invoiceNumber ?? saleNumber}', cols),
      if (when.isNotEmpty) DocLine(when, align: PosAlign.center),
      const DocLine.rule(),
      for (final l in n.lines) ..._two('${l.name} x${l.qty}', m(l.totalMinor), cols),
      const DocLine.rule(),
      ..._two('REFUND', m(n.totalMinor), cols, bold: true),
      if (n.tenders.isNotEmpty) const DocLine.blank(),
      for (final t in n.tenders) ..._two(_tender(t.method), m(t.amountMinor), cols),
      if ((n.reason ?? '').isNotEmpty) ...[const DocLine.blank(), ..._wrapped('Reason: ${n.reason}', cols)],
      const DocLine.blank(),
      DocLine('Keep this slip', align: PosAlign.center),
    ];
  }

  /// Plain text of the layout — what the snapshot tests compare (alignment applied, so what you read is what the paper shows).
  static String render(List<DocLine> lines, int cols) {
    final out = <String>[];
    for (final l in lines) {
      if (l.isRule) {
        out.add('-' * cols);
      } else if (l.isBlank) {
        out.add('');
      } else if (l.isQr) {
        out.add('[QR ${l.text}]'.padLeft((cols + '[QR ${l.text}]'.length) ~/ 2).trimRight());
      } else {
        final t = ReceiptEscPosBuilder.printable(l.text);
        // double-width text uses two columns per character
        final unit = l.big ? 2 : 1;
        final w = cols ~/ unit;
        final shown = t.length > w ? t.substring(0, w) : t;
        final pad = switch (l.align) { PosAlign.center => (w - shown.length) ~/ 2, PosAlign.right => w - shown.length, _ => 0 };
        out.add('${' ' * (pad * unit)}$shown');
      }
    }
    return '${out.join('\n')}\n';
  }

  /// ESC/POS bytes for [lines] on [paperSize], cut at the end.
  static Future<List<int>> bytes(List<DocLine> lines, {PaperSize paperSize = PaperSize.mm80, bool openDrawer = false}) async {
    final g = Generator(paperSize, await CapabilityProfile.load());
    final b = <int>[];
    b.addAll(g.reset());
    if (openDrawer) b.addAll(g.drawer());
    for (final l in lines) {
      if (l.isRule) {
        b.addAll(g.hr());
      } else if (l.isBlank) {
        b.addAll(g.emptyLines(1));
      } else if (l.isQr) {
        b.addAll(g.qrcode(l.text, size: QRSize.size5));
      } else {
        b.addAll(g.text(ReceiptEscPosBuilder.printable(l.text), styles: PosStyles(align: l.align, bold: l.bold || l.big, height: l.big ? PosTextSize.size2 : PosTextSize.size1, width: l.big ? PosTextSize.size2 : PosTextSize.size1)));
      }
    }
    b.addAll(g.feed(2));
    b.addAll(g.cut());
    return b;
  }
}
