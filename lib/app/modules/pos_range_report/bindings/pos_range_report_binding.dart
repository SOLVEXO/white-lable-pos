import 'package:solvexo_pos/app/modules/pos_range_report/controllers/pos_range_report_controller.dart';
import 'package:get/get.dart';

class PosRangeReportBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosRangeReportController>(() => PosRangeReportController());
  }
}
