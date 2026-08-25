import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:get/get.dart';

class SellerStoresBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SellerStoresController>(() => SellerStoresController());
  }
}
