import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'dart:typed_data';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/reprint_gate.dart';
import 'package:share_plus/share_plus.dart';

class PosSaleDetailController extends GetxController {
  PosSaleDetailController({PosRepository? posRepository, ThermalPrinterService? printerService, ReprintGate? reprintGate})
      : _posRepo = posRepository ?? PosRepository(),
        _printerService = printerService ?? Get.find<ThermalPrinterService>(),
        _gateOverride = reprintGate;

  final PosRepository _posRepo;
  final ThermalPrinterService _printerService;
  final ReprintGate? _gateOverride;
  late final ReprintGate _gate = _gateOverride ?? ReprintGate(repository: _posRepo);

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

  /// Set when this sale was rung up offline: the provisional number (`OFF-…`) printed on the customer's first receipt.
  final RxnString offlineRef = RxnString();

  /// saleItemId -> qty selected for partial refund

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
      await _loadOfflineRef();
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

  Future<void> _loadOfflineRef() async {
    try {
      final s = sale.value;
      if (s == null || !Get.isRegistered<PendingSaleSyncService>()) return;
      final rec = await Get.find<PendingSaleSyncService>().offlineReceiptForSale(s.saleNumber.isNotEmpty ? s.saleNumber : s.id) ??
          await Get.find<PendingSaleSyncService>().offlineReceiptForSale(s.id);
      offlineRef.value = rec?.provisionalNumber;
    } catch (_) {
      offlineRef.value = null; // purely informational
    }
  }

  Future<void> discard() async {
    final s = sale.value;
    if (s == null || isProcessing.value) return;
    isProcessing.value = true;
    try {
      final why = await ReasonPicker.ask(PosReasonKind.discard);
      if (why == null) return;
      final ok = await _posRepo.discardSale(s.id, reasonCode: why.code, reason: why.note);
      if (ok) {
        CustomAppSnackbar.success('Held sale discarded.');
        Get.back();
      }
    } finally {
      isProcessing.value = false;
    }
  }

  /// A reprint/copy of the sale's receipt, rendered from the single [ReceiptData] model.
  ReceiptData _receipt(PosSaleModel s, {bool asciiSafeMoney = false, String? receiptUrl}) =>
      ReceiptData.fromSale(s, _settings, isCopy: true, asciiSafeMoney: asciiSafeMoney, offlineRef: offlineRef.value, receiptUrl: receiptUrl);

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
      // G4.8: the reprint is recorded first (a manager PIN when the store requires it); the print says "REPRINT #n"
      final go = await _gate.record(storeId: s.storeId, documentType: 'sale', documentId: s.id, requirePinCached: _settings?.requirePinForReprint ?? false);
      if (!go.ok) {
        CustomAppSnackbar.error(go.message ?? 'The reprint was not recorded.');
        return;
      }
      // G4.8: the designer's QR = the public digital-receipt link (only when online; a reprint offline prints without it)
      final url = (_settings?.receiptOptions.showQr ?? true) ? await _posRepo.getReceiptLink(s.id).catchError((_) => null) : null;
      final error = await _printerService.printReceipt(receipt: _receipt(s, asciiSafeMoney: true, receiptUrl: url).copyWith(reprintNumber: go.number));
      if (error != null) {
        // The receipt is never lost: offer the PDF/share route right away.
        CustomAppSnackbar.error('$error You can also share it as PDF.');
      } else {
        CustomAppSnackbar.success('Receipt printed.');
      }
    } finally {
      isPrinting.value = false;
    }
  }
}
