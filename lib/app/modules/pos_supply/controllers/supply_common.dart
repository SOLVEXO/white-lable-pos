import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Shared helpers of the G3.4 supply controllers. Supply is ONLINE-ONLY (apart from the read-only last-synced order list), so the
/// connectivity source is the same one the other online-only G3 screens use.
Future<String> supplyStoreId(String? override) => invStoreId(override);

/// The till's connectivity as an observable (a till with no status service is assumed online).
RxBool supplyOnlineRx() => customersOnlineRx();
bool supplyOnline() => customersOnline();

/// A first guess of the role BEFORE the server answers (it only decides what is shown; the server enforces every rule).
Future<bool> supplyGuessCanManage() async => InvRole.canManage(await invGuessRole());

typedef SupplyApprovalRequester = Future<String?> Function({required String reason, PosRepository? repository});

/// The text of a failed write: the server's own sentence for the codes where it names the product and the number
/// (OVER_RECEIPT, LOT_REQUIRED), otherwise the plain-English message of the code.
String supplyFailure(String? code, String? message) =>
    (code == 'OVER_RECEIPT' || code == 'LOT_REQUIRED') && message != null && message.isNotEmpty ? message : supplyErrorMessage(code, fallback: message);

/// Debounced search of EXISTING products (the inventory search endpoint) for adding lines to a purchase order or a receipt.
/// Unlimited-stock items cannot be received, so they are left out. The newest search always wins.
class SupplyProductSearch {
  SupplyProductSearch({required PosRepository repository, required Future<String> Function() storeId, this.debounce = const Duration(milliseconds: 350)}) : _repo = repository, _storeId = storeId;
  final PosRepository _repo;
  final Future<String> Function() _storeId;
  final Duration debounce;

  final RxList<InvRow> results = <InvRow>[].obs;
  final RxBool searching = false.obs;
  final RxnString error = RxnString();
  final Rxn<InvCur> cur = Rxn<InvCur>();
  Timer? _timer;
  int _ticket = 0;

  void onChanged(String q) {
    _timer?.cancel();
    _timer = Timer(debounce, () => search(q));
  }

  Future<void> search(String q) async {
    final ticket = ++_ticket;
    final text = q.trim();
    if (text.isEmpty) {
      results.clear();
      error.value = null;
      searching.value = false;
      return;
    }
    searching.value = true;
    error.value = null;
    final page = await _repo.getInventoryStock(await _storeId(), search: text, limit: 20);
    if (ticket != _ticket) return;
    if (page == null) {
      results.clear();
      error.value = _repo.lastErrorCode == null ? 'Needs internet to search products.' : supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not search the products.');
    } else {
      results.assignAll(page.items.where((r) => !r.unlimited));
      cur.value = page.cur;
    }
    searching.value = false;
  }

  void dispose() => _timer?.cancel();
}
