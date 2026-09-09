import 'package:solvexo_pos/app/modules/pos_stock_activity/controllers/pos_stock_activity_controller.dart';
import 'package:get/get.dart';

class PosStockActivityBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosStockActivityController>(() => PosStockActivityController());
  }
}
