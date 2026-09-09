/// Aggregate counts from `GET /api/inventory/getStoreInventory/:storeId`.
class InventoryStats {
  final int totalProducts;
  final int inStock;
  final int lowStock;
  final int outOfStock;

  const InventoryStats({
    required this.totalProducts,
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
  });

  factory InventoryStats.fromJson(Map<String, dynamic>? json) => InventoryStats(
        totalProducts: json?['totalProducts'] as int? ?? 0,
        inStock: json?['inStock'] as int? ?? 0,
        lowStock: json?['lowStock'] as int? ?? 0,
        outOfStock: json?['outOfStock'] as int? ?? 0,
      );
}

/// One row of `GET /api/inventory/getStoreInventory/:storeId` — an
/// aggregate view across all of a product's variants (not a single
/// variant), since that's what the endpoint returns. Adjusting stock
/// requires fetching the product's actual variants first (see
/// InventoryRepository.getProductVariants) when [variantCount] > 1.
class InventoryProductSummary {
  final String productId;
  final String sku;
  final String name;
  final int stock;
  final String stockStatus;
  final double? price;
  final double? minPrice;
  final double? maxPrice;
  final int variantCount;

  const InventoryProductSummary({
    required this.productId,
    required this.sku,
    required this.name,
    required this.stock,
    required this.stockStatus,
    this.price,
    this.minPrice,
    this.maxPrice,
    required this.variantCount,
  });

  bool get hasSingleVariant => variantCount <= 1;

  factory InventoryProductSummary.fromJson(Map<String, dynamic> json) => InventoryProductSummary(
        productId: json['productId'] as String? ?? json['_id'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        name: json['name'] as String? ?? '',
        stock: json['stock'] as int? ?? 0,
        stockStatus: json['stockStatus'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble(),
        minPrice: (json['minPrice'] as num?)?.toDouble(),
        maxPrice: (json['maxPrice'] as num?)?.toDouble(),
        variantCount: json['variantCount'] as int? ?? 1,
      );
}

/// One row of `GET /api/inventory/low-stock-summary/:storeId`.
class LowStockItem {
  final String productId;
  final String name;
  final int stock;

  const LowStockItem({required this.productId, required this.name, required this.stock});

  factory LowStockItem.fromJson(Map<String, dynamic> json) => LowStockItem(
        productId: json['productId'] as String? ?? json['_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        stock: json['stock'] as int? ?? 0,
      );
}

/// `GET /api/inventory/low-stock-summary/:storeId` response — carries the
/// store's *actual* configured threshold (`store.lowStockThreshold ?? 10`
/// server-side), rather than the hardcoded `<=10` the Quick Sale badge uses.
class LowStockSummary {
  final int count;
  final int threshold;
  final List<LowStockItem> items;

  const LowStockSummary({required this.count, required this.threshold, required this.items});

  factory LowStockSummary.fromJson(Map<String, dynamic> json) => LowStockSummary(
        count: json['count'] as int? ?? 0,
        threshold: json['threshold'] as int? ?? 10,
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => LowStockItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// One variant of a product, as returned by
/// `GET /api/products/:productId/variants` — used to pick which variant to
/// adjust when a product has more than one (the inventory list only has
/// aggregate stock, not a per-variant breakdown).
class InventoryVariant {
  final String variantId;
  final String sku;
  final String? barcode;
  final int stock;
  final bool isDefault;
  final String label;

  const InventoryVariant({
    required this.variantId,
    required this.sku,
    this.barcode,
    required this.stock,
    required this.isDefault,
    required this.label,
  });

  factory InventoryVariant.fromJson(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>? ?? [])
        .map((o) => (o as Map<String, dynamic>)['value'] as String? ?? '')
        .where((v) => v.isNotEmpty)
        .join(' / ');
    return InventoryVariant(
      variantId: json['_id'] as String? ?? json['variantId'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      barcode: json['barcode'] as String?,
      stock: json['stock'] as int? ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
      label: options.isNotEmpty ? options : (json['sku'] as String? ?? ''),
    );
  }
}

/// One entry of `GET /api/activity-log/:storeId` — used here filtered to
/// `action=inventory_adjusted` for a store-wide stock-activity feed (the
/// seller route has no targetId filter, so this can't be scoped to a single
/// product server-side — see InventoryRepository.getStockActivity).
class ActivityLogEntry {
  final String id;
  final String actorName;
  final String action;
  final String description;
  final DateTime createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.actorName,
    required this.action,
    required this.description,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) => ActivityLogEntry(
        id: json['_id'] as String? ?? '',
        actorName: json['actorName'] as String? ?? '',
        action: json['action'] as String? ?? '',
        description: json['description'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
