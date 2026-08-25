import 'package:solvexo_pos/app/modules/category/models/product_model.dart';
import 'package:get/get.dart';

/// A single purchasable variant of a POS product (e.g. size/color combination).
/// Mirrors the backend's embedded ProductVariant as returned by
/// GET /api/pos/products/:storeId, /products/search and /products/barcode/:storeId/:barcode.
class PosProductVariant {
  final String variantId;
  final String sku;
  final String? barcode;
  final double price;
  final double? compareAtPrice;
  final int stock;
  final List<VariantOption> options;
  final bool isDefault;
  final List<String> images;

  const PosProductVariant({
    required this.variantId,
    required this.sku,
    this.barcode,
    required this.price,
    this.compareAtPrice,
    required this.stock,
    this.options = const [],
    required this.isDefault,
    this.images = const [],
  });

  /// Human-readable label for a variant picker, e.g. "Large / Blue".
  String get label {
    final parts = options.map((o) => o.value).where((p) => p.isNotEmpty);
    return parts.isNotEmpty ? parts.join(' / ') : sku;
  }

  factory PosProductVariant.fromJson(Map<String, dynamic> json) =>
      PosProductVariant(
        variantId: json['variantId'] as String? ?? json['_id'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        barcode: json['barcode'] as String?,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        compareAtPrice: (json['compareAtPrice'] as num?)?.toDouble(),
        stock: json['stock'] as int? ?? 0,
        options: (json['options'] as List? ?? [])
            .map((o) => VariantOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        isDefault: json['isDefault'] as bool? ?? false,
        images: (json['images'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
}

/// A POS-browsable product (type:'physical' only — the backend excludes
/// digital/service products from POS browse/search/barcode endpoints).
class PosProductModel {
  final String productId;
  final String name;
  final String type;
  final String? image;
  final String categoryId;
  final List<PosProductVariant> variants;

  const PosProductModel({
    required this.productId,
    required this.name,
    required this.type,
    this.image,
    required this.categoryId,
    required this.variants,
  });

  PosProductVariant? get defaultVariant =>
      variants.firstWhereOrNull((v) => v.isDefault) ??
      (variants.isNotEmpty ? variants.first : null);

  bool get hasMultipleVariants => variants.length > 1;
  double get price => defaultVariant?.price ?? 0;
  String get sku => defaultVariant?.sku ?? '';
  int get totalStock => variants.fold(0, (sum, v) => sum + v.stock);
  bool get inStock => variants.any((v) => v.stock > 0);
  bool get isOutOfStock => !inStock;
  bool get isLowStock => !isOutOfStock && totalStock <= 10;

  String? get displayImage {
    if (image != null && image!.isNotEmpty) return image;
    final variantImages = defaultVariant?.images ?? const [];
    return variantImages.isNotEmpty ? variantImages.first : null;
  }

  /// Matches a variant by id, or the default variant if [variantId] is null.
  PosProductVariant? variantById(String? variantId) {
    if (variantId == null) return defaultVariant;
    return variants.firstWhereOrNull((v) => v.variantId == variantId) ?? defaultVariant;
  }

  factory PosProductModel.fromJson(Map<String, dynamic> json) =>
      PosProductModel(
        productId: json['productId'] as String? ?? json['_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'physical',
        image: json['image'] as String?,
        categoryId: json['categoryId'] as String? ?? '',
        variants: (json['variants'] as List<dynamic>?)
                ?.map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Builds a single-variant product from a barcode-lookup response, which
  /// returns `{ productId, name, type, image, variant: {...} }` (singular).
  factory PosProductModel.fromBarcodeJson(Map<String, dynamic> json) =>
      PosProductModel(
        productId: json['productId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'physical',
        image: json['image'] as String?,
        categoryId: json['categoryId'] as String? ?? '',
        variants: json['variant'] != null
            ? [PosProductVariant.fromJson(json['variant'] as Map<String, dynamic>)]
            : const [],
      );
}
