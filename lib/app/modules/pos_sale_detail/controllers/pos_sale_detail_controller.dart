import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

class PosSaleDetailController extends GetxController {
  final _posRepo = PosRepository();

  final RxBool isLoading = true.obs;
  final RxBool isProcessing = false.obs;
  final Rx<PosSaleModel?> sale = Rx(null);

  /// saleItemId -> qty selected for partial refund
  final RxMap<String, int> refundSelection = <String, int>{}.obs;

  late final String saleId;

  @override
  void onInit() {
    super.onInit();
    saleId = Get.arguments as String? ?? '';
    _load();
  }

  Future<void> _load() async {
    if (saleId.isEmpty) return;
    isLoading.value = true;
    try {
      sale.value = await _posRepo.getSaleById(saleId);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshData() => _load();

  void setRefundQty(String saleItemId, int qty) {
    if (qty <= 0) {
      refundSelection.remove(saleItemId);
    } else {
      refundSelection[saleItemId] = qty;
    }
  }

  double get selectedRefundAmount {
    final s = sale.value;
    if (s == null) return 0;
    var total = 0.0;
    for (final item in s.items) {
      final qty = refundSelection[item.saleItemId];
      if (qty != null && item.qty > 0) {
        total += (item.lineTotal / item.qty) * qty;
      }
    }
    return total;
  }

  Future<void> refundFull() async {
    final s = sale.value;
    if (s == null) return;
    isProcessing.value = true;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId();
      final result = await _posRepo.refundSale(s.id, actingEmployeeId: employeeId);
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not process refund.');
        return;
      }
      CustomAppSnackbar.success(result.message ?? 'Sale fully refunded.');
      await _load();
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> refundPartial() async {
    final s = sale.value;
    if (s == null || refundSelection.isEmpty) return;
    isProcessing.value = true;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId();
      final items = refundSelection.entries
          .map((e) => {'saleItemId': e.key, 'qty': e.value})
          .toList();
      final result = await _posRepo.refundSale(s.id, items: items, actingEmployeeId: employeeId);
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not process refund.');
        return;
      }
      CustomAppSnackbar.success(result.message ?? 'Partial refund processed.');
      refundSelection.clear();
      await _load();
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> voidSale({String? reason}) async {
    final s = sale.value;
    if (s == null) return;
    isProcessing.value = true;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId();
      final ok = await _posRepo.voidSale(s.id, reason: reason, actingEmployeeId: employeeId);
      if (!ok) return;
      CustomAppSnackbar.success('Sale voided and stock restored.');
      await _load();
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> discard() async {
    final s = sale.value;
    if (s == null) return;
    isProcessing.value = true;
    try {
      final ok = await _posRepo.discardSale(s.id);
      if (ok) {
        CustomAppSnackbar.success('Held sale discarded.');
        Get.back();
      }
    } finally {
      isProcessing.value = false;
    }
  }

  void shareReceipt() {
    final s = sale.value;
    if (s == null) return;
    final buffer = StringBuffer()
      ..writeln('Receipt ${s.saleNumber.isNotEmpty ? s.saleNumber : s.id}')
      ..writeln(s.createdAt.toLocal().toString())
      ..writeln('-' * 28);
    for (final item in s.items) {
      buffer.writeln('${item.name} x${item.qty}  \$${item.lineTotal.toStringAsFixed(2)}');
    }
    buffer
      ..writeln('-' * 28)
      ..writeln('Subtotal: \$${s.subtotal.toStringAsFixed(2)}')
      ..writeln('Discount: -\$${s.discount.toStringAsFixed(2)}')
      ..writeln('Tax: +\$${s.tax.toStringAsFixed(2)}')
      ..writeln('Total: \$${s.total.toStringAsFixed(2)}')
      ..writeln('Payment: ${s.paymentMethod}')
      ..writeln('Customer: ${s.customerName}');
    SharePlus.instance.share(ShareParams(text: buffer.toString(), subject: 'Receipt ${s.saleNumber}'));
  }
}
