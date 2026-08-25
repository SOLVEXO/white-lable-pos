import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/modules/category/models/category_with_children_response.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class CategoryRepository {
  final BaseClient _baseClient = BaseClient();

  // ─────────────────────────────────────────
  // 1. GET ALL CATEGORY TREES (Full Hierarchy)
  // ─────────────────────────────────────────
  /// Get all categories
  Future<List<CategoryModel>?> getCategories() async {
    try {
      final response = await _baseClient.get(ApiConstants.categories);

      debugPrint("Get Categories Response --> ${response.data}");

      if (response.statusCode == 200 && response.data['success'] == true) {
        return (response.data['data'] as List)
            .map((category) => CategoryModel.fromJson(category))
            .toList();
      }

      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint("Get Categories error --> $e");
      return null;
    }
  }

  Future<List<CategoryModel>> getAllCategoryTrees() async {
    try {
      debugPrint('🔄 Fetching all category trees...');

      final response = await _baseClient.get(ApiConstants.categories);

      debugPrint('✅ Category Trees Response: ${response.data}');

      if (response.data['data'] != null) {
        final List data = response.data['data'] as List;
        final categories = data
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();

        debugPrint('✅ Parsed ${categories.length} root categories');
        return categories;
      }

      return [];
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching category trees: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────
  // 2. GET CATEGORY TREE BY ID (Specific subtree)
  // ─────────────────────────────────────────

  Future<CategoryModel?> getCategoryTreeById(String categoryId) async {
    try {
      debugPrint('🔄 Fetching category tree for: $categoryId');

      final response = await _baseClient.get(
        ApiConstants.getCategoryTree(categoryId),
      );

      debugPrint('✅ Category Tree Response: ${response.data}');

      final data = response.data?['data'];
      if (data is Map<String, dynamic>) {
        return CategoryModel.fromJson(data);
      }

      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching category tree by ID: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────
  // 4. CREATE CATEGORY — admin: main categories only; seller: optional
  //    subcategories, nested one level under an existing main category.
  // ─────────────────────────────────────────

  Future<CategoryModel?> createCategory({
    required String name,
    String? parentId,
    String? image,
    String? description,
    int? sortOrder,
  }) async {
    try {
      final response = await _baseClient.post(
        ApiConstants.addCategory,
        data: {
          'name': name,
          if (parentId != null) 'parentId': parentId,
          if (image != null) 'image': image,
          if (description != null) 'description': description,
          if (sortOrder != null) 'sortOrder': sortOrder,
        },
      );

      debugPrint('✅ createCategory Response: ${response.data}');

      final data = response.data?['data'];
      if (response.data?['success'] == true && data is Map<String, dynamic>) {
        return CategoryModel.fromJson(data);
      }
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ Error creating category: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────
  // 3. GET CATEGORY WITH DIRECT CHILDREN ONLY
  // ─────────────────────────────────────────

  Future<CategoryWithChildrenResponse?> getCategoryById(
    String categoryId,
  ) async {
    try {
      debugPrint('🔄 Fetching category with children: $categoryId');

      final response = await _baseClient.get(
        ApiConstants.getCategoryById(categoryId),
      );

      debugPrint('✅ Category By ID Response: ${response.data}');

      if (response.data['data'] != null) {
        return CategoryWithChildrenResponse.fromJson(
          response.data['data'] as Map<String, dynamic>,
        );
      }

      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching category by ID: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────
  // HELPER: Get only root categories (no children)
  // ─────────────────────────────────────────

  Future<List<CategoryModel>> getRootCategories() async {
    final allTrees = await getAllCategoryTrees();
    return allTrees; // These are already root categories
  }

  // ─────────────────────────────────────────
  // HELPER: Search categories by name (all levels)
  // ─────────────────────────────────────────

  Future<List<CategoryModel>> searchCategories(String query) async {
    final allTrees = await getAllCategoryTrees();
    final results = <CategoryModel>[];

    for (final tree in allTrees) {
      // Flatten the tree and search
      final flatList = tree.flatten();
      results.addAll(
        flatList.where(
          (cat) => cat.name.toLowerCase().contains(query.toLowerCase()),
        ),
      );
    }

    return results;
  }

  // ─────────────────────────────────────────
  // HELPER: Get all categories as flat list
  // ─────────────────────────────────────────

  Future<List<CategoryModel>> getAllCategoriesFlat() async {
    final allTrees = await getAllCategoryTrees();
    final flatList = <CategoryModel>[];

    for (final tree in allTrees) {
      flatList.addAll(tree.flatten());
    }

    return flatList;
  }
}
