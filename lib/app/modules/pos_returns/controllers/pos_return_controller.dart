import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/refund_instructions.dart';
import 'package:solvexo_pos/utils/return_math.dart';

/// Partial / full RETURN of a completed sale: pick the lines and quantities, say whether each goes back on the shelf, whether the customer
/// has the original receipt, see what it will credit and how it will be paid back (the sale's own tenders), then confirm. The SERVER prices it,
/// decides whether a manager must approve (amount / days / no receipt) and answers with the credit note.
class PosReturnController extends GetxController {
  PosReturnController({PosRepository? repository, String? saleId}) : _repo = repository ?? PosRepository(), _saleIdOverride = saleId;
  final PosRepository _repo;
  final String? _saleIdOverride;

  final Rx<PosSaleModel?> sale = Rx(null);
  final RxBool loading = true.obs;
  final RxBool processing = false.obs;
  final RxnString error = RxnString();
  final RxMap<String, int> qty = <String, int>{}.obs;
  /// saleItemId → false when the units are NOT going back on the shelf (then [restockReason] is required)
  final RxMap<String, bool> restock = <String, bool>{}.obs;
  final RxMap<String, String> restockReason = <String, String>{}.obs;
  final RxBool receiptPresented = true.obs;

  /// Set after a successful return: the credit note ({id, number, totalMinor}), the amount and the instructions per tender.
  final Rxn<Map<String, dynamic>> result = Rxn<Map<String, dynamic>>();
  final RxList<String> resultInstructions = <String>[].obs;
  double resultAmount = 0;

  late final String saleId;

  @override
  void onInit() {
    super.onInit();
    saleId = _saleIdOverride ?? (Get.arguments as String? ?? '');
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    sale.value = saleId.isEmpty ? null : await _repo.getSaleById(saleId);
    if (sale.value == null) error.value = 'Could not load the sale.';
    loading.value = false;
  }

  PosSaleItemModel? _item(String id) => sale.value?.items.firstWhereOrNull((i) => i.saleItemId == id);

  void setQty(String itemId, int q) {
    final it = _item(itemId);
    if (it == null) return;
    final v = q.clamp(0, it.refundableQty);
    if (v == 0) {
      qty.remove(itemId);
    } else {
      qty[itemId] = v;
    }
  }

  void selectAll() {
    final s = sale.value;
    if (s == null) return;
    for (final i in s.items) {
      if (i.saleItemId != null && i.refundableQty > 0) qty[i.saleItemId!] = i.refundableQty;
    }
  }

  void setRestock(String itemId, bool v) {
    restock[itemId] = v;
    if (v) restockReason.remove(itemId);
  }

  bool restocks(String itemId) => restock[itemId] ?? true;
  bool get hasSelection => qty.isNotEmpty;

  /// A line that is NOT going back on the shelf needs a few words why.
  bool get restockReasonsComplete => qty.keys.every((id) => restocks(id) || (_item(id)?.isCustom ?? false) || (restockReason[id] ?? '').trim().isNotEmpty);

  /// What the selected units credit, in minor units: the server's own proration over the stored per-line net + tax. Null when the sale
  /// predates per-line tax (the estimate is then simply not shown).
  int? get estimateMinor {
    final s = sale.value;
    if (s == null || !hasSelection) return null;
    var sum = 0;
    for (final e in qty.entries) {
      final it = _item(e.key);
      if (it == null) continue;
      if (it.netMinor == null || it.taxMinor == null) return null;
      sum += returnCredit(LineAmounts(it.netMinor!, it.taxMinor!), it.qty, it.refundedQty, e.value).totalMinor;
    }
    return sum;
  }

  /// How it will be paid back: the sale's own tenders in the documented order (card / other first, cash last).
  List<String> plan() {
    final s = sale.value;
    final minor = estimateMinor;
    if (s == null || minor == null) return const [];
    final exp = s.currencyExponent;
    final amount = minor / _p10(exp);
    final splits = posAllocateRefund(tenders: [for (final p in s.paymentLines) (method: p.method, amount: p.amount)], alreadyRefunded: s.refundedAmount, amount: amount, exponent: exp);
    return posRefundInstructions(splits, currency: s.currency, exponent: exp);
  }

  static num _p10(int e) => e <= 0 ? 1 : List.filled(e, 10).fold<num>(1, (a, b) => a * b);

  List<Map<String, dynamic>> _items() => [
        for (final e in qty.entries)
          {
            'saleItemId': e.key,
            'qty': e.value,
            if (!restocks(e.key)) ...{'restock': false, 'restockReason': (restockReason[e.key] ?? '').trim()},
          },
      ];

  /// Confirm. Guarded against a double tap (one request in flight, the reason picker and the approval sheet included).
  Future<bool> confirm({bool all = false}) async {
    final s = sale.value;
    if (s == null || processing.value) return false;
    if (!all && !hasSelection) return false;
    if (!all && !restockReasonsComplete) {
      error.value = 'Say why the items that are not going back on the shelf are not restocked.';
      return false;
    }
    processing.value = true;
    error.value = null;
    try {
      final why = await ReasonPicker.ask(PosReasonKind.refund);
      if (why == null) return false;
      final items = all ? null : _items();
      var r = await _repo.refundSale(s.id, items: items, reasonCode: why.code, reason: why.note, receiptPresented: receiptPresented.value ? null : false);
      if (!r.success && _repo.lastErrorCode == 'RETURN_NEEDS_MANAGER') {
        final token = await ManagerApproval.request(reason: _approvalText(_repo.lastErrorReasons), repository: _repo);
        if (token == null) return false;
        r = await _repo.refundSale(s.id, items: items, reasonCode: why.code, reason: why.note, receiptPresented: receiptPresented.value ? null : false, approverToken: token);
      }
      if (!r.success) {
        final code = _repo.lastErrorCode;
        error.value = switch (code) {
          'OPEN_SHIFT_REQUIRED' => 'Open a shift on this register before paying a cash refund.',
          'RESTOCK_REASON_REQUIRED' => 'Say why the items that are not going back on the shelf are not restocked.',
          'RETURN_NEEDS_MANAGER' => 'A manager must approve this return.',
          _ => r.message ?? 'Could not process the return.',
        };
        return false;
      }
      resultAmount = r.refundedAmount ?? 0;
      resultInstructions.assignAll(posRefundInstructions(
        [for (final t in r.tenders) PosRefundSplit(t.method, t.amount)],
        currency: s.currency,
        exponent: s.currencyExponent,
      ));
      result.value = _repo.lastCreditNote ?? {};
      return true;
    } finally {
      processing.value = false;
    }
  }

  static String _approvalText(List<String> reasons) {
    final parts = <String>[
      for (final r in reasons)
        switch (r) {
          'amount_above_limit' => 'the amount is above the limit',
          'too_many_days_since_sale' => 'it is later than the allowed days after the sale',
          'no_original_receipt' => 'the customer has no original receipt',
          _ => '',
        },
    ].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? 'A manager must approve this return.' : 'A manager must approve this return: ${parts.join(', ')}.';
  }

  String money(num minor) {
    final s = sale.value;
    return Money.format(minor / _p10(s?.currencyExponent ?? 2), currency: s?.currency, exponent: s?.currencyExponent);
  }
}
