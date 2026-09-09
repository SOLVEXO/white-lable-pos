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
  final RxString currencySymbol = '\$'.obs;
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
        final symbol = _settings?.currencySymbol;
        if (symbol != null && symbol.trim().isNotEmpty) currencySymbol.value = symbol;
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
      final result = await _posRepo.refundSale(s.id);
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

  void shareReceipt() {
    final s = sale.value;
    if (s == null) return;
    final sym = currencySymbol.value;
    final buffer = StringBuffer()
      ..writeln('Receipt ${s.saleNumber.isNotEmpty ? s.saleNumber : s.id}')
      ..writeln(s.createdAt.toLocal().toString())
      ..writeln('-' * 28);
    for (final item in s.items) {
      buffer.writeln('${item.name} x${item.qty}  $sym${item.lineTotal.toStringAsFixed(2)}');
    }
    buffer
      ..writeln('-' * 28)
      ..writeln('Subtotal: $sym${s.subtotal.toStringAsFixed(2)}')
      ..writeln('Discount: -$sym${s.discount.toStringAsFixed(2)}')
      ..writeln('Tax: +$sym${s.tax.toStringAsFixed(2)}')
      ..writeln('Total: $sym${s.total.toStringAsFixed(2)}')
      ..writeln('Payment: ${s.paymentMethod}')
      ..writeln('Customer: ${s.customerName}');
    SharePlus.instance.share(ShareParams(text: buffer.toString(), subject: 'Receipt ${s.saleNumber}'));
  }

  /// Shareable PDF receipt — kept alongside [shareReceipt] and
  /// [printReceipt] as the "just email/message it" option that needs no
  /// paired hardware.
  Future<void> shareReceiptPdf() async {
    final s = sale.value;
    if (s == null) return;
    isExportingPdf.value = true;
    try {
      final bytes = await ReceiptPdfBuilder.build(
        sale: s,
        currencySymbol: currencySymbol.value,
        settings: _settings,
      );
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
      final error = await _printerService.printReceipt(
        sale: s,
        currencySymbol: currencySymbol.value,
        settings: _settings,
      );
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
