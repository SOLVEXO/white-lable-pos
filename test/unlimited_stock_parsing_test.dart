// The inventory list endpoint used to send `stock: '∞ Unlimited'` (a String) for
// digital / unlimited-stock products; the old `as int?` cast threw, the
// repository swallowed it, and ONE such product blanked the whole screen.
// The backend now also sends typed `isUnlimited` + `stockQuantity`, and the app
// must tolerate either shape. Unlimited variants must also be sellable in POS.

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';

Map<String, dynamic> _row(Map<String, dynamic> over) => {
      'productId': 'p1', 'sku': 'S', 'name': 'Tea', 'stockStatus': 'active', 'variantCount': 1, ...over,
    };

void main() {
  group('InventoryProductSummary.fromJson', () {
    test('legacy string "∞ Unlimited" no longer throws and is flagged unlimited', () {
      final p = InventoryProductSummary.fromJson(_row({'stock': '∞ Unlimited'}));
      expect(p.isUnlimited, isTrue);
      expect(p.stock, 0);
    });

    test('typed fields win: unlimited product has isUnlimited and a null quantity', () {
      final p = InventoryProductSummary.fromJson(_row({'stock': '∞ Unlimited', 'isUnlimited': true, 'stockQuantity': null}));
      expect(p.isUnlimited, isTrue);
    });

    test('a normal tracked product reads its numeric quantity', () {
      final p = InventoryProductSummary.fromJson(_row({'stock': 12, 'isUnlimited': false, 'stockQuantity': 12}));
      expect(p.isUnlimited, isFalse);
      expect(p.stock, 12);
    });

    test('an old backend without the typed fields still parses a numeric stock', () {
      final p = InventoryProductSummary.fromJson(_row({'stock': 7}));
      expect(p.isUnlimited, isFalse);
      expect(p.stock, 7);
    });

    test('a double-typed quantity (JSON number) does not throw', () {
      expect(() => InventoryProductSummary.fromJson(_row({'stock': 3.0, 'stockQuantity': 3.0})), returnsNormally);
    });
  });

  group('PosProductModel unlimited stock', () {
    PosProductModel product(List<Map<String, dynamic>> variants) => PosProductModel.fromJson({
          'productId': 'p1', 'name': 'Tea', 'type': 'physical', 'categoryId': 'c',
          'variants': variants,
        });
    Map<String, dynamic> variant({int stock = 0, bool unlimited = false}) =>
        {'variantId': 'v${stock}_$unlimited', 'sku': 'S', 'price': 5, 'stock': stock, 'unlimitedStock': unlimited, 'isDefault': true};

    test('an unlimited variant with stock 0 is still in stock and addable', () {
      final p = product([variant(unlimited: true)]);
      expect(p.inStock, isTrue);
      expect(p.variants.single.isAvailable, isTrue);
    });

    test('an untracked-out variant (stock 0, not unlimited) is out of stock', () {
      final p = product([variant()]);
      expect(p.isOutOfStock, isTrue);
    });

    test('an unlimited product is never "low stock"', () {
      final p = product([variant(stock: 2, unlimited: true)]);
      expect(p.isLowStock, isFalse);
      expect(p.hasUnlimitedStock, isTrue);
    });

    test('a missing unlimitedStock field defaults to tracked stock (older backend)', () {
      final p = PosProductModel.fromJson({
        'productId': 'p1', 'name': 'Tea', 'categoryId': 'c',
        'variants': [{'variantId': 'v', 'sku': 'S', 'price': 5, 'stock': 3, 'isDefault': true}],
      });
      expect(p.variants.single.unlimitedStock, isFalse);
      expect(p.inStock, isTrue);
    });
  });

  group('InventoryVariant.fromJson', () {
    test('reads unlimitedStock and tolerates a double stock', () {
      final v = InventoryVariant.fromJson({'_id': 'v', 'sku': 'S', 'stock': 4.0, 'unlimitedStock': true});
      expect(v.unlimitedStock, isTrue);
      expect(v.stock, 4);
    });
  });
}
