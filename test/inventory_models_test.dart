// Model fromJson parsing tests for the Phase 2 Inventory feature, against
// fixture payloads matching the field names confirmed by reading the
// backend source directly (inventory.controller.ts/.service.ts,
// product-variants.controller.ts, activity-log schema) — catches field-name
// drift between the Flutter models and the real backend contract.

import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InventoryStats', () {
    test('parses the stats block from getStoreInventory', () {
      final stats = InventoryStats.fromJson({
        'totalProducts': 42,
        'inStock': 30,
        'lowStock': 8,
        'outOfStock': 4,
      });
      expect(stats.totalProducts, 42);
      expect(stats.inStock, 30);
      expect(stats.lowStock, 8);
      expect(stats.outOfStock, 4);
    });

    test('defaults to zeros when null', () {
      final stats = InventoryStats.fromJson(null);
      expect(stats.totalProducts, 0);
    });
  });

  group('InventoryProductSummary', () {
    test('parses a getStoreInventory product row', () {
      final p = InventoryProductSummary.fromJson({
        'productId': 'p1',
        'sku': 'SKU-1',
        'name': 'Widget',
        'stock': 12,
        'stockStatus': 'low_stock',
        'price': 9.99,
        'minPrice': 9.99,
        'maxPrice': 14.99,
        'variantCount': 3,
      });
      expect(p.productId, 'p1');
      expect(p.stock, 12);
      expect(p.hasSingleVariant, isFalse);
    });

    test('falls back to _id when productId is absent, and defaults variantCount to 1', () {
      final p = InventoryProductSummary.fromJson({
        '_id': 'p2',
        'name': 'Gadget',
        'stock': 5,
        'stockStatus': 'in_stock',
      });
      expect(p.productId, 'p2');
      expect(p.hasSingleVariant, isTrue);
    });
  });

  group('LowStockSummary', () {
    test('parses items and the real store-configured threshold', () {
      final summary = LowStockSummary.fromJson({
        'count': 2,
        'threshold': 15,
        'items': [
          {'productId': 'p1', 'name': 'Widget', 'stock': 3},
          {'productId': 'p2', 'name': 'Gadget', 'stock': 7},
        ],
      });
      expect(summary.count, 2);
      expect(summary.threshold, 15, reason: 'must reflect store.lowStockThreshold, not a client-hardcoded value');
      expect(summary.items.length, 2);
      expect(summary.items.first.name, 'Widget');
    });
  });

  group('InventoryVariant', () {
    test('builds a label from options when present', () {
      final v = InventoryVariant.fromJson({
        '_id': 'v1',
        'sku': 'SKU-1-RED-L',
        'stock': 4,
        'isDefault': false,
        'options': [
          {'name': 'Color', 'value': 'Red'},
          {'name': 'Size', 'value': 'L'},
        ],
      });
      expect(v.variantId, 'v1');
      expect(v.label, 'Red / L');
    });

    test('falls back to sku when there are no options', () {
      final v = InventoryVariant.fromJson({'_id': 'v1', 'sku': 'SKU-1', 'stock': 4, 'isDefault': true});
      expect(v.label, 'SKU-1');
    });
  });

  group('ActivityLogEntry', () {
    test('parses a stock-adjustment activity-log entry', () {
      final entry = ActivityLogEntry.fromJson({
        '_id': 'log1',
        'actorName': 'Jane Seller',
        'action': 'inventory_adjusted',
        'description': 'Stock 12 → 8 adjusted',
        'createdAt': '2026-01-15T10:30:00.000Z',
      });
      expect(entry.actorName, 'Jane Seller');
      expect(entry.description, 'Stock 12 → 8 adjusted');
      expect(entry.createdAt.year, 2026);
    });
  });
}
