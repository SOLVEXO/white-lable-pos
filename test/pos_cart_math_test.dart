// Unit tests for PosHomeController's cart math: subtotal, discount (flat +
// percent, clamped so it can never exceed the subtotal), tax, total, and
// cash tendered/change due. These are pure getters over Rx state, so the
// controller is constructed directly (no Get.put/onInit) and exercised
// without any network/SharedPreferences access.

import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

PosProductModel _product({required String id, required double price, int stock = 10}) {
  return PosProductModel(
    productId: id,
    name: 'Product $id',
    type: 'physical',
    categoryId: 'cat-1',
    variants: [
      PosProductVariant(
        variantId: '${id}_v1',
        sku: 'SKU-$id',
        price: price,
        stock: stock,
        isDefault: true,
      ),
    ],
  );
}

void main() {
  late PosHomeController c;

  setUp(() {
    c = PosHomeController();
  });

  tearDown(() {
    // Dispose the TextEditingControllers manually since we never call
    // onInit/onClose through the GetX lifecycle in these tests.
    c.searchController.dispose();
    c.noteController.dispose();
    c.customerController.dispose();
    c.discountController.dispose();
    c.taxController.dispose();
    c.tenderedController.dispose();
    c.paymentReferenceController.dispose();
    c.productScrollController.dispose();
  });

  group('subtotal', () {
    test('sums line totals across quantities', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 10.0), qty: 2));
      c.cartItems.add(CartItem(product: _product(id: 'b', price: 5.5), qty: 1));
      expect(c.subtotal, 25.5);
    });
  });

  group('discountValue', () {
    test('flat discount is used as-is when under the subtotal', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 100.0), qty: 1));
      c.discountController.text = '20';
      expect(c.discountValue, 20.0);
    });

    test('flat discount is clamped to the subtotal, never negative total', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 50.0), qty: 1));
      c.discountController.text = '999'; // way over subtotal
      expect(c.discountValue, 50.0);
      expect(c.total, 0.0);
    });

    test('percent discount converts to an absolute amount off the subtotal', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 200.0), qty: 1));
      c.isPercentDiscount.value = true;
      c.discountController.text = '25'; // 25%
      expect(c.discountValue, 50.0);
    });

    test('percent discount over 100% is clamped to the subtotal', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.isPercentDiscount.value = true;
      c.discountController.text = '150'; // 150%
      expect(c.discountValue, 40.0);
      expect(c.total, 0.0);
    });
  });

  group('tax + total', () {
    test('tax applies to the post-discount amount', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 100.0), qty: 1));
      c.discountController.text = '10'; // flat $10 off -> $90 taxable
      c.taxController.text = '10'; // 10%
      expect(c.taxValue, 9.0);
      expect(c.total, 99.0); // 100 - 10 + 9
    });

    test('total is never negative even with a large discount and no tax', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 30.0), qty: 1));
      c.discountController.text = '30';
      c.taxController.text = '0';
      expect(c.total, 0.0);
    });
  });

  group('cash tendered / change due', () {
    test('change due is tendered minus total for cash payments', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.cash;
      c.tenderedController.text = '50';
      expect(c.changeDue, 10.0);
      expect(c.isCashUnderTendered, isFalse);
      expect(c.canCharge, isTrue);
    });

    test('under-tendering cash blocks charging and reports a shortfall, not a negative change', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.cash;
      c.tenderedController.text = '10';
      expect(c.changeDue, 0.0);
      expect(c.isCashUnderTendered, isTrue);
      expect(c.canCharge, isFalse);
    });

    test('change due does not apply to non-cash payment methods', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.card;
      c.tenderedController.text = '10'; // irrelevant for card
      expect(c.changeDue, 0.0);
      expect(c.isCashUnderTendered, isFalse);
      expect(c.canCharge, isTrue);
    });
  });

  group('discount gating (manager-only, mirrors the backend token check)', () {
    // Card payment throughout — isolates the discount gate from the
    // separate cash-tendered guard (also part of canCharge) covered above.
    test('a cashier with no discount can still charge', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.card;
      c.isManager.value = false;
      c.discountController.text = '0';
      expect(c.isDiscountBlocked, isFalse);
      expect(c.canCharge, isTrue);
    });

    test('a cashier entering a discount is blocked from charging', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.card;
      c.isManager.value = false;
      c.discountController.text = '5';
      expect(c.isDiscountBlocked, isTrue);
      expect(c.canCharge, isFalse);
    });

    test('a manager entering a discount can charge normally', () {
      c.cartItems.add(CartItem(product: _product(id: 'a', price: 40.0), qty: 1));
      c.selectedPayment.value = PosPaymentMethod.card;
      c.isManager.value = true;
      c.discountController.text = '5';
      expect(c.isDiscountBlocked, isFalse);
      expect(c.canCharge, isTrue);
    });
  });
}
