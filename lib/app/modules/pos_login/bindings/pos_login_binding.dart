import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_login/controllers/pos_login_controller.dart';

class PosLoginBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosLoginController>(() => PosLoginController());
  }
}
