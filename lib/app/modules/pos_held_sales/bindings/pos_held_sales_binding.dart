import 'package:solvexo_pos/app/modules/pos_held_sales/controllers/pos_held_sales_controller.dart';
import 'package:get/get.dart';

class PosHeldSalesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosHeldSalesController>(() => PosHeldSalesController());
  }
}
