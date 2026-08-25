class CategoryModel {
  final String id;
  final String name;
  final String? description;
  final String? image;
  final String? parentId;
  final int sortOrder;
  final String status;
  final bool isDelete;
  final List<CategoryModel> children;

  /// Rolled-up active product count (own + all descendants) — only present
  /// on the `category-tree` endpoint response, not `getCategoryById`.
  final int? productCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  CategoryModel({
    required this.id,
    required this.name,
    this.description,
    this.image,
    this.parentId,
    required this.sortOrder,
    required this.status,
    required this.isDelete,
    required this.children,
    this.productCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    try {
      return CategoryModel(
        id: json['_id'] ?? '',
        name: json['name'] ?? '',
        description: json['description'],
        image: json['image'],
        parentId: json['parentId'],
        sortOrder: json['sortOrder'] ?? 0,
        status: json['status'] ?? 'inactive',
        isDelete: json['isDelete'] ?? false,

        // 🔥 RECURSIVE PARSING
        children: (json['children'] as List? ?? [])
            .map((child) => CategoryModel.fromJson(child))
            .toList(),
        productCount: json['productCount'] as int?,

        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );
    } catch (e) {
      throw Exception("CategoryModel parsing error: $e");
    }
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'description': description,
      'image': image,
      'parentId': parentId,
      'sortOrder': sortOrder,
      'status': status,
      'isDelete': isDelete,
      'children': children.map((e) => e.toJson()).toList(),
      if (productCount != null) 'productCount': productCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // ─────────────────────────────────────────
  // HELPER METHODS
  // ─────────────────────────────────────────

  /// Check if category is a parent (top-level)
  bool get isParent => parentId == null;

  /// Check if category has children
  bool get hasChildren => children.isNotEmpty;

  /// Get depth level (0 = root, 1 = child, 2 = grandchild, etc.)
  int get level {
    if (isParent) return 0;
    // This would need parent reference to calculate accurately
    return 1; // Simplified
  }

  /// Get all child IDs (flat list)
  List<String> getAllChildIds() {
    final ids = <String>[];
    for (final child in children) {
      ids.add(child.id);
      ids.addAll(child.getAllChildIds()); // Recursive
    }
    return ids;
  }

  /// Get total number of descendants
  int get totalDescendants {
    int count = children.length;
    for (final child in children) {
      count += child.totalDescendants;
    }
    return count;
  }

  /// Find a category by ID in the tree
  CategoryModel? findById(String categoryId) {
    if (id == categoryId) return this;

    for (final child in children) {
      final found = child.findById(categoryId);
      if (found != null) return found;
    }

    return null;
  }

  /// Get all categories as flat list
  List<CategoryModel> flatten() {
    final list = <CategoryModel>[this];
    for (final child in children) {
      list.addAll(child.flatten());
    }
    return list;
  }

  @override
  String toString() =>
      'CategoryModel(id: $id, name: $name, children: ${children.length})';
}
