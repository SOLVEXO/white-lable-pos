import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_count_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_limits_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_movements_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';

/// G3.1 inventory screens. The list / detail screens create their own tagged controllers (several can be open at once: All and Low).
class PosStockOverviewBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut<InvOverviewController>(() => InvOverviewController());
}

class PosStockMovementsBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut<InvMovementsController>(() => InvMovementsController(variantId: Get.arguments is Map ? (Get.arguments as Map)['variantId'] as String? : null));
}

class PosStockCountBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut<InvCountController>(() => InvCountController());
}

class PosStockLimitsBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut<InvLimitsController>(() => InvLimitsController());
}
