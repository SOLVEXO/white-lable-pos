import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:get/get.dart';

class SellerOnboardingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerOnboardingController>(() => SellerOnboardingController());
  }
}
