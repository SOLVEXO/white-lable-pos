import 'package:solvexo_pos/app/modules/pos_session_history/controllers/pos_session_history_controller.dart';
import 'package:get/get.dart';

class PosSessionHistoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSessionHistoryController>(() => PosSessionHistoryController());
  }
}
