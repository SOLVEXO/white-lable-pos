// Regression test for the held-sale resume bug flagged in the Phase 0 audit:
// resuming a held sale used to silently drop any line item whose product
// wasn't in the currently-loaded product page (or was since removed), since
// it matched purely against `allProducts`. It now falls back to a synthetic
// product built from the sale item's own snapshot (name/sku/image/price),
// which the backend always includes.

import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

PosSaleItemModel _saleItem({
  required String productId,
  String? variantId,
  required String name,
  required double price,
  required int qty,
}) {
  return PosSaleItemModel(
    saleItemId: '${productId}_item',
    productId: productId,
    variantId: variantId,
    name: name,
    sku: 'SKU-$productId',
    price: price,
    qty: qty,
    lineTotal: price * qty,
  );
}

PosSaleModel _heldSale(List<PosSaleItemModel> items) {
  return PosSaleModel(
    id: 'sale-1',
    saleNumber: 'S-0001',
    storeId: 'store-1',
    sessionId: 'session-1',
    registerId: 'register-1',
    employeeId: 'employee-1',
    items: items,
    discount: 0,
    tax: 0,
    subtotal: items.fold(0.0, (s, i) => s + i.lineTotal),
    total: items.fold(0.0, (s, i) => s + i.lineTotal),
    paymentMethod: 'cash',
    customerName: 'Walk-in',
    notes: '',
    status: 'held',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late PosHomeController c;

  setUp(() {
    c = PosHomeController();
  });

  tearDown(() {
    c.searchController.dispose();
    c.noteController.dispose();
    c.customerController.dispose();
    c.discountController.dispose();
    c.taxController.dispose();
    c.tenderedController.dispose();
    c.paymentReferenceController.dispose();
    c.productScrollController.dispose();
  });

  test('resumes a live product from allProducts by matching productId/variantId', () {
    final liveProduct = PosProductModel(
      productId: 'p1',
      name: 'Live Product',
      type: 'physical',
      categoryId: 'cat-1',
      variants: [
        PosProductVariant(variantId: 'v1', sku: 'SKU-p1', price: 12.0, stock: 5, isDefault: true),
      ],
    );
    c.allProducts.add(liveProduct);

    final sale = _heldSale([_saleItem(productId: 'p1', variantId: 'v1', name: 'Live Product', price: 12.0, qty: 3)]);
    c.resumeHeldSale(sale);

    expect(c.cartItems.length, 1);
    expect(c.cartItems.first.product.name, 'Live Product');
    expect(c.cartItems.first.quantity.value, 3);
    expect(c.cartItems.first.unitPrice, 12.0);
  });

  test('reconstructs a missing product from the sale item snapshot instead of dropping it', () {
    // allProducts is empty — as if this product left the currently-loaded
    // page, or was deleted/edited since the sale was held.
    final sale = _heldSale([
      _saleItem(productId: 'gone-1', variantId: 'gone-1-v1', name: 'Discontinued Widget', price: 7.5, qty: 2),
    ]);

    c.resumeHeldSale(sale);

    expect(c.cartItems.length, 1, reason: 'the item must not be silently dropped');
    final item = c.cartItems.first;
    expect(item.product.name, 'Discontinued Widget');
    expect(item.unitPrice, 7.5, reason: 'must resume at the originally-held price');
    expect(item.quantity.value, 2);
  });

  test('mixed cart: live products keep matching, missing ones fall back, none are dropped', () {
    final liveProduct = PosProductModel(
      productId: 'p1',
      name: 'Live Product',
      type: 'physical',
      categoryId: 'cat-1',
      variants: [PosProductVariant(variantId: 'v1', sku: 'SKU-p1', price: 20.0, stock: 5, isDefault: true)],
    );
    c.allProducts.add(liveProduct);

    final sale = _heldSale([
      _saleItem(productId: 'p1', variantId: 'v1', name: 'Live Product', price: 20.0, qty: 1),
      _saleItem(productId: 'gone-1', name: 'Gone Product', price: 9.0, qty: 4),
    ]);

    c.resumeHeldSale(sale);

    expect(c.cartItems.length, 2);
    expect(c.subtotal, 20.0 * 1 + 9.0 * 4);
  });
}
