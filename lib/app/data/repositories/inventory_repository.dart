import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart' show PagedResult;
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
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
  InventoryRepository({IdempotencyIntentStore? intents}) : _intents = intents ?? IdempotencyIntentStore.instance;

  final BaseClient _client = BaseClient();
  final IdempotencyIntentStore _intents;

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

  /// Reasons the backend accepts on a manual adjustment (`StockAdjustmentReason`
  /// — the subset that makes sense from a till). Value → label.
  static const Map<String, String> adjustmentReasons = {
    'correction': 'Count correction',
    'restocked': 'Restocked',
    'damaged': 'Damaged',
    'return': 'Customer return',
    'other': 'Other',
  };

  /// Changes a variant's stock by [delta] units (negative = remove) with a
  /// [reason], via the reason-coded, audited adjust route. Unlike the old
  /// absolute `PATCH …/variants/:id {stock}` this is a relative change, so it
  /// is NOT naturally retry-safe — the intent's idempotency key is sent as
  /// `Idempotency-Key` and reused on a retry until a final result, so a
  /// timed-out success can never be applied twice.
  ///
  /// The backend refuses stale or impossible changes with a clear message
  /// (400/409 — e.g. removing more than is on hand); that text is surfaced.
  Future<({bool success, String? message})> adjustVariantStock({
    required String storeId,
    required String variantId,
    required int delta,
    required String reason,
    String? note,
  }) async {
    final payload = {
      'delta': delta,
      'reason': reason,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    final fp = IdempotencyIntentStore.fingerprint('adjustStock:$variantId', payload);
    var settled = false;
    try {
      final res = await _client.patch(
        ApiConstants.inventoryAdjustStock(storeId, variantId),
        data: payload,
        requiresAuth: true,
        headers: {'Idempotency-Key': await _intents.keyFor(fp)},
      );
      settled = true;
      if (_ok(res)) return (success: true, message: res.data['message'] as String?);
      return (success: false, message: res.data['message'] as String? ?? 'Failed to update stock');
    } on DioException catch (e) {
      final s = e.response?.statusCode;
      settled = s != null && s >= 400 && s < 500 && s != 408 && s != 409 && s != 429;
      _logDioError('adjustVariantStock', e);
      final data = e.response?.data;
      final msg = data is Map ? data['message'] as String? : null;
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, message: msg ?? 'Failed to update stock');
    } catch (e) {
      debugPrint('❌ adjustVariantStock: $e');
      return (success: false, message: 'Failed to update stock.');
    } finally {
      if (settled) await _intents.release(fp);
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
