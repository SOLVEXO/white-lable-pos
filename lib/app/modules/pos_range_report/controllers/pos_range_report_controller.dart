import 'dart:typed_data';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

class PosRangeReportController extends GetxController {
  final _posRepo = PosRepository();

  final RxBool isLoading = true.obs;
  final RxBool isExporting = false.obs;
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

  Future<void> exportTodayCsv() async {
    isExporting.value = true;
    try {
      final bytes = await _posRepo.exportDailyReportCsv(_storeId);
      if (bytes == null) return;
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'pos-report-${_fmt(DateTime.now())}.csv',
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
