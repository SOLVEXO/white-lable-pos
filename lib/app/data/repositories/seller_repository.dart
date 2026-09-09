import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class SellerRepository {
  final BaseClient _client = BaseClient();

  // ─── GET /api/store/my-stores ─────────────────────────────────────────────

  Future<List<StoreModel>> getMyStores() async {
    try {
      debugPrint('📤 getMyStores → ${ApiConstants.myStores}');
      final response = await _client.get(
        ApiConstants.myStores,
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        final list = response.data['data'] as List<dynamic>;
        return list
            .map((e) => StoreModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getMyStores error: $e');
      return [];
    }
  }

  // ─── GET /api/store/getStoreById/:id ──────────────────────────────────────

  Future<StoreModel?> getStoreById(String id) async {
    try {
      final response = await _client.get(
        ApiConstants.getStoreById(id),
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        return StoreModel.fromJson(
          response.data['data'] as Map<String, dynamic>,
        );
      }
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getStoreById error: $e');
      return null;
    }
  }

  // ─── GET /api/store/public/enabled-currencies ─────────────────────────────
  // Admin-configurable list a store's baseCurrency must be one of — the
  // backend's own createStore validation rejects anything else, so this
  // replaces the old hardcoded ['PKR', 'USD'] onboarding list.

  Future<List<String>> getEnabledCurrencies() async {
    try {
      final response = await _client.get(
        ApiConstants.enabledCurrencies,
        requiresAuth: false,
      );
      if (response.data['success'] == true) {
        final list = response.data['data'] as List<dynamic>;
        return list
            .map((e) => (e as Map<String, dynamic>)['code'] as String)
            .toList();
      }
      return [];
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getEnabledCurrencies error: $e');
      return [];
    }
  }

  // ─── GET /api/store/suggest-location ──────────────────────────────────────
  // IP-detected country + a suggested currency for Onboarding's currency
  // step — a suggestion only, never enforced.

  Future<String?> getSuggestedCurrency() async {
    try {
      final response = await _client.get(
        ApiConstants.suggestLocation,
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return data['suggestedCurrency'] as String?;
      }
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getSuggestedCurrency error: $e');
      return null;
    }
  }

  // ─── POST /api/store/create-store ─────────────────────────────────────────

  Future<StoreModel?> createStore({
    required String name,
    required String sellerType,
    required List<String> productTypes,
    required String baseCurrency,
    String? logoUrl,
    String? description,
  }) async {
    try {
      debugPrint('📤 createStore name=$name');
      final body = <String, dynamic>{
        'name': name,
        'sellerType': sellerType,
        'productTypes': productTypes,
        'baseCurrency': baseCurrency,
        if ((logoUrl ?? '').isNotEmpty) 'logo': logoUrl,
        if ((description ?? '').isNotEmpty) 'description': description,
      };
      debugPrint('   body: $body');

      final response = await _client.post(
        ApiConstants.createStore,
        data: body,
        requiresAuth: true,
      );

      if (response.data['success'] == true) {
        final store = StoreModel.fromJson(
          response.data['data'] as Map<String, dynamic>,
        );
        debugPrint('✅ Store created: ${store.name} (${store.id})');
        return store;
      }

      ToastUtil.showToast(
        response.data['message'] as String? ?? 'Failed to create store.',
      );
      return null;
    } on DioException catch (e) {
      debugPrint('❌ DioException createStore: ${e.response?.statusCode}');
      debugPrint('   Response: ${e.response?.data}');
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ createStore error: $e');
      ToastUtil.showToast('Something went wrong. Please try again.');
      return null;
    }
  }
}
