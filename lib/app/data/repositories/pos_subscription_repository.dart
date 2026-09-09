import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_plan_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';

/// Per-store POS plan purchase gate — admin-managed plans, one-time Stripe
/// Checkout, fixed-term expiry, no recurring subscription/billing portal
/// (see backend spec for the endpoint contract).
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

  /// Active plans available for purchase — admin-authored, entirely dynamic
  /// (name/price/duration), never hardcoded on the client.
  Future<List<PosPlanModel>> getPlans() async {
    try {
      final res = await _client.get(ApiConstants.posPlans, requiresAuth: true);
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => PosPlanModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('getPlans', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return [];
    } catch (e) {
      debugPrint('❌ getPlans: $e');
      return [];
    }
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

  Future<String?> createCheckoutSession(
    String storeId, {
    required String planId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSubscriptionCheckoutSession(storeId),
        data: {'planId': planId, 'successUrl': successUrl, 'cancelUrl': cancelUrl},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      return data?['url'] as String?;
    } on DioException catch (e) {
      _logDioError('createCheckoutSession', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return null;
    } catch (e) {
      debugPrint('❌ createCheckoutSession: $e');
      return null;
    }
  }
}
