import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

/// G4.0 business pulse: today so far vs the same weekday last week. Shared (permanent) by the pulse screen and the compact Home card.
/// A cashier never calls it ([canManage] false → nothing is asked); the Home card is drawn only after the server answered 200.
class BusinessPulseController extends GetxController {
  BusinessPulseController({PosRepository? repository, String? storeId, Future<bool> Function()? canManage})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _canManage = canManage ?? reportsGuessCanManage;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final Future<bool> Function() _canManage;

  final Rxn<BusinessPulse> pulse = Rxn<BusinessPulse>();
  final RxBool loading = false.obs;
  final RxnString error = RxnString();

  /// the server refused (role / plan matrix) or this is a cashier: the Home card stays hidden
  final RxBool allowed = false.obs;
  bool _busy = false;

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    try {
      error.value = null;
      if (!await _canManage()) {
        allowed.value = false;
        pulse.value = null;
        return;
      }
      if (!reportsOnline()) return;
      loading.value = true;
      final p = await _repo.getBusinessPulse(await reportsStoreId(_storeIdOverride));
      if (p == null) {
        allowed.value = false;
        error.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the pulse. Try again.');
      } else {
        allowed.value = true;
        pulse.value = p;
      }
    } finally {
      loading.value = false;
      _busy = false;
    }
  }
}
