import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';

class PosIntegrationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosIntegrationsController>(() => PosIntegrationsController());
  }
}
