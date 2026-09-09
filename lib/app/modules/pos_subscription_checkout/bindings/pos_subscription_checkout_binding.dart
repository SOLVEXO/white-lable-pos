import 'package:solvexo_pos/app/modules/pos_subscription_checkout/controllers/pos_subscription_checkout_controller.dart';
import 'package:get/get.dart';

class PosSubscriptionCheckoutBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSubscriptionCheckoutController>(() => PosSubscriptionCheckoutController());
  }
}
