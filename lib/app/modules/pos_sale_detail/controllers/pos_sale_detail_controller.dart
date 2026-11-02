import 'package:solvexo_pos/app/components/refund_done_dialog.dart';
import 'package:solvexo_pos/utils/refund_instructions.dart';
import 'package:solvexo_pos/utils/pos_totals.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'dart:typed_data';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

class PosSaleDetailController extends GetxController {
  PosSaleDetailController({PosRepository? posRepository, ThermalPrinterService? printerService})
      : _posRepo = posRepository ?? PosRepository(),
        _printerService = printerService ?? Get.find<ThermalPrinterService>();

  final PosRepository _posRepo;
  final ThermalPrinterService _printerService;

  final RxBool isLoading = true.obs;
  final RxBool isProcessing = false.obs;
  final RxBool isExportingPdf = false.obs;
  final RxBool isPrinting = false.obs;
  bool get hasSavedPrinter => _printerService.hasSavedPrinter;
  final Rx<PosSaleModel?> sale = Rx(null);
  final RxString currencySymbol = Money.symbol().obs;
  /// See PosRole.isCurrentEmployeeManager's doc comment — gates the
  /// refund/void actions to match the backend's actual (if weak) check.
  final RxBool isManager = false.obs;
  PosSettingsModel? _settings;

  /// saleItemId -> qty selected for partial refund
  final RxMap<String, int> refundSelection = <String, int>{}.obs;

  late final String saleId;

  @override
  void onInit() {
    super.onInit();
    saleId = Get.arguments as String? ?? '';
    _load();
    PosRole.isCurrentEmployeeManager().then((v) => isManager.value = v);
  }

  Future<void> _load() async {
    if (saleId.isEmpty) return;
    isLoading.value = true;
    try {
      sale.value = await _posRepo.getSaleById(saleId);
      final storeId = sale.value?.storeId;
      if (storeId != null && storeId.isNotEmpty) {
        _settings = await _posRepo.getPosSettings(storeId);
        currencySymbol.value = Money.symbol(); // from the store's currency code, never free text
      }
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

  /// What the server will refund for the selected units: their share of what was paid (discount and tax
  /// pro-rated), not the sticker price. Display only — the server computes the real amount.
  double get selectedRefundAmount {
    final s = sale.value;
    if (s == null) return 0;
    final lines = <({double price, int qty})>[];
    var completes = true;
    for (final item in s.items) {
      final qty = refundSelection[item.saleItemId] ?? 0;
      if (qty > 0) lines.add((price: item.price, qty: qty));
      if (item.refundedQty + qty < item.qty) completes = false;
    }
    if (lines.isEmpty) return 0;
    return posPartialRefundAmount(
      subtotal: s.subtotal,
      total: s.total,
      alreadyRefunded: s.refundedAmount,
      lines: lines,
      completesSale: completes,
      exponent: s.currencyExponent,
    );
  }

  /// What the cashier will have to do for a refund of [amount] on this sale, per tender (card machine / cash).
  List<String> refundPlan(double amount) {
    final s = sale.value;
    if (s == null) return const [];
    final splits = posAllocateRefund(
      tenders: [for (final p in s.paymentLines) (method: p.method, amount: p.amount)],
      alreadyRefunded: s.refundedAmount,
      amount: amount,
      exponent: s.currencyExponent,
    );
    return posRefundInstructions(splits, currency: s.currency, exponent: s.currencyExponent);
  }

  Future<void> refundFull() async {
    final s = sale.value;
    if (s == null) return;
    isProcessing.value = true;
    try {
      final result = await _posRepo.refundSale(s.id);
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not process refund.');
        return;
      }
      CustomAppSnackbar.success(result.message ?? 'Sale fully refunded.');
      await showRefundDoneDialog(s, result.tenders, result.refundedAmount);
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
      final items = refundSelection.entries
          .map((e) => {'saleItemId': e.key, 'qty': e.value})
          .toList();
      final result = await _posRepo.refundSale(s.id, items: items);
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not process refund.');
        return;
      }
      CustomAppSnackbar.success(result.message ?? 'Partial refund processed.');
      refundSelection.clear();
      await showRefundDoneDialog(s, result.tenders, result.refundedAmount);
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
      final ok = await _posRepo.voidSale(s.id, reason: reason);
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

  /// A reprint/copy of the sale's receipt, rendered from the single [ReceiptData] model.
  ReceiptData _receipt(PosSaleModel s, {bool asciiSafeMoney = false}) =>
      ReceiptData.fromSale(s, _settings, isCopy: true, asciiSafeMoney: asciiSafeMoney);

  void shareReceipt() {
    final s = sale.value;
    if (s == null) return;
    SharePlus.instance.share(ShareParams(text: _receipt(s).toPlainText(), subject: 'Receipt ${s.saleNumber}'));
  }

  /// Shareable PDF receipt — kept alongside [shareReceipt] and
  /// [printReceipt] as the "just email/message it" option that needs no
  /// paired hardware.
  Future<void> shareReceiptPdf() async {
    final s = sale.value;
    if (s == null) return;
    isExportingPdf.value = true;
    try {
      final bytes = await ReceiptPdfBuilder.build(data: _receipt(s));
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'receipt-${s.saleNumber.isNotEmpty ? s.saleNumber : s.id}.pdf',
        mimeType: 'application/pdf',
      );
      await SharePlus.instance.share(ShareParams(files: [file], subject: 'Receipt ${s.saleNumber}'));
    } catch (e) {
      CustomAppSnackbar.error('Failed to generate receipt PDF.');
    } finally {
      isExportingPdf.value = false;
    }
  }

  /// Prints to the paired thermal printer set in Settings → Receipt
  /// Printer. See ThermalPrinterService's doc comment for why a failure
  /// here is just an error, not something queued/retried like a sale.
  Future<void> printReceipt() async {
    final s = sale.value;
    if (s == null) return;
    if (!hasSavedPrinter) {
      CustomAppSnackbar.warning('No printer set up. Go to Settings → Receipt Printer.');
      return;
    }
    isPrinting.value = true;
    try {
      final error = await _printerService.printReceipt(receipt: _receipt(s, asciiSafeMoney: true));
      if (error != null) {
        CustomAppSnackbar.error(error);
      } else {
        CustomAppSnackbar.success('Receipt printed.');
      }
    } finally {
      isPrinting.value = false;
    }
  }
}
