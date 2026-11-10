import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';

/// G4.5: the store's modifier groups and price books as last read from the server, so the till can still offer them offline (the server prices
/// every sale anyway; an offline sale is never refused for them). Not secret (prices the shelf shows), so plain preferences, one key per store.
class CatalogPricingCache {
  static String _k(String kind, String storeId) => 'pos_cat_${kind}_$storeId';

  static Future<void> saveGroups(String storeId, ModifierGroups g) => _save(_k('groups', storeId), g.toJson());
  static Future<void> saveBooks(String storeId, PriceBooks b) => _save(_k('books', storeId), b.toJson());

  static Future<ModifierGroups?> groups(String storeId) async {
    final j = await _load(_k('groups', storeId));
    return j == null ? null : ModifierGroups.fromJson(j);
  }

  static Future<PriceBooks?> books(String storeId) async {
    final j = await _load(_k('books', storeId));
    return j == null ? null : PriceBooks.fromJson(j);
  }

  static Future<void> _save(String key, Map<String, dynamic> j) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(j));
    } catch (e) {
      debugPrint('catalog cache save: $e');
    }
  }

  static Future<Map<String, dynamic>?> _load(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      return j is Map ? j.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }
}
