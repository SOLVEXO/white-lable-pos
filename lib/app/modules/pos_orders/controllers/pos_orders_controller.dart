import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class PosOrdersController extends GetxController {
  final _posRepo = PosRepository();

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

  String _storeId   = '';
  String _sessionId = '';
  int _page = 1;
  bool _hasMore = true;

  static const statusFilters = ['All', 'completed', 'held', 'refunded', 'voided', 'partially_refunded'];

  // ── Computed stats (over the currently loaded + filtered page set) ────────
  double get totalSales  => filteredSales.fold(0.0, (s, t) => s + t.total);
  double get avgTransaction => filteredSales.isEmpty ? 0.0 : totalSales / filteredSales.length;
  double get cashTotal  =>
      filteredSales.where((t) => t.paymentMethod == 'cash').fold(0.0, (s, t) => s + t.total);
  int    get txnCount   => filteredSales.length;
  bool   get hasMore    => _hasMore;

  List<PosSaleModel> get filteredSales {
    return sales.where((s) {
      final matchPayment = paymentFilter.value == 'All' || s.paymentMethod == paymentFilter.value;
      final matchStatus = statusFilter.value == 'All' || s.status == statusFilter.value;
      return matchPayment && matchStatus;
    }).toList();
  }

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadSales());
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
  }

  String? _fmtDate(DateTime? d) => d?.toIso8601String().split('T').first;

  Future<void> loadSales() async {
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _posRepo.getSales(
        storeId: _storeId,
        sessionId: _sessionId.isEmpty ? null : _sessionId,
        page: _page,
        from: _fmtDate(fromDate.value),
        to: _fmtDate(toDate.value),
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
      );
      sales.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> refreshData() => loadSales();

  void setPaymentFilter(String method) => paymentFilter.value = method;
  void setStatusFilter(String status) => statusFilter.value = status;

  void setDateRange(DateTime? from, DateTime? to) {
    fromDate.value = from;
    toDate.value = to;
    dateFilter.value = (from == null && to == null)
        ? 'All time'
        : '${_fmtDate(from) ?? '…'} → ${_fmtDate(to) ?? '…'}';
    loadSales();
  }

  void openSaleDetail(PosSaleModel sale) => Get.toNamed(Routes.posSaleDetail, arguments: sale.id);

  // ── Full refund (from the list quick-action) ─────────────────────────────
  Future<void> refundSale(PosSaleModel sale) async {
    processingId.value = sale.id;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId();
      final result = await _posRepo.refundSale(sale.id, actingEmployeeId: employeeId);
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not process refund.');
        return;
      }
      final idx = sales.indexWhere((s) => s.id == sale.id);
      if (idx >= 0) {
        sales[idx] = _withStatus(sales[idx], result.newStatus ?? 'refunded', refundedAmount: sale.total);
      }
      CustomAppSnackbar.success(result.message ?? 'Refund processed.');
    } finally {
      processingId.value = '';
    }
  }

  Future<void> voidSale(PosSaleModel sale) async {
    processingId.value = sale.id;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId();
      final ok = await _posRepo.voidSale(sale.id, actingEmployeeId: employeeId);
      if (!ok) return;
      final idx = sales.indexWhere((s) => s.id == sale.id);
      if (idx >= 0) sales[idx] = _withStatus(sales[idx], 'voided');
      CustomAppSnackbar.success('Sale voided and stock restored.');
    } finally {
      processingId.value = '';
    }
  }

  PosSaleModel _withStatus(PosSaleModel sale, String status, {double? refundedAmount}) => PosSaleModel(
        id: sale.id,
        saleNumber: sale.saleNumber,
        storeId: sale.storeId,
        sessionId: sale.sessionId,
        registerId: sale.registerId,
        employeeId: sale.employeeId,
        items: sale.items,
        discount: sale.discount,
        tax: sale.tax,
        subtotal: sale.subtotal,
        total: sale.total,
        paymentMethod: sale.paymentMethod,
        customerName: sale.customerName,
        customerId: sale.customerId,
        notes: sale.notes,
        heldAt: sale.heldAt,
        status: status,
        voidedAt: status == 'voided' ? DateTime.now() : sale.voidedAt,
        refundedAmount: refundedAmount ?? sale.refundedAmount,
        createdAt: sale.createdAt,
      );
}
