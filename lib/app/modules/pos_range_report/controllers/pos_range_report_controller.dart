import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';

class PosRangeReportController extends GetxController {
  PosRangeReportController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxBool isLoading = true.obs;
  final Rx<PosRangeReportModel?> report = Rx(null);
  final Rx<DateTime> from = (DateTime.now().subtract(const Duration(days: 6))).obs;
  final Rx<DateTime> to = DateTime.now().obs;

  String _storeId = '';

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadReport());
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  String _fmt(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> loadReport() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    try {
      report.value = await _posRepo.getRangeReport(_storeId, from: _fmt(from.value), to: _fmt(to.value));
    } finally {
      isLoading.value = false;
    }
  }

  void setRange(DateTime f, DateTime t) {
    from.value = f;
    to.value = t;
    loadReport();
  }

  // No CSV export here: the backend only exposes a single-date export
  // (`/pos/reports/daily/export`), not a ranged one — that action now lives
  // on Daily Report (PosDailyReportController.exportCsv), where it always
  // matches what's on screen instead of silently exporting "today" no
  // matter which range is selected here.
}
