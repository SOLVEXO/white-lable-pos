import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';

class PosKybBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosKybController>(() => PosKybController());
  }
}
