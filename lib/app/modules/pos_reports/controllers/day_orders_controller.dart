import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

/// G4.1 follow-up: the sales of ONE store day (a report's day drills down here). A dedicated list, so the shared Orders tab (its own controller, its own
/// filters, its shift scope) is never touched. Online only; pages of 20.
class DayOrdersController extends GetxController {
  DayOrdersController({required this.date, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String date;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxList<PosSaleModel> sales = <PosSaleModel>[].obs;
  final RxBool loading = true.obs;
  final RxBool loadingMore = false.obs;
  final RxnString error = RxnString();
  final RxInt total = 0.obs;
  int _page = 1;
  bool _hasMore = false;
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final r = await _repo.getSalesForDay(await reportsStoreId(_storeIdOverride), date);
    if (r == null) {
      error.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the sales of this day. Try again.');
    } else {
      sales.assignAll(r.items);
      total.value = r.total;
      _page = 1;
      _hasMore = r.hasMore;
    }
    loading.value = false;
  }

  Future<void> loadMore() async {
    if (!_hasMore || loadingMore.value) return;
    loadingMore.value = true;
    final r = await _repo.getSalesForDay(await reportsStoreId(_storeIdOverride), date, page: _page + 1);
    if (r != null) {
      sales.addAll(r.items);
      _page++;
      _hasMore = r.hasMore;
    }
    loadingMore.value = false;
  }
}
