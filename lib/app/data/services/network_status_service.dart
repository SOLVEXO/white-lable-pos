import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

/// App-wide connectivity status, driving `NetworkStatusBanner`. Reflects
/// whether a network *interface* is connected (WiFi/cellular/ethernet), not
/// verified internet reachability — connectivity_plus doesn't do reachability
/// checks, and adding a ping-based check would be over-engineering for what
/// this is: a "here's probably why things are failing" hint for the cashier,
/// not a guarantee. Retry/error handling (see BaseClient/DioExceptionHandler)
/// is the actual source of truth for whether a request succeeded.
///
/// `Get.put(NetworkStatusService(), permanent: true)` in `main.dart` (mirrors
/// `BrandingService`'s init pattern); read anywhere via
/// `Get.find<NetworkStatusService>()`.
class NetworkStatusService extends GetxController {
  final RxBool isOnline = true.obs;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> init() async {
    final initial = await Connectivity().checkConnectivity();
    _apply(initial);
    _subscription = Connectivity().onConnectivityChanged.listen(_apply);
  }

  void _apply(List<ConnectivityResult> results) {
    isOnline.value = results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
