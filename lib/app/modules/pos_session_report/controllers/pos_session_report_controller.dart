import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:get/get.dart';

class PosSessionReportController extends GetxController {
  PosSessionReportController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxBool isLoading = true.obs;
  final Rx<PosSessionReportModel?> report = Rx(null);

  late final String sessionId;

  @override
  void onInit() {
    super.onInit();
    sessionId = Get.arguments as String? ?? '';
    _load();
  }

  Future<void> _load() async {
    if (sessionId.isEmpty) return;
    isLoading.value = true;
    try {
      report.value = await _posRepo.getSessionReport(sessionId);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshData() => _load();
}
