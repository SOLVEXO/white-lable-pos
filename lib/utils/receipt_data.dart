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

  Map<String, dynamic> toJson() => {'name': name, 'qtyAndPrice': qtyAndPrice, 'total': total, if (note != null) 'note': note};
  factory ReceiptLine.fromJson(Map<String, dynamic> j) =>
      ReceiptLine(name: j['name'] as String, qtyAndPrice: j['qtyAndPrice'] as String, total: j['total'] as String, note: j['note'] as String?);
}

class ReceiptPaymentRow {
  final String label; // "Card", "Cash"
  final String amount;
  final String? detail; // "Ref AUTH-77" / "Tendered $50.00"
  const ReceiptPaymentRow({required this.label, required this.amount, this.detail});

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount, if (detail != null) 'detail': detail};
  factory ReceiptPaymentRow.fromJson(Map<String, dynamic> j) =>
      ReceiptPaymentRow(label: j['label'] as String, amount: j['amount'] as String, detail: j['detail'] as String?);
}

class ReceiptRefundRow {
  final String label;
  final String amount;
  const ReceiptRefundRow({required this.label, required this.amount});

  Map<String, dynamic> toJson() => {'label': label, 'amount': amount};
  factory ReceiptRefundRow.fromJson(Map<String, dynamic> j) => ReceiptRefundRow(label: j['label'] as String, amount: j['amount'] as String);
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

  /// Offline sales (Q7): the receipt of a sale that is still only on this device carries a PROVISIONAL number
  /// (`OFF-<device>-<seq>`) and this note; it is never the server's receipt number. After the sale syncs, [offlineRef]
  /// keeps the provisional number on the real receipt so a customer holding the offline paper can be matched to it.
  final String? offlineNote;
  final String? offlineRef;

  /// The server's sale id (null for a provisional offline receipt): the digital receipt link is asked for with it.
  final String? saleId;

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
    this.offlineNote,
    this.offlineRef,
    this.saleId,
  });

  /// The note printed on a provisional (not yet synced) receipt.
  static const offlinePendingNote = 'OFFLINE - PENDING SYNC';

  ReceiptData copyWith({String? receiptNumber, bool? isCopy, String? offlineNote, bool clearOfflineNote = false, String? offlineRef}) => ReceiptData(
        businessName: businessName,
        header: header,
        address: address,
        taxId: taxId,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        dateText: dateText,
        cashier: cashier,
        customer: customer,
        lines: lines,
        subtotal: subtotal,
        discountLabel: discountLabel,
        discount: discount,
        taxLabel: taxLabel,
        tax: tax,
        total: total,
        payments: payments,
        change: change,
        refunds: refunds,
        totalRefunded: totalRefunded,
        banner: banner,
        isCopy: isCopy ?? this.isCopy,
        footer: footer,
        offlineNote: clearOfflineNote ? null : (offlineNote ?? this.offlineNote),
        offlineRef: offlineRef ?? this.offlineRef,
        saleId: saleId,
      );

  Map<String, dynamic> toJson() => {
        if (businessName != null) 'businessName': businessName,
        if (header != null) 'header': header,
        if (address != null) 'address': address,
        if (taxId != null) 'taxId': taxId,
        'receiptNumber': receiptNumber,
        'dateText': dateText,
        if (cashier != null) 'cashier': cashier,
        'customer': customer,
        'lines': [for (final l in lines) l.toJson()],
        'subtotal': subtotal,
        if (discountLabel != null) 'discountLabel': discountLabel,
        if (discount != null) 'discount': discount,
        if (taxLabel != null) 'taxLabel': taxLabel,
        if (tax != null) 'tax': tax,
        'total': total,
        'payments': [for (final p in payments) p.toJson()],
        if (change != null) 'change': change,
        'refunds': [for (final r in refunds) r.toJson()],
        if (totalRefunded != null) 'totalRefunded': totalRefunded,
        if (banner != null) 'banner': banner,
        'isCopy': isCopy,
        if (footer != null) 'footer': footer,
        if (offlineNote != null) 'offlineNote': offlineNote,
        if (offlineRef != null) 'offlineRef': offlineRef,
      };

  factory ReceiptData.fromJson(Map<String, dynamic> j) => ReceiptData(
        businessName: j['businessName'] as String?,
        header: j['header'] as String?,
        address: j['address'] as String?,
        taxId: j['taxId'] as String?,
        receiptNumber: j['receiptNumber'] as String,
        dateText: j['dateText'] as String,
        cashier: j['cashier'] as String?,
        customer: j['customer'] as String,
        lines: [for (final l in (j['lines'] as List)) ReceiptLine.fromJson(Map<String, dynamic>.from(l as Map))],
        subtotal: j['subtotal'] as String,
        discountLabel: j['discountLabel'] as String?,
        discount: j['discount'] as String?,
        taxLabel: j['taxLabel'] as String?,
        tax: j['tax'] as String?,
        total: j['total'] as String,
        payments: [for (final p in (j['payments'] as List)) ReceiptPaymentRow.fromJson(Map<String, dynamic>.from(p as Map))],
        change: j['change'] as String?,
        refunds: [for (final r in (j['refunds'] as List? ?? const [])) ReceiptRefundRow.fromJson(Map<String, dynamic>.from(r as Map))],
        totalRefunded: j['totalRefunded'] as String?,
        banner: j['banner'] as String?,
        isCopy: j['isCopy'] as bool? ?? true,
        footer: j['footer'] as String?,
        offlineNote: j['offlineNote'] as String?,
        offlineRef: j['offlineRef'] as String?,
      );

  /// How a refund slice is handed back, per tender.
  static String refundHow(String m) => switch (m) { 'cash' => 'cash returned', 'card' => 'to card', 'raast_qr' => 'to Raast', 'store_credit' => 'to store credit', _ => 'bank / other' };

  static String methodLabel(String m) => switch (m) { 'cash' => 'Cash', 'card' => 'Card', 'raast_qr' => 'Raast', 'store_credit' => 'Store credit', _ => 'Bank / Other' };

  /// [asciiSafeMoney]: thermal printers can't print most currency symbols, so amounts are written as
  /// `JPY 1,234` instead of `¥1,234`.
  factory ReceiptData.fromSale(
    PosSaleModel sale,
    PosSettingsModel? settings, {
    bool isCopy = true,
    bool asciiSafeMoney = false,
    String? offlineRef,
  }) {
    final code = sale.currency;
    final exp = sale.currencyExponent;
    String m(num v) => asciiSafeMoney
        ? '$code ${NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: exp).format(Money.round(v, exp))}'
        : Money.format(v, currency: code, exponent: exp);

    String? clean(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

    final taxPct = sale.taxRate != null ? '${(sale.taxRate! * 100).toStringAsFixed((sale.taxRate! * 100) % 1 == 0 ? 0 : 2)}%' : null;
    final discLabel = sale.discount > 0
        ? ((sale.loyalty?.redeemedPoints ?? 0) > 0 ? 'Points redeemed (${sale.loyalty!.redeemedPoints})' : sale.discountType == 'percent' && sale.discountValue != null ? 'Discount (${sale.discountValue!.toStringAsFixed(sale.discountValue! % 1 == 0 ? 0 : 1)}%)' : 'Discount')
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
      offlineRef: offlineRef,
      saleId: sale.id.isEmpty ? null : sale.id,
    );
  }

  /// The receipt for a sale rung up while offline, built from what the till had on screen (the server has not priced
  /// it yet). It carries the provisional number and [offlinePendingNote]; amounts follow the sale currency, ASCII-safe for
  /// thermal printers like the online print.
  factory ReceiptData.forOfflineSale({
    required String provisionalNumber,
    required DateTime madeAt,
    PosSettingsModel? settings,
    required String currency,
    required int exponent,
    required List<({String name, int qty, double unitPrice})> items,
    required double subtotal,
    required double discount,
    String? discountLabel,
    String? taxLabel,
    required double tax,
    required double total,
    required List<({String method, double amount, String? reference})> payments,
    double? cashTendered,
    required double change,
    String? cashier,
    String customer = 'Walk-in',
  }) {
    String m(num v) => '$currency ${NumberFormat.decimalPatternDigits(locale: 'en_US', decimalDigits: exponent).format(Money.round(v, exponent))}';
    String? clean(String? x) => (x ?? '').trim().isEmpty ? null : x!.trim();
    String? detailOf(({String method, double amount, String? reference}) p) {
      final d = [
        if (p.method == 'cash' && cashTendered != null && cashTendered > p.amount) 'Tendered ${m(cashTendered)}',
        if (clean(p.reference) != null) 'Ref ${p.reference!.trim()}',
      ];
      return d.isEmpty ? null : d.join(' · ');
    }

    return ReceiptData(
      businessName: clean(settings?.businessName),
      header: clean(settings?.receiptHeader),
      address: clean(settings?.businessAddress),
      taxId: clean(settings?.businessTaxId),
      receiptNumber: provisionalNumber,
      dateText: DateFormat('yyyy-MM-dd HH:mm').format(madeAt.toLocal()),
      cashier: clean(cashier),
      customer: customer.trim().isEmpty ? 'Walk-in' : customer.trim(),
      lines: [for (final i in items) ReceiptLine(name: i.name, qtyAndPrice: '${i.qty} × ${m(i.unitPrice)}', total: m(i.unitPrice * i.qty))],
      subtotal: m(subtotal),
      discountLabel: discount > 0 ? (discountLabel ?? 'Discount') : null,
      discount: discount > 0 ? '-${m(discount)}' : null,
      taxLabel: tax > 0 ? (taxLabel ?? 'Tax') : null,
      tax: tax > 0 ? m(tax) : null,
      total: m(total),
      payments: [
        for (final p in payments)
          ReceiptPaymentRow(label: methodLabel(p.method), amount: m(p.amount), detail: detailOf(p)),
      ],
      change: change > 0 ? m(change) : null,
      isCopy: false,
      footer: clean(settings?.receiptFooter),
      offlineNote: offlinePendingNote,
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
    if (offlineNote != null) b.writeln(center('*** $offlineNote ***'));
    if (isCopy) b.writeln(center('COPY'));
    if (businessName != null) b.writeln(center(businessName!));
    if (header != null) b.writeln(center(header!));
    if (address != null) b.writeln(center(address!));
    if (taxId != null) b.writeln(center(taxId!));
    b.writeln(center('Receipt $receiptNumber'));
    if (offlineRef != null) b.writeln(center('Offline ref $offlineRef'));
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
