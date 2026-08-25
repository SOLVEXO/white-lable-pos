import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_products/controllers/pos_products_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:get/get.dart';

class PosBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<PosBottomNavController>(PosBottomNavController());
    Get.lazyPut<PosHomeController>(() => PosHomeController());
    Get.lazyPut<PosOrdersController>(() => PosOrdersController());
    Get.lazyPut<PosProductsController>(() => PosProductsController());
    Get.lazyPut<PosSettingsController>(() => PosSettingsController());
  }
}
