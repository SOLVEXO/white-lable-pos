import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';

class PosDailyReportController extends GetxController {
  final _posRepo = PosRepository();

  final RxBool isLoading = true.obs;
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
}
