import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_device_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';

/// Device registration endpoints. Register / list / revoke are owner-only on the backend; on a registered device the Dio
/// layer attaches the owner's short-lived in-memory session to them (see OwnerRoutes), never the device token.
class PosDeviceRepository {
  PosDeviceRepository({BaseClient? client}) : _client = client ?? BaseClient();
  final BaseClient _client;

  Future<PosDeviceRegistration?> register({required String storeId, required String registerId, required String name, String? platform}) async {
    try {
      final res = await _client.post(
        ApiConstants.posDevices,
        data: {'storeId': storeId, 'registerId': registerId, 'name': name, if (platform != null) 'platform': platform},
        requiresAuth: true,
      );
      final data = res.data is Map ? (res.data as Map)['data'] as Map<String, dynamic>? : null;
      if (data == null || data['deviceToken'] == null) return null;
      return PosDeviceRegistration(deviceId: data['deviceId'].toString(), deviceToken: data['deviceToken'] as String);
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ registerDevice: $e');
      return null;
    }
  }

  Future<List<PosDeviceModel>?> list(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posDevicesOfStore(storeId), requiresAuth: true);
      final list = (res.data is Map ? (res.data as Map)['data'] : null) as List<dynamic>?;
      return list?.map((e) => PosDeviceModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ listDevices: $e');
      return null;
    }
  }

  Future<bool> revoke(String storeId, String deviceId) async {
    try {
      final res = await _client.post(ApiConstants.posDeviceRevoke(storeId, deviceId), data: const {}, requiresAuth: true);
      return res.data is Map && (res.data as Map)['success'] == true;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ revokeDevice: $e');
      return false;
    }
  }

  /// The device retiring itself (full sign-out): its token stops working server-side. Best effort — the owner can always
  /// revoke it from the Devices screen if this could not be reached.
  Future<void> signOutSelf() async {
    try {
      await _client.post(ApiConstants.posDeviceSignOut, data: const {}, requiresAuth: true);
    } catch (e) {
      debugPrint('⚠️ device sign-out (server) failed: $e');
    }
  }
}
