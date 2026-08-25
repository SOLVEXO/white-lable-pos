import 'package:solvexo_pos/app/modules/seller_pos_management/controllers/seller_pos_management_controller.dart';
import 'package:get/get.dart';

class SellerPosManagementBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerPosManagementController>(
        () => SellerPosManagementController());
  }
}
