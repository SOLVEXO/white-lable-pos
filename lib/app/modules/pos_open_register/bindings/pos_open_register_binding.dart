import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:get/get.dart';

class PosOpenRegisterBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosOpenRegisterController>(() => PosOpenRegisterController());
  }
}
