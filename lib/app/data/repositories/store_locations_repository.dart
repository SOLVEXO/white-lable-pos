import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class StoreLocationsRepository {
  final BaseClient _client = BaseClient();

  Future<List<StoreLocationModel>> getLocations(String storeId) async {
    try {
      final response = await _client.get(ApiConstants.posLocations(storeId), requiresAuth: true);
      if (response.data['success'] == true) {
        return (response.data['data'] as List).cast<Map<String, dynamic>>().map(StoreLocationModel.fromJson).toList();
      }
      return [];
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getLocations error: $e');
      ToastUtil.showToast('Failed to load locations.');
      return [];
    }
  }

  Future<StoreLocationsOverviewModel> getOverview(String storeId) async {
    try {
      final response = await _client.get(ApiConstants.posLocationsOverview(storeId), requiresAuth: true);
      if (response.data['success'] == true) {
        return StoreLocationsOverviewModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      return StoreLocationsOverviewModel.empty;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return StoreLocationsOverviewModel.empty;
    } catch (e) {
      debugPrint('❌ getOverview error: $e');
      ToastUtil.showToast('Failed to load locations overview.');
      return StoreLocationsOverviewModel.empty;
    }
  }

  Future<StoreLocationModel?> getLocationById(String storeId, String locationId) async {
    try {
      final response = await _client.get(ApiConstants.posLocationById(storeId, locationId), requiresAuth: true);
      if (response.data['success'] == true) {
        return StoreLocationModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getLocationById error: $e');
      ToastUtil.showToast('Failed to load location.');
      return null;
    }
  }

  Future<StoreLocationModel?> createLocation(
    String storeId, {
    required String name,
    String? addressLine1,
    String? city,
    String? phone,
  }) async {
    try {
      final response = await _client.post(
        ApiConstants.posLocations(storeId),
        data: {
          'name': name,
          if (addressLine1 != null) 'addressLine1': addressLine1,
          if (city != null) 'city': city,
          if (phone != null) 'phone': phone,
        },
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        ToastUtil.showToast(response.data['message'] ?? 'Location added');
        return StoreLocationModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      ToastUtil.showToast(response.data['message'] ?? 'Failed to add location');
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ createLocation error: $e');
      ToastUtil.showToast('Failed to add location.');
      return null;
    }
  }

  Future<StoreLocationModel?> updateLocation(
    String storeId,
    String locationId, {
    String? name,
    String? addressLine1,
    String? city,
    String? phone,
    String? status,
  }) async {
    try {
      final response = await _client.patch(
        ApiConstants.posLocationById(storeId, locationId),
        data: {
          if (name != null) 'name': name,
          if (addressLine1 != null) 'addressLine1': addressLine1,
          if (city != null) 'city': city,
          if (phone != null) 'phone': phone,
          if (status != null) 'status': status,
        },
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        ToastUtil.showToast(response.data['message'] ?? 'Location updated');
        return StoreLocationModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      ToastUtil.showToast(response.data['message'] ?? 'Failed to update location');
      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ updateLocation error: $e');
      ToastUtil.showToast('Failed to update location.');
      return null;
    }
  }

  Future<bool> archiveLocation(String storeId, String locationId, {bool force = false}) async {
    try {
      final response = await _client.delete(
        ApiConstants.posLocationById(storeId, locationId),
        queryParameters: force ? {'force': 'true'} : null,
        requiresAuth: true,
      );
      if (response.data['success'] == true) {
        ToastUtil.showToast(response.data['message'] ?? 'Location archived');
        return true;
      }
      return false;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ archiveLocation error: $e');
      ToastUtil.showToast('Failed to archive location.');
      return false;
    }
  }
}
