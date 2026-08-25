import 'package:solvexo_pos/app/modules/pos_session_report/controllers/pos_session_report_controller.dart';
import 'package:get/get.dart';

class PosSessionReportBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSessionReportController>(() => PosSessionReportController());
  }
}
