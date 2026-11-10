import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';

/// The period chips of the expense list.
enum ExpensePeriod {
  today('Today'),
  week('7 days'),
  month('30 days');

  const ExpensePeriod(this.label);
  final String label;

  /// [from] inclusive, [to] exclusive, as local times.
  (DateTime, DateTime) range(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final to = start.add(const Duration(days: 1));
    return switch (this) {
      ExpensePeriod.today => (start, to),
      ExpensePeriod.week => (start.subtract(const Duration(days: 6)), to),
      ExpensePeriod.month => (start.subtract(const Duration(days: 29)), to),
    };
  }
}

/// Expenses of a period with the total per category and a status filter (recorded / approved / rejected). The server decides what is shown: a cashier
/// only gets their own expenses. Online only.
class ExpenseListController extends GetxController {
  ExpenseListController({PosRepository? repository, String? storeId, DateTime Function()? clock}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId, _clock = clock ?? DateTime.now;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;

  final RxList<Expense> items = <Expense>[].obs;
  final RxMap<String, int> totals = <String, int>{}.obs;
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxString status = 'all'.obs;
  final Rx<ExpensePeriod> period = ExpensePeriod.week.obs;
  final RxBool canManageHint = false.obs;
  Worker? _online;

  int get totalMinor => totals.values.fold(0, (a, b) => a + b);

  @override
  void onInit() {
    super.onInit();
    cashGuessCanManage().then((v) => canManageHint.value = v);
    load();
    _online = ever<bool>(cashOnlineRx(), (on) {
      if (on) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  void setStatus(String s) {
    if (status.value == s) return;
    status.value = s;
    load();
  }

  void setPeriod(ExpensePeriod p) {
    if (period.value == p) return;
    period.value = p;
    load();
  }

  Future<void> load() async {
    error.value = null;
    if (!cashOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final (from, to) = period.value.range(_clock());
    final r = await _repo.getExpenses(await cashStoreId(_storeIdOverride), status: status.value, from: from, to: to);
    if (r == null) {
      items.clear();
      totals.clear();
      error.value = cashErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the expenses. Try again.');
    } else {
      items.assignAll(r.expenses);
      totals.assignAll(r.totalsByCategoryMinor);
      cur.value = r.cur;
    }
    loading.value = false;
  }
}
