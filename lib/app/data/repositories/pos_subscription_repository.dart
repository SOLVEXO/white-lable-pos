import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';

/// Reads a store's POS plan entitlement. READ-ONLY by design: plans are bought on the web (Solvexo's own site / admin grant),
/// never in this app — there is no plan list, price or checkout call here (store-policy compliance).
///
/// Duplicates PosRepository's `_data`/`_ok` envelope helpers rather than
/// sharing them via a mixin/base class: they're two three-line methods, and
/// a shared base would couple two repositories that otherwise have nothing
/// to do with each other just to save a few lines.
class PosSubscriptionRepository {
  PosSubscriptionRepository({BaseClient? client}) : _client = client ?? BaseClient();

  final BaseClient _client;

  /// Every response is `{success, message?, data?}`. Returns the unwrapped
  /// `data` payload only when `success == true`; otherwise null.
  dynamic _data(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic> && raw['success'] == true) {
      return raw['data'];
    }
    return null;
  }

  void _logDioError(String tag, DioException e) {
    debugPrint('❌ $tag DioException: ${e.response?.statusCode}');
    debugPrint('   Response: ${e.response?.data}');
  }

  Future<PosSubscriptionStatusModel> getStatus(String storeId) async {
    try {
      final res = await _client.get(
        ApiConstants.posSubscriptionStatus(storeId),
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return PosSubscriptionStatusModel.unknown();
      return PosSubscriptionStatusModel.fromJson(data);
    } on DioException catch (e) {
      _logDioError('getStatus', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return PosSubscriptionStatusModel.unknown();
    } catch (e) {
      debugPrint('❌ getStatus: $e');
      return PosSubscriptionStatusModel.unknown();
    }
  }
}
