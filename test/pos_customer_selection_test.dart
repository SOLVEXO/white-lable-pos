// Unit test for the customer-selection bookkeeping added in Phase 2:
// PosHomeController.onCustomerTextChanged must clear a previously-picked
// selectedCustomer as soon as the cashier edits the name field, so a stale
// customerId is never sent to the backend alongside a different typed name.

import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('selecting a customer sets both the text field and selectedCustomer', () {
    const customer = CustomerModel(id: 'cust1', name: 'Alice Buyer');
    c.selectedCustomer.value = customer;
    c.customerController.text = customer.name;

    expect(c.selectedCustomer.value?.id, 'cust1');
    expect(c.customerController.text, 'Alice Buyer');
  });

  test('editing the name after a selection clears selectedCustomer', () {
    const customer = CustomerModel(id: 'cust1', name: 'Alice Buyer');
    c.selectedCustomer.value = customer;
    c.customerController.text = customer.name;

    c.onCustomerTextChanged('Alice Buyer Jr'); // cashier edits the name

    expect(c.selectedCustomer.value, isNull,
        reason: 'a stale customerId must never be sent alongside a different typed name');
  });

  test('re-typing the exact same name does not clear the selection', () {
    const customer = CustomerModel(id: 'cust1', name: 'Alice Buyer');
    c.selectedCustomer.value = customer;

    c.onCustomerTextChanged('Alice Buyer');

    expect(c.selectedCustomer.value?.id, 'cust1');
  });

  test('clearSale resets the selected customer along with the rest of the cart', () {
    const customer = CustomerModel(id: 'cust1', name: 'Alice Buyer');
    c.selectedCustomer.value = customer;
    c.customerController.text = customer.name;

    c.clearSale();

    expect(c.selectedCustomer.value, isNull);
    expect(c.customerController.text, isEmpty);
  });

  test('resuming a held sale with a customerId reconstructs a minimal CustomerModel', () {
    // Exercises the same snapshot-based reconstruction the held-sale-resume
    // fix (Phase 1) uses for products — here for the attached customer, so
    // completing a resumed held sale still carries the original customerId.
    final sale = PosSaleModel(
      id: 'sale-1',
      saleNumber: 'S-0001',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'register-1',
      employeeId: 'employee-1',
      items: const [],
      discount: 0,
      tax: 0,
      subtotal: 0,
      total: 0,
      paymentMethod: 'cash',
      customerName: 'Alice Buyer',
      customerId: 'cust1',
      notes: '',
      status: 'held',
      createdAt: DateTime(2026, 1, 1),
    );

    c.resumeHeldSale(sale);

    expect(c.selectedCustomer.value?.id, 'cust1');
    expect(c.selectedCustomer.value?.name, 'Alice Buyer');
    expect(c.customerController.text, 'Alice Buyer');
  });

  test('resuming a held sale with no customerId leaves selectedCustomer unset', () {
    final sale = PosSaleModel(
      id: 'sale-2',
      saleNumber: 'S-0002',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'register-1',
      employeeId: 'employee-1',
      items: const [],
      discount: 0,
      tax: 0,
      subtotal: 0,
      total: 0,
      paymentMethod: 'cash',
      customerName: 'Walk-in',
      notes: '',
      status: 'held',
      createdAt: DateTime(2026, 1, 1),
    );

    c.resumeHeldSale(sale);

    expect(c.selectedCustomer.value, isNull);
  });
}
