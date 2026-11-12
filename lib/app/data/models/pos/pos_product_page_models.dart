import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart' show InvCur;

/// G5.2 — the product page at the till (`GET pos/catalog-admin/products/:storeId/:productId`). Money in minor units with the response's currency.
/// [ProductPageVariant.costMinor] is absent for a cashier, and for a manager when the owner hides costs.
class ProductPage {
  const ProductPage({required this.id, required this.name, this.description = '', this.categoryId, this.categoryName, this.status = 'active', this.images = const [], this.variants = const [], this.stockByLocation = const [], this.cur, this.canEdit = false, this.costsHidden = false});
  final String id, name, description, status;
  final String? categoryId, categoryName;
  final List<({String url, String thumbUrl})> images;
  final List<ProductPageVariant> variants;
  final List<({String? locationId, String name, int stock})> stockByLocation;
  final InvCur? cur;
  final bool canEdit, costsHidden;

  factory ProductPage.fromJson(Map<String, dynamic> d) {
    final p = (d['product'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return ProductPage(
      id: '${p['id'] ?? ''}',
      name: p['name'] as String? ?? '',
      description: p['description'] as String? ?? '',
      categoryId: p['categoryId'] as String?,
      categoryName: p['categoryName'] as String?,
      status: p['status'] as String? ?? 'active',
      images: [for (final i in (p['images'] as List? ?? const [])) if (i is Map) (url: '${i['url']}', thumbUrl: '${i['thumbUrl'] ?? i['url']}')],
      variants: [for (final v in (p['variants'] as List? ?? const [])) if (v is Map) ProductPageVariant.fromJson(v.cast<String, dynamic>())],
      stockByLocation: [for (final l in (p['stockByLocation'] as List? ?? const [])) if (l is Map) (locationId: l['locationId'] as String?, name: '${l['name'] ?? 'Location'}', stock: (l['stock'] as num?)?.toInt() ?? 0)],
      cur: InvCur.fromJson(d),
      canEdit: d['canEdit'] == true,
      costsHidden: d['costsHidden'] == true,
    );
  }
}

class ProductPageVariant {
  const ProductPageVariant({required this.id, this.sku, this.barcode, this.options = const [], this.priceMinor = 0, this.costMinor, this.stock = 0, this.unlimitedStock = false, this.reorderPoint, this.status = 'active', this.isDefault = false});
  final String id;
  final String? sku, barcode;
  final List<String> options;
  final int priceMinor, stock;
  final int? costMinor, reorderPoint;
  final bool unlimitedStock, isDefault;
  final String status;
  String get label => options.isEmpty ? (sku ?? 'Default') : options.join(' · ');

  factory ProductPageVariant.fromJson(Map<String, dynamic> v) => ProductPageVariant(
    id: '${v['id'] ?? ''}',
    sku: v['sku'] as String?,
    barcode: v['barcode'] as String?,
    options: [for (final o in (v['options'] as List? ?? const [])) if (o is Map) '${o['value'] ?? ''}'].where((e) => e.isNotEmpty).toList(),
    priceMinor: (v['priceMinor'] as num?)?.toInt() ?? 0,
    costMinor: (v['costMinor'] as num?)?.toInt(),
    stock: (v['stock'] as num?)?.toInt() ?? 0,
    unlimitedStock: v['unlimitedStock'] == true,
    reorderPoint: (v['reorderPoint'] as num?)?.toInt(),
    status: v['status'] as String? ?? 'active',
    isDefault: v['isDefault'] == true,
  );
}
