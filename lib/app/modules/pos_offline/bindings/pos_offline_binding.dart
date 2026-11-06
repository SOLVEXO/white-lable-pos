import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_offline/controllers/pos_offline_controller.dart';

class PosOfflineBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosOfflineController>(() => PosOfflineController());
  }
}
