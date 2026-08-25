import 'package:solvexo_pos/app/data/models/branding/branding_config_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:flutter/foundation.dart';

/// Fetches this app build's white-label branding. `ApiConstants.brandingConfig`
/// doesn't exist on the backend yet (see that constant's doc comment) — a 404
/// here is an expected, routine outcome (not a real error), so it's treated
/// as a valid response via `validateStatus` rather than a thrown
/// `DioException`. That keeps this quiet in the console (no "❌ Dio Error"
/// from the shared interceptor for something that isn't actually broken) and
/// still lets `BrandingService` fall back to `BrandingConfigModel.defaults()`
/// or the last cached config.
class BrandingRepository {
  final BaseClient _client = BaseClient();

  Future<BrandingConfigModel?> getBrandingConfig() async {
    try {
      final response = await _client.get(
        ApiConstants.brandingConfig,
        requiresAuth: false,
        validateStatus: (status) => status != null && status < 500,
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return BrandingConfigModel.fromJson(response.data['data'] as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('ℹ️ Branding config fetch error: $e — using defaults/cache.');
      return null;
    }
  }
}
