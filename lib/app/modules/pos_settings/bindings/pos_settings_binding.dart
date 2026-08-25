import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:get/get.dart';

class PosSettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSettingsController>(() => PosSettingsController());
  }
}
