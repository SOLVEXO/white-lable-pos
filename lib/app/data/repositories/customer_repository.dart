import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart' show PagedResult;
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Real customers of a store — no fabricated/mock customer data. Two
/// distinct backend endpoints, both confirmed live and seller-JWT callable:
/// a paginated list of actual past buyers (with order stats), and a global
/// registered-user search (by name/email/phone) used to attach a customer
/// to a sale. Neither supports full CRUD — customers originate from real
/// orders, which is the right model for a POS's purposes.
class CustomerRepository {
  final BaseClient _client = BaseClient();

  dynamic _data(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic> && raw['success'] == true) return raw['data'];
    return null;
  }

  void _logDioError(String tag, DioException e) {
    debugPrint('❌ $tag DioException: ${e.response?.statusCode}');
    debugPrint('   Response: ${e.response?.data}');
  }

  /// Paginated list of buyers who've actually purchased from this store —
  /// no search param exists on this endpoint (confirmed against the
  /// backend service), so this is browse-only; use [searchCustomers] for
  /// typed lookup.
  Future<PagedResult<CustomerModel>> getStoreCustomers(String storeId, {int page = 1}) async {
    try {
      final res = await _client.get(
        ApiConstants.storeCustomers(storeId),
        queryParameters: {'page': page},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return (items: <CustomerModel>[], total: 0, totalPages: 0, hasMore: false);
      final pagination = data['pagination'] as Map<String, dynamic>? ?? {};
      final pageNum = pagination['page'] as int? ?? 1;
      final totalPages = pagination['totalPages'] as int? ?? 1;
      final items = (data['customers'] as List<dynamic>?)
              ?.map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <CustomerModel>[];
      return (
        items: items,
        total: pagination['total'] as int? ?? items.length,
        totalPages: totalPages,
        hasMore: pageNum < totalPages,
      );
    } on DioException catch (e) {
      _logDioError('getStoreCustomers', e);
      DioExceptionHandler.handleDioException(e);
      return (items: <CustomerModel>[], total: 0, totalPages: 0, hasMore: false);
    } catch (e) {
      debugPrint('❌ getStoreCustomers: $e');
      return (items: <CustomerModel>[], total: 0, totalPages: 0, hasMore: false);
    }
  }

  /// Global registered-user search by name/email/phone (capped at 10
  /// results server-side) — not scoped to past buyers of this store, but
  /// it's the only search capability the backend exposes for attaching a
  /// customer to a sale.
  Future<List<CustomerModel>> searchCustomers(String storeId, String q) async {
    if (q.trim().isEmpty) return [];
    try {
      final res = await _client.get(
        ApiConstants.customerSearch(storeId),
        queryParameters: {'q': q.trim()},
        requiresAuth: true,
      );
      final data = _data(res);
      final list = data is List ? data : const [];
      return list.map((e) => CustomerModel.fromSearchJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('searchCustomers', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ searchCustomers: $e');
      return [];
    }
  }
}
