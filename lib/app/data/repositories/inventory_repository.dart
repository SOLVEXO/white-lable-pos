import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart' show PagedResult;
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Store inventory / stock-adjustment / stock-activity — none of this is
/// `/api/pos/*`, so it lives outside PosRepository (which only ever calls
/// the POS module) even though it's used from POS screens. All of these
/// routes are real and already live on the backend (confirmed by reading
/// inventory.controller.ts / product-variants.controller.ts /
/// activity-log.controller.ts directly) — they just weren't wired to any
/// Flutter repository before Phase 2.
class InventoryRepository {
  final BaseClient _client = BaseClient();

  dynamic _data(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic> && raw['success'] == true) return raw['data'];
    return null;
  }

  bool _ok(Response response) =>
      response.data is Map<String, dynamic> && response.data['success'] == true;

  PagedResult<T> _emptyPage<T>() => (items: <T>[], total: 0, totalPages: 0, hasMore: false);

  PagedResult<T> _page<T>(
    Map<String, dynamic> data,
    String listKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};
    final page = pagination['page'] as int? ?? 1;
    final totalPages = pagination['totalPages'] as int? ?? 1;
    final items = (data[listKey] as List<dynamic>?)
            ?.map((e) => fromJson(e as Map<String, dynamic>))
            .toList() ??
        <T>[];
    return (
      items: items,
      total: pagination['total'] as int? ?? items.length,
      totalPages: totalPages,
      hasMore: page < totalPages,
    );
  }

  void _logDioError(String tag, DioException e) {
    debugPrint('❌ $tag DioException: ${e.response?.statusCode}');
    debugPrint('   Response: ${e.response?.data}');
  }

  // ── Inventory list ───────────────────────────────────────────────────────

  Future<({PagedResult<InventoryProductSummary> page, InventoryStats stats})> getStoreInventory(
    String storeId, {
    int page = 1,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.getStoreInventory(storeId),
        queryParameters: {'page': page},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) {
        return (page: _emptyPage<InventoryProductSummary>(), stats: const InventoryStats(totalProducts: 0, inStock: 0, lowStock: 0, outOfStock: 0));
      }
      return (
        page: _page(data, 'products', InventoryProductSummary.fromJson),
        stats: InventoryStats.fromJson(data['stats'] as Map<String, dynamic>?),
      );
    } on DioException catch (e) {
      _logDioError('getStoreInventory', e);
      DioExceptionHandler.handleDioException(e);
      return (page: _emptyPage<InventoryProductSummary>(), stats: const InventoryStats(totalProducts: 0, inStock: 0, lowStock: 0, outOfStock: 0));
    } catch (e) {
      debugPrint('❌ getStoreInventory: $e');
      return (page: _emptyPage<InventoryProductSummary>(), stats: const InventoryStats(totalProducts: 0, inStock: 0, lowStock: 0, outOfStock: 0));
    }
  }

  Future<LowStockSummary?> getLowStockSummary(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.lowStockSummary(storeId), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? LowStockSummary.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getLowStockSummary', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getLowStockSummary: $e');
      return null;
    }
  }

  // ── Variants (to pick which one to adjust) ──────────────────────────────

  Future<List<InventoryVariant>> getProductVariants(String productId) async {
    try {
      final res = await _client.get(ApiConstants.productVariants(productId), requiresAuth: true);
      final data = _data(res);
      final list = data is List ? data : (data as Map<String, dynamic>?)?['variants'] as List<dynamic>?;
      return (list ?? []).map((e) => InventoryVariant.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('getProductVariants', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getProductVariants: $e');
      return [];
    }
  }

  // ── Stock correction ─────────────────────────────────────────────────────

  /// Sets a variant's stock to an absolute new quantity. The backend has no
  /// reason-code field for this (UpdateVariantDto only carries `stock` for
  /// our purposes) — it just logs a generic "Stock X → Y adjusted" activity
  /// entry, visible via [getStockActivity].
  Future<bool> updateVariantStock({
    required String productId,
    required String variantId,
    required int stock,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.productVariant(productId, variantId),
        data: {'stock': stock},
        requiresAuth: true,
        // Confirmed safe to retry on a network blip: this PATCH sets stock
        // to an absolute value (not a delta), so a retry after a timed-out
        // success is a no-op, not a double-adjustment.
        retryable: true,
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to update stock');
      return false;
    } on DioException catch (e) {
      _logDioError('updateVariantStock', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ updateVariantStock: $e');
      ToastUtil.showToast('Failed to update stock.');
      return false;
    }
  }

  // ── Stock activity (movement history) ───────────────────────────────────

  /// Store-wide feed of stock adjustments, newest first. Not filterable to
  /// a single product server-side — the seller-facing activity-log route
  /// has no targetId/targetType query param (only the admin route does).
  Future<PagedResult<ActivityLogEntry>> getStockActivity(String storeId, {int page = 1}) async {
    try {
      final res = await _client.get(
        ApiConstants.activityLog(storeId),
        queryParameters: {'page': page, 'action': 'inventory_adjusted'},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return _emptyPage();
      return _page(data, 'logs', ActivityLogEntry.fromJson);
    } on DioException catch (e) {
      _logDioError('getStockActivity', e);
      DioExceptionHandler.handleDioException(e);
      return _emptyPage();
    } catch (e) {
      debugPrint('❌ getStockActivity: $e');
      return _emptyPage();
    }
  }
}
