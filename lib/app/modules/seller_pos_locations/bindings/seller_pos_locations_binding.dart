import 'package:solvexo_pos/app/modules/seller_pos_locations/controllers/seller_pos_locations_controller.dart';
import 'package:get/get.dart';

class SellerPosLocationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerPosLocationsController>(() => SellerPosLocationsController());
  }
}
