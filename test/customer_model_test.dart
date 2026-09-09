// Model fromJson parsing tests for CustomerModel, against fixture payloads
// matching the two real backend endpoints confirmed by reading
// store.service.ts (getStoreCustomers) and draft-orders.service.ts
// (searchCustomers) directly.

import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomerModel.fromJson (store past-buyers list)', () {
    test('parses a full customer row with order stats', () {
      final c = CustomerModel.fromJson({
        '_id': 'cust1',
        'name': 'Alice Buyer',
        'email': 'alice@example.com',
        'phone': '+92 300 1234567',
        'orderCount': 5,
        'totalSpent': 249.5,
        'segment': 'returning',
      });
      expect(c.id, 'cust1');
      expect(c.name, 'Alice Buyer');
      expect(c.orderCount, 5);
      expect(c.totalSpent, 249.5);
      expect(c.segment, 'returning');
    });
  });

  group('CustomerModel.fromSearchJson (global user search)', () {
    test('parses the flat id/name/email/phone shape with no order stats', () {
      final c = CustomerModel.fromSearchJson({
        'id': 'user1',
        'name': 'Bob Shopper',
        'email': 'bob@example.com',
        'phone': '+92 300 7654321',
      });
      expect(c.id, 'user1');
      expect(c.name, 'Bob Shopper');
      expect(c.orderCount, isNull, reason: 'search results have no order-stats fields');
      expect(c.totalSpent, isNull);
      expect(c.segment, isNull);
    });
  });
}
