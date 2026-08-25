import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:get/get.dart';

class PosAuditLogBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosAuditLogController>(() => PosAuditLogController());
  }
}
