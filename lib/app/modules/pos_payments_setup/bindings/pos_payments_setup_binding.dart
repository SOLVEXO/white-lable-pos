import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/controllers/pos_payments_setup_controller.dart';

class PosPaymentsSetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosPaymentsSetupController>(() => PosPaymentsSetupController());
  }
}
