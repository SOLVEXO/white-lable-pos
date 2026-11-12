import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart' show ChosenModifier;
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/utils/money_json.dart';
class PosSaleItemModel {
  /// Sale-item subdocument id — required to target a specific line for a
  /// partial refund (POST /pos/sales/:saleId/refund { items: [{saleItemId}] }).
  final String? saleItemId;
  final String productId;
  final String? variantId;
  final String name;
  final String? sku;
  final String? image;
  final int qty;
  final double price;
  final double lineTotal;
  final int refundedQty;

  /// G2.5: the line's value excluding tax and its tax (minor units), the PCT/HS code snapshot, and the custom-item flags.
  final int? netMinor;
  final int? taxMinor;
  final String? hsCode;
  final bool isCustom;

  /// G3.2: the lots this line was taken from (empty for an item that is not lot-tracked) and whether any of it came from an EXPIRED lot.
  final List<SaleLot> lots;
  final bool soldExpired;

  /// G4.5: the options sold with this line (priced by the server) and, when options or a price book applied, the base unit price in minor units
  final List<ChosenModifier> modifiers;
  final int? basePriceMinor;

  const PosSaleItemModel({
    this.saleItemId,
    required this.productId,
    this.variantId,
    required this.name,
    this.sku,
    this.image,
    required this.qty,
    required this.price,
    required this.lineTotal,
    this.refundedQty = 0,
    this.netMinor,
    this.taxMinor,
    this.hsCode,
    this.isCustom = false,
    this.lots = const [],
    this.soldExpired = false,
    this.modifiers = const [],
    this.basePriceMinor,
  });

  int get refundableQty => qty - refundedQty;
  bool get isFullyRefunded => refundedQty >= qty;

  factory PosSaleItemModel.fromJson(Map<String, dynamic> json, {int? exp}) =>
      PosSaleItemModel(
        saleItemId: json['_id'] as String?,
        productId: json['productId'] as String? ?? '',
        variantId: json['variantId'] as String?,
        // Backend snapshots the line name under "name"; keep a defensive
        // fallback to the old (incorrect) "productName" key just in case.
        name: json['name'] as String? ?? json['productName'] as String? ?? '',
        sku: json['sku'] as String?,
        image: json['image'] as String?,
        qty: json['qty'] as int? ?? 1,
        price: MoneyJson.read(json, 'price', exp: exp),
        lineTotal: MoneyJson.read(json, 'lineTotal', exp: exp),
        refundedQty: json['refundedQty'] as int? ?? 0,
        netMinor: (json['netMinor'] as num?)?.toInt(),
        taxMinor: (json['taxMinor'] as num?)?.toInt(),
        hsCode: json['hsCode'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
        lots: [for (final l in (json['lots'] as List? ?? const [])) if (l is Map) SaleLot.fromJson(l.cast<String, dynamic>())],
        soldExpired: json['soldExpired'] == true,
        modifiers: [for (final m in (json['modifiers'] as List? ?? const [])) if (m is Map) ChosenModifier.fromJson(m.cast<String, dynamic>())],
        basePriceMinor: (json['basePriceMinor'] as num?)?.toInt(),
      );
}

/// One tender taken for a sale. [amount] is what was applied to the total (cash net of change);
/// for cash [tendered] is what the customer handed over.
class PosPaymentLine {
  final String method; // cash | card | other
  final double amount;
  final double? tendered;
  final String? reference;

  const PosPaymentLine({required this.method, required this.amount, this.tendered, this.reference});

  factory PosPaymentLine.fromJson(Map<String, dynamic> json, {int? exp}) => PosPaymentLine(
        method: json['method'] as String? ?? 'other',
        amount: MoneyJson.read(json, 'amount', exp: exp),
        tendered: MoneyJson.readNullable(json, 'tendered', exp: exp),
        reference: json['reference'] as String?,
      );
}

/// A reason the server flagged a (synced offline) sale for a manager to look at.
class PosSaleFlag {
  final String type;
  final Map<String, dynamic> detail;
  const PosSaleFlag({required this.type, this.detail = const {}});

  factory PosSaleFlag.fromJson(Map<String, dynamic> j) =>
      PosSaleFlag(type: j['type'] as String? ?? '', detail: (j['detail'] as Map?)?.cast<String, dynamic>() ?? const {});

  /// Plain-language explanation for the manager.
  String get description {
    switch (type) {
      case 'oversold_on_sync':
        return 'Sold ${detail['requested']} of ${detail['sku'] ?? 'an item'} but only ${detail['available']} were in stock — stock is now negative. Recount and correct it.';
      case 'price_changed_while_offline':
        return 'The price changed while the till was offline: charged ${detail['deviceTotal']}, current price total is ${detail['serverTotal']}.';
      case 'payment_shortfall':
        return 'The customer paid ${detail['shortBy']} less than the current price total (${detail['serverTotal']}).';
      case 'expired_lot_sold_offline':
        return 'Sold from an expired lot while offline. Check the stock and the expiry dates.';
      case 'lots_short':
        return 'Not enough lot stock recorded for this sale. Check the lots of the items sold.';
      default:
        return type.replaceAll('_', ' ');
    }
  }
}

/// One refund event against a sale (what came back, and to which tenders).
class PosRefundRecord {
  final double amount;
  final String kind; // full | partial
  final List<PosPaymentLine> tenders;
  final DateTime? createdAt;

  const PosRefundRecord({required this.amount, required this.kind, this.tenders = const [], this.createdAt});

  factory PosRefundRecord.fromJson(Map<String, dynamic> json, {int? exp}) => PosRefundRecord(
        amount: MoneyJson.read(json, 'amount', exp: exp),
        kind: json['kind'] as String? ?? 'partial',
        tenders: (json['tenders'] as List<dynamic>?)?.map((e) => PosPaymentLine.fromJson(e as Map<String, dynamic>, exp: exp ?? (json['currencyExponent'] as num?)?.toInt())).toList() ?? const [],
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}

class PosSaleModel {
  final String id;
  final String saleNumber;
  final String storeId;
  final String sessionId;
  final String registerId;
  final String employeeId;
  final List<PosSaleItemModel> items;
  final double discount;
  final double tax;
  final double subtotal;
  final double total;
  final String paymentMethod;
  final String customerName;
  final String? customerId;

  /// G4.5: the price book the server priced this sale with (picked at checkout or the customer's own), null for normal prices
  final String? priceBookName;
  final String notes;
  final DateTime? heldAt;
  /// completed | held | refunded | voided | partially_refunded
  final String status;
  final DateTime? voidedAt;
  final String? voidedBy;
  final double refundedAmount;
  final DateTime createdAt;

  /// Currency snapshot taken when the sale was made, and its minor-unit exponent (JPY 0, USD 2, KWD 3).
  /// The backend always sends one (older sales are backfilled from the store).
  final String currency;
  final int currencyExponent;

  /// Tender lines — empty for held sales and for sales made before split tender (see [paymentLines]).
  final List<PosPaymentLine> payments;
  final double changeGiven;
  final String? employeeName;

  /// What the cashier entered for the discount, and the tax rate the server applied.
  final String? discountType; // amount | percent
  final double? discountValue;
  final double? taxRate;
  final List<PosRefundRecord> refunds;

  /// Offline sync: why a manager should look at this sale (oversold, price changed, shortfall), and whether it still needs it.
  final bool needsReview;
  final List<PosSaleFlag> flags;
  final bool isOffline;

  /// G2.5 tax invoice header (null on a held sale and on sales that predate it) and the coupon CODE a held sale remembers (G2.4).
  final PosInvoiceInfo? invoice;
  final String? heldCouponCode;

  /// G3.3: points earned / redeemed on this sale (null when the sale had no customer or the store has no loyalty).
  final SaleLoyalty? loyalty;

  /// G4.9: the till's client key for this sale (its idempotency key, made when Charge was first tapped) — with the store's link base it is the
  /// receipt QR, buildable offline. Null on sales rung up without one.
  final String? clientKey;

  /// G4.9: the customer's points balance right after this sale, when the server stored it (online customer sales); else the receipt prints earned / redeemed.
  final int? loyaltyBalanceAfterPoints;

  const PosSaleModel({
    required this.id,
    required this.saleNumber,
    required this.storeId,
    required this.sessionId,
    required this.registerId,
    required this.employeeId,
    required this.items,
    required this.discount,
    required this.tax,
    required this.subtotal,
    required this.total,
    required this.paymentMethod,
    required this.customerName,
    this.customerId,
    this.priceBookName,
    required this.notes,
    this.heldAt,
    required this.status,
    this.voidedAt,
    this.voidedBy,
    this.refundedAmount = 0,
    required this.createdAt,
    this.currency = 'USD',
    this.currencyExponent = 2,
    this.payments = const [],
    this.changeGiven = 0,
    this.employeeName,
    this.discountType,
    this.discountValue,
    this.taxRate,
    this.refunds = const [],
    this.needsReview = false,
    this.flags = const [],
    this.isOffline = false,
    this.invoice,
    this.heldCouponCode,
    this.loyalty,
    this.clientKey,
    this.loyaltyBalanceAfterPoints,
  });

  /// The tender lines to show: the stored ones, or — for a sale made before split tender — one synthetic line.
  List<PosPaymentLine> get paymentLines =>
      payments.isNotEmpty ? payments : [PosPaymentLine(method: paymentMethod == 'split' ? 'other' : paymentMethod, amount: total)];
  bool get isSplit => paymentLines.map((l) => l.method).toSet().length > 1;

  bool get isHeld => status == 'held';
  bool get isCompleted => status == 'completed';
  bool get isRefunded => status == 'refunded';
  bool get isVoided => status == 'voided';
  bool get isPartiallyRefunded => status == 'partially_refunded';

  /// Mirrors the backend's voidSale guard: only a still-fully-completed,
  /// non-refunded sale can be voided.
  bool get canVoid => status == 'completed';
  /// Mirrors refundSale: completed or already-partially-refunded sales.
  bool get canRefund => status == 'completed' || status == 'partially_refunded';
  bool get canDiscard => status == 'held';
  bool get canComplete => status == 'held';

  factory PosSaleModel.fromJson(Map<String, dynamic> json) {
    final exp = (json['currencyExponent'] as num?)?.toInt() ?? 2;
    return PosSaleModel(
        id: json['_id'] as String? ?? '',
        saleNumber: json['saleNumber'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        registerId: json['registerId'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) =>
                    PosSaleItemModel.fromJson(e as Map<String, dynamic>, exp: exp))
                .toList() ??
            [],
        discount: MoneyJson.read(json, 'discount', exp: exp),
        tax: MoneyJson.read(json, 'tax', exp: exp),
        subtotal: MoneyJson.read(json, 'subtotal', exp: exp),
        total: MoneyJson.read(json, 'total', exp: exp),
        paymentMethod: json['paymentMethod'] as String? ?? '',
        customerName: json['customerName'] as String? ?? 'Walk-in',
        customerId: json['customerId'] as String?,
        priceBookName: json['priceBookName'] as String?,
        notes: json['notes'] as String? ?? '',
        heldAt: json['heldAt'] != null
            ? DateTime.tryParse(json['heldAt'] as String)
            : null,
        status: json['status'] as String? ?? '',
        voidedAt: json['voidedAt'] != null
            ? DateTime.tryParse(json['voidedAt'] as String)
            : null,
        voidedBy: json['voidedBy'] as String?,
        refundedAmount: MoneyJson.read(json, 'refundedAmount', exp: exp),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        currency: (json['currency'] as String?)?.toUpperCase() ?? 'USD',
        currencyExponent: (json['currencyExponent'] as num?)?.toInt() ?? 2,
        payments: (json['payments'] as List<dynamic>?)?.map((e) => PosPaymentLine.fromJson(e as Map<String, dynamic>, exp: exp)).toList() ?? const [],
        changeGiven: MoneyJson.read(json, 'changeGiven', exp: exp),
        employeeName: json['employeeName'] as String?,
        discountType: json['discountType'] as String?,
        discountValue: json['discountType'] == 'amount' ? MoneyJson.readNullable(json, 'discountValue', exp: exp) : (json['discountValue'] as num?)?.toDouble(),
        taxRate: (json['taxRate'] as num?)?.toDouble(),
        refunds: (json['refunds'] as List<dynamic>?)?.map((e) => PosRefundRecord.fromJson(e as Map<String, dynamic>, exp: exp)).toList() ?? const [],
        needsReview: json['needsReview'] as bool? ?? false,
        flags: (json['flags'] as List<dynamic>?)?.map((e) => PosSaleFlag.fromJson((e as Map).cast<String, dynamic>())).toList() ?? const [],
        isOffline: json['isOffline'] as bool? ?? false,
        invoice: json['invoice'] is Map ? PosInvoiceInfo.fromJson((json['invoice'] as Map).cast<String, dynamic>()) : null,
        heldCouponCode: json['heldCouponCode'] as String?,
        loyalty: json['loyalty'] is Map ? SaleLoyalty.fromJson((json['loyalty'] as Map).cast<String, dynamic>()) : null,
        clientKey: json['idempotencyKey'] as String?,
        loyaltyBalanceAfterPoints: (json['loyaltyBalanceAfterPoints'] as num?)?.toInt(),
    );
  }
}


/// The tax-invoice header of a completed sale: its immutable per-store number, the issue date, the seller as registered.
class PosInvoiceInfo {
  final String number;
  final DateTime? issuedAt;
  final String? offlineRef;
  final String? sellerName;
  final String? sellerAddress;
  final String? sellerNtn;
  final String? sellerStrn;
  /// G5.5: the fiscal block (`not_enabled` / `pending` / `confirmed` / `rejected`), the tax authority's number and QR once confirmed
  final String fiscalStatus;
  final String? fiscalNumber;
  final String? fiscalQr;
  const PosInvoiceInfo({required this.number, this.issuedAt, this.offlineRef, this.sellerName, this.sellerAddress, this.sellerNtn, this.sellerStrn, this.fiscalStatus = 'not_enabled', this.fiscalNumber, this.fiscalQr});
  bool get fiscalConfirmed => fiscalStatus == 'confirmed' && fiscalNumber != null;
  bool get fiscalPending => fiscalStatus == 'pending';

  factory PosInvoiceInfo.fromJson(Map<String, dynamic> j) {
    final s = (j['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosInvoiceInfo(
      number: j['number'] as String? ?? '',
      issuedAt: j['issuedAt'] != null ? DateTime.tryParse(j['issuedAt'].toString()) : null,
      offlineRef: j['offlineRef'] as String?,
      sellerName: s['legalName'] as String?,
      sellerAddress: s['address'] as String?,
      sellerNtn: s['ntn'] as String?,
      sellerStrn: s['strn'] as String?,
      fiscalStatus: (j['fiscal'] is Map ? (j['fiscal'] as Map)['status'] as String? : null) ?? 'not_enabled',
      fiscalNumber: j['fiscal'] is Map ? (j['fiscal'] as Map)['externalInvoiceNumber'] as String? : null,
      fiscalQr: j['fiscal'] is Map ? (j['fiscal'] as Map)['qrPayload'] as String? : null,
    );
  }
}

/// What the sale did to the customer's points (the sale's discount and total already include any redemption).
class SaleLoyalty {
  const SaleLoyalty({this.earnedPoints = 0, this.redeemedPoints = 0, this.redeemValueMinor = 0});
  final int earnedPoints, redeemedPoints, redeemValueMinor;

  factory SaleLoyalty.fromJson(Map<String, dynamic> j) => SaleLoyalty(
    earnedPoints: (j['earnedPoints'] as num?)?.toInt() ?? 0,
    redeemedPoints: (j['redeemedPoints'] as num?)?.toInt() ?? 0,
    redeemValueMinor: (j['redeemValueMinor'] as num?)?.toInt() ?? 0,
  );
}
