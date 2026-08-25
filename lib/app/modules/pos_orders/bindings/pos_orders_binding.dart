import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:get/get.dart';

class PosOrdersBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosOrdersController>(() => PosOrdersController());
  }
}
