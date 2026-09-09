import 'dart:typed_data';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

class PosDailyReportController extends GetxController {
  PosDailyReportController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxBool isLoading = true.obs;
  final RxBool isExporting = false.obs;
  final Rx<PosDailyReportModel?> report = Rx(null);

  String _storeId = '';

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadReport());
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  Future<void> loadReport() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    try {
      report.value = await _posRepo.getDailyReport(_storeId);
    } catch (e) {
      CustomAppSnackbar.error('Failed to load daily report.');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> onRefresh() => loadReport();

  /// Exports today's report as CSV — this is the only date the backend
  /// actually supports exporting (`/pos/reports/daily/export` takes a single
  /// date, there's no ranged export endpoint), so this button lives here
  /// where it always matches what's on screen, rather than on Range Report.
  Future<void> exportCsv() async {
    if (_storeId.isEmpty) return;
    isExporting.value = true;
    try {
      final bytes = await _posRepo.exportDailyReportCsv(_storeId);
      if (bytes == null) return;
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'pos-daily-report-${DateTime.now().toIso8601String().split('T').first}.csv',
        mimeType: 'text/csv',
      );
      await SharePlus.instance.share(ShareParams(files: [file], subject: 'POS Daily Report'));
    } catch (e) {
      CustomAppSnackbar.error('Failed to export report.');
    } finally {
      isExporting.value = false;
    }
  }
}
