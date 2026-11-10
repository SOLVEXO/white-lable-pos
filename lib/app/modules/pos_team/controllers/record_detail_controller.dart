import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

/// The raw punches and correction history of one attendance record. Online only: offline the record itself still shows, with a note that the
/// history needs an internet connection. The server decides who may open whose record.
class RecordDetailController extends GetxController {
  RecordDetailController({required this.employeeId, required this.recordId, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String employeeId, recordId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<AttendanceRecordDetail> detail = Rxn<AttendanceRecordDetail>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  Worker? _online;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(teamOnlineRx(), (on) {
      if (on && detail.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!teamOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final d = await _repo.getAttendanceRecordDetail(await teamStoreId(_storeIdOverride), employeeId: employeeId, recordId: recordId);
    if (d == null) {
      error.value = teamErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the punches. Try again.');
    } else {
      detail.value = d;
    }
    loading.value = false;
  }
}
