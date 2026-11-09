import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class PosOrdersController extends GetxController {
  PosOrdersController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final ScrollController scrollController = ScrollController();

  final RxBool isLoading    = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString dateFilter  = 'All time'.obs;
  final Rx<DateTime?> fromDate = Rx(null);
  final Rx<DateTime?> toDate   = Rx(null);

  final RxList<PosSaleModel> sales = <PosSaleModel>[].obs;
  final RxString paymentFilter = 'All'.obs;
  final RxString statusFilter  = 'All'.obs;
  final RxString processingId  = ''.obs;
  /// The receipt number typed in the search box (OFF-…, INV-…, sale number, CN-…). Non-empty = the list shows that lookup across the WHOLE store.
  final RxString searchQuery = ''.obs;
  final RxString currencySymbol = Money.symbol().obs;
  /// See PosRole.isCurrentEmployeeManager's doc comment — gates the
  /// quick refund/void actions to match the backend's actual (if weak) check.
  final RxBool isManager = false.obs;

  /// The store / shift / currency are read once; a search typed before they are in must wait for them (an empty store id was a 500).
  late final Future<void> _ready = _loadContext();

  String _storeId   = '';
  String _sessionId = '';
  int _page = 1;
  bool _hasMore = true;

  static const statusFilters = ['All', 'completed', 'held', 'refunded', 'voided', 'partially_refunded'];

  // ── Computed stats ───────────────────────────────────────────────────────
  // Payment/status filters are now applied server-side (see loadSales/
  // loadMore), so `sales` already only contains matching rows. These totals
  // still only cover the pages loaded so far, not the full server-side
  // result set — there's no filtered-aggregate endpoint to total against —
  // so the UI labels them "(loaded)" rather than implying a full total.
  double get totalSales  => sales.fold(0.0, (s, t) => s + t.total);
  double get avgTransaction => sales.isEmpty ? 0.0 : totalSales / sales.length;
  double get cashTotal  =>
      sales.where((t) => t.paymentMethod == 'cash').fold(0.0, (s, t) => s + t.total);
  int    get txnCount   => sales.length;
  bool   get hasMore    => _hasMore;

  List<PosSaleModel> get filteredSales => sales;

  @override
  void onInit() {
    super.onInit();
    _ready.then((_) => loadSales());
    PosRole.isCurrentEmployeeManager().then((v) => isManager.value = v);
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
        loadMore();
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> _loadContext() async {
    _storeId   = await AppPreferences.getStoreId()      ?? '';
    _sessionId = await AppPreferences.getPosSessionId() ?? '';
    await _posRepo.getPosSettings(_storeId); // also configures Money (store currency + exponent)
    currencySymbol.value = Money.symbol(); // from the store's currency code, never free text
  }

  String? _fmtDate(DateTime? d) => d?.toIso8601String().split('T').first;
  String? get _paymentParam => paymentFilter.value == 'All' ? null : paymentFilter.value;
  String? get _statusParam => statusFilter.value == 'All' ? null : statusFilter.value;

  Future<void> searchByReceipt(String raw) async {
    await _ready;
    searchQuery.value = raw.trim();
    await loadSales();
  }

  Future<void> loadSales() async {
    isLoading.value = true;
    _page = 1;
    try {
      if (searchQuery.value.isNotEmpty && _storeId.isNotEmpty) {
        // a receipt-number lookup is store-wide (the return may be at a different till than the sale), not limited to this shift
        sales.assignAll(await _posRepo.lookupSales(_storeId, searchQuery.value));
        _hasMore = false;
        return;
      }
      final result = await _posRepo.getSales(
        storeId: _storeId,
        sessionId: _sessionId.isEmpty ? null : _sessionId,
        page: _page,
        from: _fmtDate(fromDate.value),
        to: _fmtDate(toDate.value),
        paymentMethod: _paymentParam,
        status: _statusParam,
      );
      sales.assignAll(result.items);
      _hasMore = result.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    try {
      final result = await _posRepo.getSales(
        storeId: _storeId,
        sessionId: _sessionId.isEmpty ? null : _sessionId,
        page: _page + 1,
        from: _fmtDate(fromDate.value),
        to: _fmtDate(toDate.value),
        paymentMethod: _paymentParam,
        status: _statusParam,
      );
      sales.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> refreshData() => loadSales();

  // Filters are applied server-side, so changing either re-fetches page 1.
  void setPaymentFilter(String method) {
    paymentFilter.value = method;
    loadSales();
  }

  void setStatusFilter(String status) {
    statusFilter.value = status;
    loadSales();
  }

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate.value = from;
    toDate.value = to;
    dateFilter.value = (from == null && to == null)
        ? 'All time'
        : '${_fmtDate(from) ?? '…'} → ${_fmtDate(to) ?? '…'}';
    loadSales();
  }

  void openSaleDetail(PosSaleModel sale) => Get.toNamed(Routes.posSaleDetail, arguments: sale.id);
}
