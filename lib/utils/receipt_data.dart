import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart' show ReceiptOptions;
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
/// G4.8: what a Code 128 receipt barcode can carry — printable ASCII only, at most 30 characters (null when nothing is left).
String? receiptBarcode(String number) {
  final s = number.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  if (s.isEmpty) return null;
  return s.length > 30 ? s.substring(0, 30) : s;
}

/// G4.9: the receipt link a till can build with no network — the store's link base (from the cached settings) + the sale's client key. The server
/// answers "receipt is syncing" until the sale arrives, then the receipt. Null when either part is missing or the key is not a till key.
String? offlineReceiptLink(PosSettingsModel? settings, String? clientKey) {
  final base = settings?.receiptLinkBase;
  if (base == null || base.isEmpty || clientKey == null || !RegExp(r'^pos-\d{13,17}-[0-9a-f]{24}$').hasMatch(clientKey)) return null;
  return base.endsWith('/') ? '$base$clientKey' : '$base/$clientKey';
}

/// G5.1: the QR a receipt PRINTS — only ever the server-provided base (cached with the store settings) + the sale's client key. No base cached →
/// no QR (logged), never a guessed or hard-coded URL and never another link.
String? printedReceiptQr(PosSettingsModel? settings, String? clientKey) {
  if (!(settings?.receiptOptions.showQr ?? true)) return null;
  final link = offlineReceiptLink(settings, clientKey);
  if (link == null) debugPrint('receipt QR skipped: ${settings?.receiptLinkBase == null ? 'no receipt link base from the server is cached' : 'the sale has no client key'}');
  return link;
}

/// G4.4: the receipt's closing text — the owner's promotion line (receipt designer) above the footer; null when there is neither.
String? receiptFooterText(PosSettingsModel? settings, String? Function(String?) clean) {
  final parts = [clean(settings?.receiptOptions.promoText), clean(settings?.receiptFooter)].whereType<String>();
  return parts.isEmpty ? null : parts.join('\n');
}

class ReceiptData {
  final String? businessName;
  final String? header;
  final String? address;
  final String? taxId;
  final String receiptNumber;
  final String dateText;
  final String? cashier;
  /// null when the owner's receipt designer hides the customer's name
  final String? customer;
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

  /// G4.8: the server's reprint number — printed "REPRINT #n" instead of "COPY" (null = not recorded, e.g. offline)
  final int? reprintNumber;

  /// G4.8 receipt designer: the QR (the public digital-receipt link, when the till has it), the receipt-number barcode, the points of this sale
  final String? qrPayload;

  /// the designer's QR switch (the link itself may arrive later: the success screen loads it after the sale)
  final bool qrWanted;
  final String? barcodeData;
  final int? pointsEarned, pointsRedeemed;

  /// G4.9: the customer's points balance after the sale (when the server returned it) — printed INSTEAD of earned / redeemed
  final int? pointsBalance;
  final String? footer;

  /// Offline sales (Q7): the receipt of a sale that is still only on this device carries a PROVISIONAL number
  /// (`OFF-<device>-<seq>`) and this note; it is never the server's receipt number. After the sale syncs, [offlineRef]
  /// keeps the provisional number on the real receipt so a customer holding the offline paper can be matched to it.
  final String? offlineNote;
  final String? offlineRef;
  /// G5.5: the tax authority's invoice number + QR once confirmed; [fiscalPending] → "Fiscal pending" (store fiscalises, not confirmed yet)
  final String? fiscalNumber;
  final String? fiscalQr;
  final bool fiscalPending;
  /// G5.6: the store's receipt logo (only when the designer's logo switch is on); the printer uses the till's cached bitmap of it
  final String? logoUrl;

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
    this.reprintNumber,
    this.qrPayload,
    this.qrWanted = false,
    this.barcodeData,
    this.pointsEarned,
    this.pointsRedeemed,
    this.pointsBalance,
    this.footer,
    this.offlineNote,
    this.offlineRef,
    this.saleId,
    this.fiscalNumber,
    this.fiscalQr,
    this.fiscalPending = false,
    this.logoUrl,
  });

  /// The note printed on a provisional (not yet synced) receipt.
  static const offlinePendingNote = 'OFFLINE - PENDING SYNC';

  ReceiptData copyWith({String? receiptNumber, bool? isCopy, String? offlineNote, bool clearOfflineNote = false, String? offlineRef, int? reprintNumber, String? qrPayload}) => ReceiptData(
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
        reprintNumber: reprintNumber ?? this.reprintNumber,
        qrPayload: qrPayload ?? this.qrPayload,
        qrWanted: qrWanted,
        barcodeData: barcodeData,
        pointsEarned: pointsEarned,
        pointsRedeemed: pointsRedeemed,
        pointsBalance: pointsBalance,
        footer: footer,
        offlineNote: clearOfflineNote ? null : (offlineNote ?? this.offlineNote),
        offlineRef: offlineRef ?? this.offlineRef,
        saleId: saleId,
        fiscalNumber: fiscalNumber,
        fiscalQr: fiscalQr,
        fiscalPending: fiscalPending,
        logoUrl: logoUrl,
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
        if (reprintNumber != null) 'reprintNumber': reprintNumber,
        if (qrPayload != null) 'qrPayload': qrPayload,
        if (qrWanted) 'qrWanted': true,
        if (barcodeData != null) 'barcodeData': barcodeData,
        if (pointsEarned != null) 'pointsEarned': pointsEarned,
        if (pointsRedeemed != null) 'pointsRedeemed': pointsRedeemed,
        if (pointsBalance != null) 'pointsBalance': pointsBalance,
        if (footer != null) 'footer': footer,
        if (offlineNote != null) 'offlineNote': offlineNote,
        if (offlineRef != null) 'offlineRef': offlineRef,
        if (fiscalNumber != null) 'fiscalNumber': fiscalNumber,
        if (fiscalQr != null) 'fiscalQr': fiscalQr,
        if (fiscalPending) 'fiscalPending': true,
        if (logoUrl != null) 'logoUrl': logoUrl,
      };

  factory ReceiptData.fromJson(Map<String, dynamic> j) => ReceiptData(
        businessName: j['businessName'] as String?,
        header: j['header'] as String?,
        address: j['address'] as String?,
        taxId: j['taxId'] as String?,
        receiptNumber: j['receiptNumber'] as String,
        dateText: j['dateText'] as String,
        cashier: j['cashier'] as String?,
        customer: j['customer'] as String?,
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
        reprintNumber: (j['reprintNumber'] as num?)?.toInt(),
        qrPayload: j['qrPayload'] as String?,
        qrWanted: j['qrWanted'] == true,
        barcodeData: j['barcodeData'] as String?,
        pointsEarned: (j['pointsEarned'] as num?)?.toInt(),
        pointsRedeemed: (j['pointsRedeemed'] as num?)?.toInt(),
        pointsBalance: (j['pointsBalance'] as num?)?.toInt(),
        footer: j['footer'] as String?,
        offlineNote: j['offlineNote'] as String?,
        offlineRef: j['offlineRef'] as String?,
        fiscalNumber: j['fiscalNumber'] as String?,
        fiscalQr: j['fiscalQr'] as String?,
        fiscalPending: j['fiscalPending'] == true,
        logoUrl: j['logoUrl'] as String?,
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
    String? receiptUrl, // G4.8: the public digital-receipt link — printed as a QR when the designer's switch is on
    String? clientKey, // G4.9: the sale's client key when the caller has it (defaults to the one the server returned on the sale)
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

    final o = settings?.receiptOptions ?? const ReceiptOptions();
    return ReceiptData(
      businessName: clean(settings?.businessName),
      header: clean(settings?.receiptHeader),
      address: o.showStoreAddress ? clean(settings?.businessAddress) : null,
      taxId: o.showTaxId ? clean(settings?.businessTaxId) : null,
      receiptNumber: sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
      dateText: DateFormat('yyyy-MM-dd HH:mm').format(sale.createdAt.toLocal()),
      cashier: o.showCashierName ? clean(sale.employeeName) : null,
      customer: o.showCustomerName ? (sale.customerName.isEmpty ? 'Walk-in' : sale.customerName) : null,
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
      taxLabel: sale.tax > 0 ? (taxPct != null && o.showTaxBreakdown ? 'Tax ($taxPct)' : 'Tax') : null,
      tax: sale.tax > 0 ? m(sale.tax) : null,
      total: m(sale.total),
      payments: payments,
      change: sale.changeGiven > 0 ? m(sale.changeGiven) : null,
      refunds: refunds,
      totalRefunded: sale.refundedAmount > 0 ? m(sale.refundedAmount) : null,
      banner: banner,
      isCopy: isCopy,
      footer: receiptFooterText(settings, clean),
      offlineRef: offlineRef,
      saleId: sale.id.isEmpty ? null : sale.id,
      fiscalNumber: sale.invoice?.fiscalConfirmed == true ? sale.invoice!.fiscalNumber : null,
      fiscalQr: sale.invoice?.fiscalConfirmed == true ? sale.invoice!.fiscalQr : null,
      fiscalPending: sale.invoice?.fiscalPending == true,
      logoUrl: settings?.receiptLogoUrlToPrint,
      // G4.8 receipt designer switches (defaults: QR on, barcode off, points on)
      // G4.9: the offline-built link first (the same QR online or offline, at checkout and on reprint); the token link only for a sale without a client key
      // G5.1: only the server-provided base + client key (no fallback to any other link — [receiptUrl] is no longer printed)
      qrPayload: printedReceiptQr(settings, clientKey ?? sale.clientKey),
      qrWanted: settings?.receiptOptions.showQr ?? true,
      barcodeData: (settings?.receiptOptions.showBarcode ?? false) ? receiptBarcode(sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id) : null,
      // G4.9: the balance after the sale when the server stored it; otherwise what this sale earned / redeemed (G4.8)
      pointsBalance: (settings?.receiptOptions.showLoyaltyBalance ?? true) ? sale.loyaltyBalanceAfterPoints : null,
      pointsEarned: (settings?.receiptOptions.showLoyaltyBalance ?? true) && sale.loyaltyBalanceAfterPoints == null && (sale.loyalty?.earnedPoints ?? 0) > 0 ? sale.loyalty!.earnedPoints : null,
      pointsRedeemed: (settings?.receiptOptions.showLoyaltyBalance ?? true) && sale.loyaltyBalanceAfterPoints == null && (sale.loyalty?.redeemedPoints ?? 0) > 0 ? sale.loyalty!.redeemedPoints : null,
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
    String? clientKey, // G4.9: the queued sale's client key → the receipt QR (resolves to "syncing", then the receipt)
    bool fiscalPending = false, // G5.5: the store fiscalises → an offline receipt is always "Fiscal pending"
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
      address: (settings?.receiptOptions.showStoreAddress ?? true) ? clean(settings?.businessAddress) : null,
      taxId: (settings?.receiptOptions.showTaxId ?? true) ? clean(settings?.businessTaxId) : null,
      receiptNumber: provisionalNumber,
      dateText: DateFormat('yyyy-MM-dd HH:mm').format(madeAt.toLocal()),
      cashier: (settings?.receiptOptions.showCashierName ?? true) ? clean(cashier) : null,
      customer: (settings?.receiptOptions.showCustomerName ?? true) ? (customer.trim().isEmpty ? 'Walk-in' : customer.trim()) : null,
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
      footer: receiptFooterText(settings, clean),
      offlineNote: offlinePendingNote,
      fiscalPending: fiscalPending,
      logoUrl: settings?.receiptLogoUrlToPrint,
      qrPayload: printedReceiptQr(settings, clientKey),
      qrWanted: settings?.receiptOptions.showQr ?? true,
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
