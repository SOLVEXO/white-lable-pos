import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';
import 'package:solvexo_pos/app/data/services/reprint_gate.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart' show SettingsCacheStore;

/// The tax invoice of a sale and its credit notes: load, share as PDF (print from the share sheet) and share the public link.
class PosDocumentsController extends GetxController {
  PosDocumentsController({PosRepository? repository, String? saleId, Future<void> Function(ShareParams)? share, ThermalPrinterService? printer, ReprintGate? reprintGate, Future<bool> Function(String storeId)? requirePinCached})
      : _repo = repository ?? PosRepository(),
        _gateOverride = reprintGate,
        _requirePin = requirePinCached ?? _cachedRequirePin,
        _printerOverride = printer,
        _saleIdOverride = saleId,
        _share = share ?? ((p) async => SharePlus.instance.share(p));
  final PosRepository _repo;
  final String? _saleIdOverride;
  final Future<void> Function(ShareParams) _share;
  final ThermalPrinterService? _printerOverride;
  final ReprintGate? _gateOverride;
  late final ReprintGate _gate = _gateOverride ?? ReprintGate(repository: _repo);
  final Future<bool> Function(String storeId) _requirePin;

  /// the store's "require PIN to reprint" as last cached on this till (for an offline reprint)
  static Future<bool> _cachedRequirePin(String storeId) async => (await SettingsCacheStore.instance.load(storeId))?.settings.requirePinForReprint ?? false;

  /// G4.8: record the print first (a manager PIN when a REPRINT needs one); null = stop (the reason is in [printNotice]).
  /// G4.9: a document not printed yet asks for its `original`; the server's answer is printed — ORIGINAL, REPRINT #n, or COPY when offline (unrecorded).
  Future<({int? number, bool original, bool copy})?> _recordReprint(String type, String id) async {
    final s = sale.value;
    if (s == null) return null;
    final go = await _gate.record(storeId: s.storeId, documentType: type, documentId: id, requirePinCached: await _requirePin(s.storeId), kind: isPrinted(type, id) ? 'reprint' : 'original');
    if (!go.ok) {
      _notice('$type:$id', go.message);
      return null;
    }
    if (go.original || go.number != null) printedIds.add('$type:$id');
    return (number: go.number, original: go.original, copy: !go.original && go.number == null);
  }

  /// G4.9: documents printed at least once — from the server's documents read-out, plus what this screen printed since it loaded
  final RxSet<String> printedIds = <String>{}.obs;
  bool isPrinted(String type, String id) =>
      printedIds.contains('$type:$id') || (type == 'invoice' ? documents.value?.invoicePrinted == true : creditNotes.any((n) => n.id == id && n.printed));
  ThermalPrinterService? get _printer => _printerOverride ?? (Get.isRegistered<ThermalPrinterService>() ? Get.find<ThermalPrinterService>() : null);

  /// Outcome of the last print attempt (null = nothing yet): `printed` or the printer's own message — the PDF share is always the fallback.
  final RxnString printNotice = RxnString();
  final RxBool printOk = false.obs;

  /// G5.1: which document the notice belongs to (`invoice:<saleId>` / `credit_note:<id>`) — a screen shows only its own document's notice
  final RxnString noticeDoc = RxnString();
  String? noticeFor(String doc) => noticeDoc.value == doc ? printNotice.value : null;
  void _notice(String doc, String? msg, {bool ok = false}) {
    noticeDoc.value = doc;
    printOk.value = ok;
    printNotice.value = msg;
  }

  final Rx<PosSaleModel?> sale = Rx(null);
  final Rx<PosSaleDocuments?> documents = Rx(null);
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  late final String saleId;

  List<PosCreditNote> get creditNotes => documents.value?.creditNotes ?? const [];

  @override
  void onInit() {
    super.onInit();
    saleId = _saleIdOverride ?? (Get.arguments is Map ? (Get.arguments as Map)['saleId'] as String? ?? '' : Get.arguments as String? ?? '');
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    final results = await Future.wait([_repo.getSaleById(saleId), _repo.getSaleDocuments(saleId)]);
    sale.value = results[0] as PosSaleModel?;
    documents.value = results[1] as PosSaleDocuments?;
    if (sale.value == null) error.value = 'Could not load the invoice.';
    loading.value = false;
  }

  PosCreditNote? note(String number) => creditNotes.firstWhereOrNull((n) => n.number == number);

  Future<void> shareInvoicePdf() => _guard(() async {
        final s = sale.value;
        if (s == null) return;
        final bytes = await TaxDocumentPdf.invoice(sale: s);
        await _share(ShareParams(files: [XFile.fromData(Uint8List.fromList(bytes), name: 'invoice-${s.invoice?.number ?? s.saleNumber}.pdf', mimeType: 'application/pdf')], subject: 'Tax invoice ${s.invoice?.number ?? s.saleNumber}'));
      });

  Future<void> shareCreditNotePdf(PosCreditNote n) => _guard(() async {
        final bytes = await TaxDocumentPdf.creditNote(note: n);
        await _share(ShareParams(files: [XFile.fromData(Uint8List.fromList(bytes), name: 'credit-note-${n.number}.pdf', mimeType: 'application/pdf')], subject: 'Credit note ${n.number}'));
      });

  /// The public page for the customer: the invoice view (`/invoice`) or a credit note page — behind the sale's unguessable receipt link.
  Future<void> shareLink({String? creditNoteNumber}) => _guard(() async {
        final url = await _repo.getReceiptLink(saleId);
        if (url == null) {
          error.value = 'The link could not be created right now. Try again when you are online.';
          return;
        }
        final target = creditNoteNumber == null ? '$url/invoice' : '$url/credit-note/$creditNoteNumber';
        await _share(ShareParams(text: target, subject: creditNoteNumber ?? 'Tax invoice'));
      });

  /// Thermal printing (58 / 80 mm per Settings → Receipt Printer). No printer paired → says so and points at the PDF.
  Future<void> _print(String doc, List<DocLine> Function(int cols) build) async {
    if (busy.value) return;
    busy.value = true;
    _notice(doc, null);
    try {
      final pr = _printer;
      if (pr == null || !pr.hasSavedPrinter) {
        _notice(doc, 'No printer is set up. Go to Settings → Receipt printer, or share the PDF.');
        return;
      }
      final err = await pr.printDocument(build);
      _notice(doc, err == null ? 'Printed.' : '$err You can also share it as a PDF.', ok: err == null);
    } catch (_) {
      _notice(doc, 'Printing failed. You can share it as a PDF instead.');
    } finally {
      busy.value = false;
    }
  }

  Future<void> printInvoice() async {
    final s = sale.value;
    if (s == null) return;
    final r = await _recordReprint('invoice', s.id);
    if (r == null) return;
    return _print('invoice:${s.id}', (cols) => TaxDocumentEscPos.invoice(s, cols: cols, reprintNumber: r.number, original: r.original, copy: r.copy));
  }

  Future<void> printCreditNote(PosCreditNote n) async {
    final r = await _recordReprint('credit_note', n.id);
    if (r == null) return;
    return _print('credit_note:${n.id}', (cols) => TaxDocumentEscPos.creditNote(n, cols: cols, reprintNumber: r.number, original: r.original, copy: r.copy));
  }

  Future<void> printReturnReceipt(PosCreditNote n) => _print('credit_note:${n.id}', (cols) => TaxDocumentEscPos.returnReceipt(n, cols: cols, saleNumber: sale.value?.saleNumber));

  Future<void> _guard(Future<void> Function() f) async {
    if (busy.value) return; // double-tap protection
    busy.value = true;
    error.value = null;
    try {
      await f();
    } catch (_) {
      error.value = 'Could not share the document.';
    } finally {
      busy.value = false;
    }
  }
}
