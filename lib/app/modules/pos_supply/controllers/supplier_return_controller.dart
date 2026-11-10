import 'dart:convert';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

class ReturnLine {
  ReturnLine({required this.variantId, required this.name, required this.max, this.lotId, this.lotNumber, this.sku});
  final String variantId, name;
  final String? lotId, lotNumber, sku;

  /// good + damaged units that came in on the receipt (the server subtracts earlier returns and answers EXCEEDS_RECEIPT)
  final int max;
  final RxInt qty = 0.obs;
  final RxBool fromDamaged = false.obs;
}

/// Sending stock back to a supplier (managers): pick a receipt (or start from one), the quantity of each of its lines (and whether the
/// units come from the damaged pool), a reason and a note. The server creates the credit on the supplier's ledger and answers with it.
/// One `requestId` per submit (same request = same id).
class SupplierReturnController extends GetxController {
  SupplierReturnController({this.receipt, this.supplierId, PosRepository? repository, String? storeId, String Function()? requestIdFactory})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _newId = requestIdFactory ?? newSupplyRequestId;
  final SupplyReceipt? receipt;
  final String? supplierId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final String Function() _newId;

  final Rxn<SupplyReceipt> picked = Rxn<SupplyReceipt>();
  final RxList<SupplyReceipt> receipts = <SupplyReceipt>[].obs;
  final RxList<ReturnLine> lines = <ReturnLine>[].obs;
  final RxString reason = 'other'.obs;
  final RxString note = ''.obs;
  final RxBool loading = false.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final Rxn<SupplierReturnResult> result = Rxn<SupplierReturnResult>();
  String? _requestId, _fingerprint;

  bool _started = false;

  @override
  void onInit() {
    super.onInit();
    start();
  }

  /// Loads what the sheet needs (called by the controller's lifecycle, or by the sheet when the controller was made by hand). Safe to call twice.
  void start() {
    if (_started) return;
    _started = true;
    if (receipt != null) {
      pick(receipt!);
    } else {
      _loadReceipts();
    }
  }

  Future<void> _loadReceipts() async {
    error.value = null;
    if (!supplyOnline()) return;
    loading.value = true;
    final list = await _repo.getSupplyReceipts(await supplyStoreId(_storeIdOverride), supplierId: supplierId);
    if (list == null) {
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the receipts. Try again.');
    } else {
      receipts.assignAll(list);
    }
    loading.value = false;
  }

  Future<void> reload() => _loadReceipts();

  void pick(SupplyReceipt r) {
    picked.value = r;
    lines.assignAll([for (final l in r.lines) ReturnLine(variantId: l.variantId, name: l.name, max: l.qtyTotal, lotId: l.lotId, lotNumber: l.lotNumber, sku: l.sku)]);
  }

  void back() {
    if (receipt == null) picked.value = null;
  }

  bool get hasQuantity => lines.any((l) => l.qty.value > 0);
  bool get canSubmit => picked.value != null && hasQuantity && !busy.value;

  Map<String, dynamic> buildPayload() => {
    'receiptId': picked.value?.id,
    'reason': reason.value,
    if (note.value.trim().isNotEmpty) 'note': note.value.trim(),
    'items': [
      for (final l in lines)
        if (l.qty.value > 0) {'variantId': l.variantId, 'quantity': l.qty.value, if (l.lotId != null) 'lotId': l.lotId, 'fromDamaged': l.fromDamaged.value},
    ],
  };

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    if (picked.value == null || !hasQuantity) {
      error.value = 'Enter how many units go back.';
      return false;
    }
    if (!supplyOnline()) {
      error.value = 'Needs internet.';
      return false;
    }
    final body = buildPayload();
    final fp = jsonEncode(body);
    if (_requestId == null || _fingerprint != fp) {
      _requestId = _newId();
      _fingerprint = fp;
    }
    busy.value = true;
    try {
      final r = await _repo.createSupplierReturn(await supplyStoreId(_storeIdOverride), {...body, 'requestId': _requestId});
      if (!r.success || r.result == null) {
        error.value = supplyFailure(r.code ?? _repo.lastErrorCode, r.message);
        return false;
      }
      result.value = r.result;
      _requestId = null;
      _fingerprint = null;
      return true;
    } finally {
      busy.value = false;
    }
  }

  InvCur? get cur => result.value?.cur;
}
