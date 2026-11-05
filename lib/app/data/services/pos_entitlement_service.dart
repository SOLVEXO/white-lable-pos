import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Whether this store may SELL right now, as told by the backend — never decided by the app.
///
/// When the store has no active POS plan **and the backend is enforcing it**, the app switches to
/// *restricted mode*: only closing the shift, reports, refund/void (manager) and sign-out stay
/// reachable, with a banner. Selling, holding, opening a session and the product catalog are off
/// (they are refused server-side anyway; this just stops the app offering them).
///
/// Two inputs, both server-driven:
///  * [checkPlan] — `GET /pos-subscriptions/:storeId`, whose response carries `enforced`. A failed call
///    changes nothing (a network blip must never lock a cashier out of the till).
///  * [markRestricted] — any POS call answered with `POS_PLAN_REQUIRED`.
class PosEntitlementService extends GetxController {
  PosEntitlementService({PosSubscriptionRepository? repository})
      : _repo = repository ?? PosSubscriptionRepository();

  final PosSubscriptionRepository _repo;

  /// True → selling is disabled; show the banner and keep to the allowed screens.
  final RxBool restricted = false.obs;

  /// Whether this store may take Raast QR payments (server's word; `null` = unknown, so the till does not hide the option).
  final Rxn<bool> digitalPaymentsEnabled = Rxn<bool>();

  /// Plain-language reason for the banner.
  final RxString message = ''.obs;

  static const String planInactiveMessage = 'POS plan not active for this store';

  /// Re-checks the plan. Safe to call any time; returns the resulting [restricted] value.
  Future<bool> checkPlan({String? storeId}) async {
    final id = storeId ?? await AppPreferences.getStoreId();
    if (id == null || id.isEmpty) return restricted.value;
    try {
      final status = await _repo.getStatus(id);
      if (status.isUnknown) return restricted.value; // can't tell — change nothing
      if (status.digitalPaymentsEnabled != null) digitalPaymentsEnabled.value = status.digitalPaymentsEnabled;
      if (status.status.isEntitled || !status.enforced) {
        clear();
      } else {
        markRestricted();
      }
    } catch (e) {
      debugPrint('⚠️ PosEntitlementService.refresh: $e');
    }
    return restricted.value;
  }

  void markRestricted() {
    message.value = planInactiveMessage;
    restricted.value = true;
  }

  void clear() {
    restricted.value = false;
    message.value = '';
  }

  /// Convenience for code that may run where the service isn't registered (unit tests).
  static PosEntitlementService? get maybe => Get.isRegistered<PosEntitlementService>() ? Get.find<PosEntitlementService>() : null;
  static bool get isRestricted => maybe?.restricted.value ?? false;
}
