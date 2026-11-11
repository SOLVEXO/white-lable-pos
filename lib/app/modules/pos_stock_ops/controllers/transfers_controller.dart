import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/store_locations_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

/// G4.6 stock transfers between the store's locations: the list (by status), ship a variant from one location to another, receive (part of) an
/// open transfer, cancel one nothing of which has arrived. Online only; the permission matrix decides who may ship / receive (refusals in words).
class TransfersController extends GetxController {
  TransfersController({PosRepository? repository, Future<List<StoreLocationModel>> Function(String storeId)? locations, String? storeId})
    : _repo = repository ?? PosRepository(),
      _locations = locations ?? StoreLocationsRepository().getLocations,
      _storeIdOverride = storeId;

  final PosRepository _repo;
  final Future<List<StoreLocationModel>> Function(String) _locations;
  final String? _storeIdOverride;

  static const statuses = <(String, String)>[('open', 'Open'), ('received', 'Received'), ('cancelled', 'Cancelled'), ('all', 'All')];

  final RxList<StockTransfer> transfers = <StockTransfer>[].obs;
  final RxString status = 'open'.obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString actionError = RxnString();
  final RxnString notice = RxnString();
  final RxList<StoreLocationModel> locations = <StoreLocationModel>[].obs;
  int _ticket = 0;
  Worker? _online;

  @override
  void onInit() {
    super.onInit();
    load();
    _loadLocations();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && transfers.isEmpty) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> _loadLocations() async {
    try {
      final all = await _locations(await reportsStoreId(_storeIdOverride));
      locations.assignAll(all.where((l) => l.status != 'inactive' && l.status != 'archived'));
    } catch (_) {
      /* the ship form says there are no locations */
    }
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    final ticket = ++_ticket;
    loading.value = true;
    // "open" = in transit + partly received: one read, filtered here (the server filters one status at a time)
    final r = await _repo.getTransfers(await reportsStoreId(_storeIdOverride), status: status.value == 'open' ? 'all' : status.value);
    if (ticket != _ticket) return;
    if (r == null) {
      error.value = stockOpsErrorMessage(_repo.lastErrorCode, message: 'Could not load the transfers. Try again.');
    } else {
      transfers.assignAll(status.value == 'open' ? r.where((t) => t.open) : r);
    }
    loading.value = false;
  }

  void setStatus(String s) {
    status.value = s;
    load();
  }

  /// Products to ship (the till's product search).
  Future<List<PosProductModel>> search(String q) async {
    if (q.trim().length < 2) return const [];
    try {
      return await _repo.searchProducts(storeId: await reportsStoreId(_storeIdOverride), q: q.trim());
    } catch (_) {
      return const [];
    }
  }

  Future<bool> ship({required String variantId, required String fromLocationId, required String toLocationId, required int quantity, String? note}) async {
    if (fromLocationId == toLocationId) {
      actionError.value = 'Choose two different locations.';
      return false;
    }
    if (quantity <= 0) {
      actionError.value = 'Enter how many to send.';
      return false;
    }
    return _write(
      () async => _repo.shipTransfer(await reportsStoreId(_storeIdOverride), variantId: variantId, fromLocationId: fromLocationId, toLocationId: toLocationId, quantity: quantity, note: note),
      'Sent. It shows here until it is received.',
    );
  }

  Future<bool> receive(StockTransfer t, int qty) {
    if (qty <= 0 || qty > t.outstanding) {
      actionError.value = 'Receive between 1 and ${t.outstanding}.';
      return Future.value(false);
    }
    return _write(() async => _repo.receiveTransfer(await reportsStoreId(_storeIdOverride), t.id, qty), qty == t.outstanding ? 'Received in full.' : 'Received $qty of ${t.outstanding}.');
  }

  Future<bool> cancel(StockTransfer t) => _write(() async => _repo.cancelTransfer(await reportsStoreId(_storeIdOverride), t.id), 'Cancelled. The stock is back at ${t.fromLocationName}.');

  Future<bool> _write(Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> Function() run, String done) async {
    actionError.value = null;
    notice.value = null;
    if (!reportsOnline()) {
      actionError.value = 'Transfers need an internet connection.';
      return false;
    }
    if (busy.value) return false;
    busy.value = true;
    try {
      final r = await run();
      if (!r.success) {
        actionError.value = stockOpsErrorMessage(r.code, message: r.message);
        return false;
      }
      notice.value = done;
      await load();
      return true;
    } finally {
      busy.value = false;
    }
  }
}
