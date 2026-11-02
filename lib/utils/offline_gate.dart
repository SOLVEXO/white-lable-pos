import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';

/// Actions that must reach the server to be safe — completing a held sale, refunding, voiding. The offline queue only
/// carries NEW sales; these three change an existing sale's money/stock state, so they are disabled (with a reason)
/// while there is no network instead of failing half-way. Reactive: read inside an `Obx`.
class OfflineGate {
  static const String message =
      "You're offline. Completing a held sale, refunds and voids need a connection — reconnect and try again.";

  static bool get isOffline =>
      Get.isRegistered<NetworkStatusService>() && !Get.find<NetworkStatusService>().isOnline.value;
}
