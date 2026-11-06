import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';

/// The tax invoice of a sale and its credit notes: load, share as PDF (print from the share sheet) and share the public link.
class PosDocumentsController extends GetxController {
  PosDocumentsController({PosRepository? repository, String? saleId, Future<void> Function(ShareParams)? share})
      : _repo = repository ?? PosRepository(),
        _saleIdOverride = saleId,
        _share = share ?? ((p) async => SharePlus.instance.share(p));
  final PosRepository _repo;
  final String? _saleIdOverride;
  final Future<void> Function(ShareParams) _share;

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
