import 'package:solvexo_pos/app/modules/pos_inventory/controllers/pos_inventory_controller.dart';
import 'package:get/get.dart';

class PosInventoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosInventoryController>(() => PosInventoryController());
  }
}
