import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/utils/money.dart';

class ReceiptLine {
  final String name;
  final String qtyAndPrice; // "2 × $5.00"
  final String total;
  final String? note; // "1 refunded"
  const ReceiptLine({required this.name, required this.qtyAndPrice, required this.total, this.note});
}

class ReceiptPaymentRow {
  final String label; // "Card", "Cash"
  final String amount;
  final String? detail; // "Ref AUTH-77" / "Tendered $50.00"
  const ReceiptPaymentRow({required this.label, required this.amount, this.detail});
}

class ReceiptRefundRow {
  final String label;
  final String amount;
  const ReceiptRefundRow({required this.label, required this.amount});
}

/// Everything a receipt shows, computed ONCE from the sale + store settings — the PDF, the thermal (ESC/POS)
/// print and the shared text are all rendered from this one object, so they can never disagree. All amounts are
/// already formatted in the SALE's own currency and decimals (JPY has no cents, KWD has three).
class ReceiptData {
  final String? businessName;
  final String? header;
  final String? address;
  final String? taxId;
  final String receiptNumber;
  final String dateText;
  final String? cashier;
  final String customer;
  final List<ReceiptLine> lines;
  final String subtotal;
  final String? discountLabel;
  final String? discount;
  final String? taxLabel;
  final String? tax;
  final String total;
  final List<ReceiptPaymentRow> payments;
  final String? change;
  final List<ReceiptRefundRow> refunds;
  final String? totalRefunded;

  /// "VOID", "REFUNDED" or "PARTIALLY REFUNDED" — null for a normal sale.
  final String? banner;

  /// Printed on every reprint ("COPY") so a copy is never mistaken for the original.
  final bool isCopy;
  final String? footer;

  const ReceiptData({
    this.businessName,
    this.header,
    this.address,
    this.taxId,
    required this.receiptNumber,
    required this.dateText,
    this.cashier,
    required this.customer,
    required this.lines,
    required this.subtotal,
    this.discountLabel,
    this.discount,
    this.taxLabel,
    this.tax,
    required this.total,
    required this.payments,
    this.change,
    this.refunds = const [],
    this.totalRefunded,
    this.banner,
    this.isCopy = true,
    this.footer,
  });

  /// How a refund slice is handed back, per tender.
  static String refundHow(String m) => switch (m) { 'cash' => 'cash returned', 'card' => 'to card', _ => 'bank / other' };

  static String methodLabel(String m) => switch (m) { 'cash' => 'Cash', 'card' => 'Card', _ => 'Bank / Other' };

  /// [asciiSafeMoney]: thermal printers can't print most currency symbols, so amounts are written as
  /// `JPY 1,234` instead of `¥1,234`.
  factory ReceiptData.fromSale(
    PosSaleModel sale,
    PosSettingsModel? settings, {
    bool isCopy = true,
    bool asciiSafeMoney = false,
  }) {
    final code = sale.currency;
    final exp = sale.currencyExponent;
    String m(num v) => asciiSafeMoney
        ? '$code ${NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: exp).format(Money.round(v, exp))}'
        : Money.format(v, currency: code, exponent: exp);

    String? clean(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

    final taxPct = sale.taxRate != null ? '${(sale.taxRate! * 100).toStringAsFixed((sale.taxRate! * 100) % 1 == 0 ? 0 : 2)}%' : null;
    final discLabel = sale.discount > 0
        ? (sale.discountType == 'percent' && sale.discountValue != null ? 'Discount (${sale.discountValue!.toStringAsFixed(sale.discountValue! % 1 == 0 ? 0 : 1)}%)' : 'Discount')
        : null;

    final payments = <ReceiptPaymentRow>[];
    if (!sale.isHeld) {
      for (final p in sale.paymentLines) {
        final details = <String>[
          if (p.method == 'cash' && p.tendered != null && p.tendered! > p.amount) 'Tendered ${m(p.tendered!)}',
          if (clean(p.reference) != null) 'Ref ${p.reference!.trim()}',
        ];
        payments.add(ReceiptPaymentRow(label: methodLabel(p.method), amount: m(p.amount), detail: details.isEmpty ? null : details.join(' · ')));
      }
    }

    final refunds = <ReceiptRefundRow>[];
    if (sale.refunds.isNotEmpty) {
      // one row per TENDER per refund event, saying what was done with it — the cash row is exactly what left the drawer
      for (final r in sale.refunds) {
        final prefix = r.kind == 'full' ? 'Refund' : 'Partial refund';
        if (r.tenders.isEmpty) {
          refunds.add(ReceiptRefundRow(label: prefix, amount: '-${m(r.amount)}'));
        } else {
          for (final t in r.tenders) {
            refunds.add(ReceiptRefundRow(label: '$prefix — ${refundHow(t.method)}', amount: '-${m(t.amount)}'));
          }
        }
      }
    } else if (sale.refundedAmount > 0) {
      refunds.add(ReceiptRefundRow(label: 'Refunded', amount: '-${m(sale.refundedAmount)}')); // refunded before refund records existed
    }

    final banner = sale.isVoided
        ? 'VOID'
        : sale.isRefunded
            ? 'REFUNDED'
            : sale.isPartiallyRefunded
                ? 'PARTIALLY REFUNDED'
                : null;

    return ReceiptData(
      businessName: clean(settings?.businessName),
      header: clean(settings?.receiptHeader),
      address: clean(settings?.businessAddress),
      taxId: clean(settings?.businessTaxId),
      receiptNumber: sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
      dateText: DateFormat('yyyy-MM-dd HH:mm').format(sale.createdAt.toLocal()),
      cashier: clean(sale.employeeName),
      customer: sale.customerName.isEmpty ? 'Walk-in' : sale.customerName,
      lines: [
        for (final i in sale.items)
          ReceiptLine(
            name: i.name,
            qtyAndPrice: '${i.qty} × ${m(i.price)}',
            total: m(i.lineTotal),
            note: i.refundedQty > 0 ? '${i.refundedQty} refunded' : null,
          ),
      ],
      subtotal: m(sale.subtotal),
      discountLabel: discLabel,
      discount: sale.discount > 0 ? '-${m(sale.discount)}' : null,
      taxLabel: sale.tax > 0 ? (taxPct != null ? 'Tax ($taxPct)' : 'Tax') : null,
      tax: sale.tax > 0 ? m(sale.tax) : null,
      total: m(sale.total),
      payments: payments,
      change: sale.changeGiven > 0 ? m(sale.changeGiven) : null,
      refunds: refunds,
      totalRefunded: sale.refundedAmount > 0 ? m(sale.refundedAmount) : null,
      banner: banner,
      isCopy: isCopy,
      footer: clean(settings?.receiptFooter),
    );
  }

  /// Plain-text rendering (for the OS share sheet), [width] columns wide.
  String toPlainText({int width = 32}) {
    final b = StringBuffer();
    String center(String s) => s.length >= width ? s : '${' ' * ((width - s.length) ~/ 2)}$s';
    String row(String l, String r) {
      final gap = width - l.length - r.length;
      return gap >= 1 ? '$l${' ' * gap}$r' : '$l\n${' ' * (width - r.length)}$r';
    }

    if (banner != null) b.writeln(center('*** $banner ***'));
    if (isCopy) b.writeln(center('COPY'));
    if (businessName != null) b.writeln(center(businessName!));
    if (header != null) b.writeln(center(header!));
    if (address != null) b.writeln(center(address!));
    if (taxId != null) b.writeln(center(taxId!));
    b.writeln(center('Receipt $receiptNumber'));
    b.writeln(center(dateText));
    if (cashier != null) b.writeln(center('Cashier: $cashier'));
    b.writeln('-' * width);
    for (final l in lines) {
      b.writeln(row(l.name, l.total));
      b.writeln('  ${l.qtyAndPrice}${l.note != null ? '  (${l.note})' : ''}');
    }
    b.writeln('-' * width);
    b.writeln(row('Subtotal', subtotal));
    if (discount != null) b.writeln(row(discountLabel ?? 'Discount', discount!));
    if (tax != null) b.writeln(row(taxLabel ?? 'Tax', tax!));
    b.writeln(row('TOTAL', total));
    for (final p in payments) {
      b.writeln(row(p.label, p.amount));
      if (p.detail != null) b.writeln('  ${p.detail}');
    }
    if (change != null) b.writeln(row('Change', change!));
    for (final r in refunds) {
      b.writeln(row(r.label, r.amount));
    }
    b.writeln('Customer: $customer');
    if (footer != null) {
      b.writeln('-' * width);
      b.writeln(center(footer!));
    }
    return b.toString();
  }
}
