import 'package:solvexo_pos/app/modules/pos_subscription_paywall/controllers/pos_subscription_paywall_controller.dart';
import 'package:get/get.dart';

class PosSubscriptionPaywallBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSubscriptionPaywallController>(() => PosSubscriptionPaywallController());
  }
}
