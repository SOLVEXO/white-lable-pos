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
  });

  int get refundableQty => qty - refundedQty;
  bool get isFullyRefunded => refundedQty >= qty;

  factory PosSaleItemModel.fromJson(Map<String, dynamic> json) =>
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
        price: (json['price'] as num?)?.toDouble() ?? 0,
        lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
        refundedQty: json['refundedQty'] as int? ?? 0,
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
  final String notes;
  final DateTime? heldAt;
  /// completed | held | refunded | voided | partially_refunded
  final String status;
  final DateTime? voidedAt;
  final String? voidedBy;
  final double refundedAmount;
  final DateTime createdAt;

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
    required this.notes,
    this.heldAt,
    required this.status,
    this.voidedAt,
    this.voidedBy,
    this.refundedAmount = 0,
    required this.createdAt,
  });

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

  factory PosSaleModel.fromJson(Map<String, dynamic> json) => PosSaleModel(
        id: json['_id'] as String? ?? '',
        saleNumber: json['saleNumber'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        registerId: json['registerId'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) =>
                    PosSaleItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        paymentMethod: json['paymentMethod'] as String? ?? '',
        customerName: json['customerName'] as String? ?? 'Walk-in',
        customerId: json['customerId'] as String?,
        notes: json['notes'] as String? ?? '',
        heldAt: json['heldAt'] != null
            ? DateTime.tryParse(json['heldAt'] as String)
            : null,
        status: json['status'] as String? ?? '',
        voidedAt: json['voidedAt'] != null
            ? DateTime.tryParse(json['voidedAt'] as String)
            : null,
        voidedBy: json['voidedBy'] as String?,
        refundedAmount: (json['refundedAmount'] as num?)?.toDouble() ?? 0,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
