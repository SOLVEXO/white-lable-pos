import 'package:solvexo_pos/app/modules/pos_customers/controllers/pos_customers_controller.dart';
import 'package:get/get.dart';

class PosCustomersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosCustomersController>(() => PosCustomersController());
  }
}
