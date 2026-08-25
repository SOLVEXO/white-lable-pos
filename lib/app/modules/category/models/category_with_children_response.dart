import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:flutter/material.dart';

class CategoryWithChildrenResponse {
  final CategoryModel category;
  final List<CategoryModel> children;
  final int childrenCount;

  CategoryWithChildrenResponse({
    required this.category,
    required this.children,
    required this.childrenCount,
  });

  factory CategoryWithChildrenResponse.fromJson(Map<String, dynamic> json) {
    try {
      debugPrint("🔍 Parsing CategoryWithChildrenResponse");

      return CategoryWithChildrenResponse(
        // ✅ Main category
        category: CategoryModel.fromJson(
          (json['category'] ?? {}) as Map<String, dynamic>,
        ),

        // ✅ Direct children only (NOT recursive here)
        children: (json['children'] as List? ?? [])
            .map((e) => CategoryModel.fromJson(e))
            .toList(),

        // ✅ Safe count
        childrenCount:
            json['childrenCount'] ?? (json['children'] as List? ?? []).length,
      );
    } catch (e) {
      debugPrint("❌ CategoryWithChildrenResponse parsing error: $e");
      debugPrint("JSON: $json");
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // HELPER METHODS (VERY USEFUL)
  // ─────────────────────────────────────────

  /// Check if category has children
  bool get hasChildren => children.isNotEmpty;

  /// Get all children as flat list (including nested)
  List<CategoryModel> get allChildrenFlat {
    final list = <CategoryModel>[];
    for (final child in children) {
      list.addAll(child.flatten());
    }
    return list;
  }

  /// Find child by ID
  CategoryModel? findChildById(String id) {
    for (final child in children) {
      final found = child.findById(id);
      if (found != null) return found;
    }
    return null;
  }

  @override
  String toString() {
    return 'CategoryWithChildrenResponse(category: ${category.name}, children: ${children.length})';
  }
}
