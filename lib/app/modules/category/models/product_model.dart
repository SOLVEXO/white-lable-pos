import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:get/get.dart';

// ─── Variant option (arbitrary seller-defined attribute, e.g. Color/Size) ──────
class VariantOption {
  final String name;
  final String value;

  const VariantOption({required this.name, required this.value});

  factory VariantOption.fromJson(Map<String, dynamic> json) => VariantOption(
    name: json['name'] as String? ?? '',
    value: json['value'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
}

// ─── Variant Model ────────────────────────────────────────────────────────────
class ProductVariant {
  final String id;
  final String productId;
  final String sku;
  final List<VariantOption> options;
  final double price;
  final double? compareAtPrice;
  final int? stock; // null = unlimited
  final bool unlimitedStock; // server-side flag; takes priority over `stock`
  final List<String> images;
  final String status;
  // Server-stamped from the owning Store's baseCurrency at creation time —
  // never client-supplied. Nullable only for pre-backfill legacy rows.
  final String? currency;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.sku,
    this.options = const [],
    required this.price,
    this.compareAtPrice,
    required this.stock,
    this.unlimitedStock = false,
    required this.images,
    required this.status,
    this.currency,
    required this.createdAt,
    required this.updatedAt,
  });

  String? optionValue(String name) => options
      .firstWhereOrNull((o) => o.name.toLowerCase() == name.toLowerCase())
      ?.value;

  // null  → unlimited; int → as-is; "∞"/"unlimited"/"Infinity" → null
  static int? _parseStock(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    final s = raw.toString().trim().toLowerCase();
    if (s.isEmpty || s == '∞' || s.startsWith('∞') ||
        s == 'unlimited' || s == 'infinity' || s == 'infinite') {
      return null;
    }
    return int.tryParse(s);
  }

  bool get isUnlimited => unlimitedStock || stock == null;
  bool get isInStock => isUnlimited || stock! > 0;
  // Large sentinel so qty-cap comparisons work without special-casing nulls
  int get resolvedStock => isUnlimited ? 999999 : (stock ?? 999999);
  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['_id'] ?? json['id'] ?? '',
      productId: json['productId'] ?? '',
      sku: json['sku'] ?? '',
      options: (json['options'] as List? ?? [])
          .map((o) => VariantOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      price: (json['price'] ?? 0).toDouble(),
      compareAtPrice: json['compareAtPrice'] != null
          ? (json['compareAtPrice'] as num).toDouble()
          : null,
      stock: _parseStock(json['stock']),
      unlimitedStock: json['unlimitedStock'] == true,
      images: List<String>.from(json['images'] ?? []),
      status: json['status'] ?? 'active',
      currency: json['currency'] as String?,
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'productId': productId,
      'sku': sku,
      'options': options.map((o) => o.toJson()).toList(),
      'price': price,
      'compareAtPrice': compareAtPrice,
      'stock': stock,
      'unlimitedStock': unlimitedStock,
      'images': images,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

// ─── Active campaign (marketing sale) badge ────────────────────────────────
// Attached server-side (`attachCampaignBadges`, src/products/products.service.ts)
// whenever a platform-sponsored campaign is running (applies to every store)
// or a seller-sponsored campaign this product's store has joined is active —
// null otherwise. Drives the red "sale" tag on the product card.
class ActiveCampaign {
  final String campaignId;
  final String name;
  final String? discountType; // 'percentage' | 'fixed'
  final double? discountValue;
  final DateTime? endDate;

  const ActiveCampaign({
    required this.campaignId,
    required this.name,
    this.discountType,
    this.discountValue,
    this.endDate,
  });

  factory ActiveCampaign.fromJson(Map<String, dynamic> json) {
    return ActiveCampaign(
      campaignId: (json['campaignId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      discountType: json['discountType'] as String?,
      discountValue: (json['discountValue'] as num?)?.toDouble(),
      endDate: json['endDate'] != null
          ? DateTime.tryParse(json['endDate'].toString())
          : null,
    );
  }

  /// e.g. "20% OFF" / "$5 OFF" — falls back to "SALE" when the campaign is
  /// purely promotional (no configured discount).
  String get badgeLabel {
    if (discountValue == null) return 'SALE';
    if (discountType == 'percentage') {
      return '${discountValue!.toStringAsFixed(0)}% OFF';
    }
    if (discountType == 'fixed') {
      return '\$${discountValue!.toStringAsFixed(0)} OFF';
    }
    return 'SALE';
  }
}

// ─── Product Model ────────────────────────────────────────────────────────────
class ProductModel {
  final String id;
  final String name;
  final String sellerId;
  final String slug;
  final String description;
  final String categoryId;
  final CategoryModel? category;
  final List<String> images;
  final List<ProductVariant> variants;
  final String type; // 'physical' | 'digital' | 'educational'

  // Only set when type == 'educational'. See EducationLevel enum values in
  // the backend (`src/products/schemas/product.schema.ts`).
  final String? educationLevel;
  final String? customLevel; // raw seller text, only when educationLevel == 'other'
  final String? normalizedCustomLevel; // server-derived, grouping/filtering only

  // digital.previewAvailable — server-derived, only meaningful when isDigital
  final bool previewAvailable;

  // Seller / store. sellerName/sellerVerified/storeId are batch-attached on
  // every listing endpoint (category, search, shaped-by-ids) as well as
  // product detail (verified against the live search + products-by-category
  // responses) — storeId is what lets a single-store build client-side
  // filter those marketplace-wide listing endpoints down to its own store
  // (see product_controller.dart/search_controller.dart _scopeToCurrentStore).
  // The remaining store* cosmetic fields (slug/name/logo/followers) stay
  // product-detail only.
  final String? sellerName;
  final bool sellerVerified;
  final String? storeId;
  final String? storeSlug;
  final String? storeName;
  final String? storeLogo;
  final int storeFollowersCount;

  // Analytics fields
  final int viewCount;
  final int wishlistCount;
  final int purchaseCount;
  final double averageRating;
  final int totalRatings;

  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Active marketing campaign (platform-wide sale, or a seller sale this
  // product's store joined) — null when nothing is currently running.
  final ActiveCampaign? activeCampaign;

  ProductModel({
    required this.id,
    required this.name,
    required this.sellerId,
    required this.slug,
    required this.description,
    required this.categoryId,
    this.category,
    required this.images,
    required this.variants,
    this.type = 'physical',
    this.educationLevel,
    this.customLevel,
    this.normalizedCustomLevel,
    this.previewAvailable = false,
    required this.viewCount,
    required this.wishlistCount,
    required this.purchaseCount,
    required this.averageRating,
    required this.totalRatings,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sellerName,
    this.sellerVerified = false,
    this.storeId,
    this.storeSlug,
    this.storeName,
    this.storeLogo,
    this.storeFollowersCount = 0,
    this.activeCampaign,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // categoryId can come as a raw string or a populated object
    String categoryId;
    CategoryModel? categoryObj;

    if (json['categoryId'] is String) {
      categoryId = json['categoryId'];
    } else if (json['categoryId'] is Map<String, dynamic>) {
      categoryObj = CategoryModel.fromJson(json['categoryId']);
      categoryId = categoryObj.id;
    } else {
      categoryId = '';
    }

    return ProductModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      sellerId: json['sellerId'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'] ?? '',
      categoryId: categoryId,
      category: categoryObj,
      images: List<String>.from(json['images'] ?? []),
      variants: (json['variants'] as List? ?? [])
          .map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
      type: json['type'] as String? ?? 'physical',
      educationLevel: json['educationLevel'] as String?,
      customLevel: json['customLevel'] as String?,
      normalizedCustomLevel: json['normalizedCustomLevel'] as String?,
      previewAvailable: json['digital'] is Map
          ? (json['digital']['previewAvailable'] == true)
          : false,
      viewCount: json['viewCount'] ?? 0,
      wishlistCount: json['wishlistCount'] ?? 0,
      purchaseCount: json['purchaseCount'] ?? 0,
      averageRating: (json['averageRating'] ?? 0).toDouble(),
      totalRatings: json['totalRatings'] ?? 0,
      status: json['status'] ?? 'active',
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updatedAt'] ?? DateTime.now().toIso8601String(),
      ),
      sellerName: json['sellerName'] as String?,
      sellerVerified: json['sellerVerified'] == true,
      storeId: json['storeId'] as String?,
      storeSlug: json['storeSlug'] as String?,
      storeName: json['storeName'] as String?,
      storeLogo: json['storeLogo'] as String?,
      storeFollowersCount: json['storeFollowersCount'] as int? ?? 0,
      activeCampaign: json['activeCampaign'] is Map
          ? ActiveCampaign.fromJson(json['activeCampaign'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'sellerId': sellerId,
      'slug': slug,
      'description': description,
      'categoryId': categoryId,
      'images': images,
      'variants': variants.map((v) => v.toJson()).toList(),
      'viewCount': viewCount,
      'wishlistCount': wishlistCount,
      'purchaseCount': purchaseCount,
      'averageRating': averageRating,
      'totalRatings': totalRatings,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // ─── Computed helpers (derived from variants) ─────────────────────────────

  /// Cheapest variant price — shown as the "starting from" price
  double get price {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  }

  /// The variant that determines the displayed "starting from" price
  ProductVariant? get _cheapestVariant {
    if (variants.isEmpty) return null;
    return variants.reduce((a, b) => a.price < b.price ? a : b);
  }

  /// Compare-at (original/crossed-out) price of the cheapest variant, if set
  double? get compareAtPrice => _cheapestVariant?.compareAtPrice;

  /// True when the cheapest variant has a real discount to show
  bool get hasDiscount => _cheapestVariant?.hasDiscount ?? false;

  /// Currency of the cheapest variant (server-stamped from the store's
  /// baseCurrency) — null only for pre-backfill legacy rows with no variants.
  String? get currency => _cheapestVariant?.currency;

  /// Most expensive variant price
  double get maxPrice {
    if (variants.isEmpty) return 0.0;
    return variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);
  }

  /// True when there are multiple price points across variants
  bool get hasPriceRange => price != maxPrice;

  bool get isDigital => type.toLowerCase() == 'digital';
  bool get isEducational => type.toLowerCase() == 'educational';
  bool get isOnSale => activeCampaign != null;

  /// Total stock across active variants. Returns 999999 if any variant is unlimited.
  int get stock {
    final active = variants.where((v) => v.status == 'active');
    if (active.any((v) => v.isUnlimited)) return 999999;
    return active.fold(0, (sum, v) => sum + v.stock!);
  }

  /// True when at least one active variant is in stock (or product is digital).
  bool get inStock {
    if (isDigital || isEducational) return true;
    return variants.any((v) => v.status == 'active' && v.isInStock);
  }

  /// True when product and all logic is active
  bool get isActive => status == 'active';

  /// Attribute name → distinct values across all variants, in first-seen order.
  Map<String, List<String>> get availableOptionValues {
    final map = <String, List<String>>{};
    for (final v in variants) {
      for (final o in v.options) {
        map.putIfAbsent(o.name, () => []);
        if (!map[o.name]!.contains(o.value)) map[o.name]!.add(o.value);
      }
    }
    return map;
  }

  /// Get the variant whose full attribute set matches [selections] exactly.
  ProductVariant? findVariant(Map<String, String> selections) {
    return variants.firstWhereOrNull(
      (v) =>
          selections.length == v.options.length &&
          selections.entries.every((e) => v.optionValue(e.key) == e.value),
    );
  }
}

// ─── Education level taxonomy (Tier-1, shared by seller forms + buyer filters) ─
// Mirrors the backend's `EducationLevel` enum exactly
// (`src/products/schemas/product.schema.ts`).
class EducationLevelOption {
  final String value;
  final String label;
  const EducationLevelOption(this.value, this.label);
}

const List<EducationLevelOption> kEducationLevels = [
  EducationLevelOption('preschool', 'Preschool'),
  EducationLevelOption('primary_school', 'Primary School'),
  EducationLevelOption('middle_school', 'Middle School'),
  EducationLevelOption('secondary_school', 'Secondary School'),
  EducationLevelOption('college', 'College'),
  EducationLevelOption('university', 'University'),
  EducationLevelOption('professional_courses', 'Professional Courses'),
  EducationLevelOption('islamic_education', 'Islamic Education'),
  EducationLevelOption('other', 'Other'),
];

String educationLevelLabel(String? value) {
  if (value == null) return '';
  return kEducationLevels
      .firstWhereOrNull((e) => e.value == value)
      ?.label ??
      value;
}

// ─── Education-level facets (buyer filter chips) ──────────────────────────────
class EducationLevelFacet {
  final String level;
  final int count;

  const EducationLevelFacet({required this.level, required this.count});

  factory EducationLevelFacet.fromJson(Map<String, dynamic> json) {
    return EducationLevelFacet(
      level: json['level'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }
}

class EducationOtherLevelFacet {
  final String slug;
  final String displayName;
  final int count;

  const EducationOtherLevelFacet({
    required this.slug,
    required this.displayName,
    required this.count,
  });

  factory EducationOtherLevelFacet.fromJson(Map<String, dynamic> json) {
    return EducationOtherLevelFacet(
      slug: json['slug'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }
}

class EducationFacetsResult {
  final List<EducationLevelFacet> levels;
  final List<EducationOtherLevelFacet> otherLevels;

  const EducationFacetsResult({required this.levels, required this.otherLevels});

  factory EducationFacetsResult.fromJson(Map<String, dynamic> json) {
    return EducationFacetsResult(
      levels: (json['levels'] as List? ?? [])
          .map((e) => EducationLevelFacet.fromJson(e as Map<String, dynamic>))
          .toList(),
      otherLevels: (json['otherLevels'] as List? ?? [])
          .map((e) => EducationOtherLevelFacet.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Response wrapper ─────────────────────────────────────────────────────────
class ProductListResponse {
  final int total;
  final int page;
  final int pages;
  final List<ProductModel> products;

  ProductListResponse({
    required this.total,
    required this.page,
    required this.pages,
    required this.products,
  });

  /// Handles both response shapes:
  ///   • new:  { total, page, limit, products: [...] }   ← products-by-category
  ///   • old:  { success, count, total, page, pages, data: [...] }
  factory ProductListResponse.fromJson(Map<String, dynamic> json) {
    // Determine the products list key
    final rawList = (json['products'] ?? json['data'] ?? []) as List;

    // pages may not exist in the new response — derive it from total + limit
    int total = json['total'] ?? 0;
    int page = int.tryParse(json['page'].toString()) ?? 1;
    int limit = int.tryParse(json['limit'].toString()) ?? 10;
    int pages = json['pages'] ?? (limit > 0 ? (total / limit).ceil() : 1);

    return ProductListResponse(
      total: total,
      page: page,
      pages: pages,
      products: rawList
          .map((p) => ProductModel.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
