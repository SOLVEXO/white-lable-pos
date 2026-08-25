import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:get/get.dart';

class PosHomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosHomeController>(() => PosHomeController());
  }
}
