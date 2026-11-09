import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/controllers/pos_permissions_controller.dart';

class PosPermissionsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosPermissionsController>(() => PosPermissionsController());
  }
}
