// G2.7: tax invoice, credit note and return receipt on the thermal path — layout snapshots for 58 mm (32 columns) and 80 mm (48 columns),
// the reserved FBR slots (number / QR / logo), real ESC/POS bytes for both widths, and the print buttons' outcomes.
// Regenerate the snapshots on purpose with:  UPDATE_THERMAL_GOLDENS=1 flutter test test/g27_thermal_documents_test.dart
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'g25_returns_documents_test.dart' show invoiceSale, note;

class _Printer extends Mock implements ThermalPrinterService {}

class _Repo extends Mock implements PosRepository {}

// times are printed in the device's local time zone: the snapshot must not depend on the machine it was made on
String _noClock(String s) => s.replaceAll(RegExp(r'\d{4}-\d\d-\d\d \d\d:\d\d'), '<date time>');

void expectGolden(String name, String raw) {
  final actual = _noClock(raw);
  final f = File('test/golden_thermal/$name.txt');
  if (Platform.environment['UPDATE_THERMAL_GOLDENS'] == '1') {
    f.writeAsStringSync(actual);
    return;
  }
  expect(f.existsSync(), isTrue, reason: 'missing snapshot ${f.path} — run with UPDATE_THERMAL_GOLDENS=1');
  expect(actual, f.readAsStringSync(), reason: 'the thermal layout $name changed; if intended, regenerate with UPDATE_THERMAL_GOLDENS=1');
}

void main() {
  final sale = invoiceSale(extraLine: true);
  final cn = note();

  for (final mm in [58, 80]) {
    final cols = ReceiptEscPosBuilder.columnsFor(mm);
    group('$mm mm ($cols columns)', () {
      test('tax invoice snapshot', () => expectGolden('invoice_$mm', TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(sale, cols: cols), cols)));
      test('credit note snapshot', () => expectGolden('credit_note_$mm', TaxDocumentEscPos.render(TaxDocumentEscPos.creditNote(cn, cols: cols), cols)));
      test('return receipt snapshot', () => expectGolden('return_receipt_$mm', TaxDocumentEscPos.render(TaxDocumentEscPos.returnReceipt(cn, cols: cols, saleNumber: 'POS-00007'), cols)));

      test('no line is ever longer than the paper (nothing is cut off on any document)', () {
        for (final text in [
          TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(sale, cols: cols), cols),
          TaxDocumentEscPos.render(TaxDocumentEscPos.creditNote(cn, cols: cols), cols),
          TaxDocumentEscPos.render(TaxDocumentEscPos.returnReceipt(cn, cols: cols), cols),
        ]) {
          for (final l in text.split('\n')) {
            expect(l.length, lessThanOrEqualTo(cols), reason: l);
          }
        }
      });

      test('the three documents become real ESC/POS bytes (init … cut) for this paper', () async {
        final paper = mm == 58 ? PaperSize.mm58 : PaperSize.mm80;
        for (final lines in [TaxDocumentEscPos.invoice(sale, cols: cols), TaxDocumentEscPos.creditNote(cn, cols: cols), TaxDocumentEscPos.returnReceipt(cn, cols: cols)]) {
          final b = await TaxDocumentEscPos.bytes(lines, paperSize: paper);
          expect(b.take(2), [0x1B, 0x40], reason: 'starts with ESC @');
          expect(b.length, greaterThan(100));
        }
      });
    });
  }

  group('reserved FBR slots', () {
    test('empty slots print NOTHING extra and move nothing', () {
      final plain = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(sale, cols: 48), 48);
      expect(plain, isNot(contains('FBR')));
      expect(plain, isNot(contains('[QR')));
    });

    test('a fiscal number lands directly under the document number; the QR under the totals — and everything else is unchanged', () {
      const f = FiscalSlots(invoiceNumber: 'FBR-123456789', qrPayload: 'https://example/verify/123');
      final base = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(sale, cols: 48), 48).split('\n');
      final withF = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(sale, cols: 48, fiscal: f), 48).split('\n');
      final i = withF.indexWhere((l) => l.contains('INV-000007'));
      expect(withF[i + 1].trim(), 'FBR Invoice No');
      expect(withF[i + 2].trim(), 'FBR-123456789');
      expect(withF.any((l) => l.contains('[QR https://example/verify/123]')), isTrue);
      final stripped = [...withF]..removeRange(i + 1, i + 3);
      final q = stripped.indexWhere((l) => l.contains('[QR'));
      stripped.removeRange(q - 1, q + 1); // the blank line before the QR and the QR itself
      expect(stripped.where((l) => l.isNotEmpty).toList(), base.where((l) => l.isNotEmpty).toList());
    });

    test('the QR is sent to the printer as a real QR command', () async {
      final b = await TaxDocumentEscPos.bytes(TaxDocumentEscPos.invoice(sale, cols: 48, fiscal: const FiscalSlots(qrPayload: 'https://x/y')));
      expect(String.fromCharCodes(b), contains('https://x/y'));
    });
  });

  group('print buttons (controller)', () {
    late _Printer printer;
    late _Repo repo;
    setUp(() {
      Get.testMode = true;
      Get.reset();
      printer = _Printer();
      repo = _Repo();
      when(() => repo.getSaleById(any())).thenAnswer((_) async => sale);
      when(() => repo.getSaleDocuments(any())).thenAnswer((_) async => PosSaleDocuments(saleNumber: 'POS-00007', status: 'completed', creditNotes: [cn]));
      // G4.8: every print here is a reprint — recorded first (no number back = the lines stay exactly the document's)
      when(() => repo.recordReprint(any(), documentType: any(named: 'documentType'), documentId: any(named: 'documentId'), approverToken: any(named: 'approverToken'), kind: any(named: 'kind'))).thenAnswer((_) async => (success: true, code: null, message: null, reprintNumber: null, kind: null));
    });

    Future<PosDocumentsController> make() async {
      final c = PosDocumentsController(repository: repo, saleId: 'sale-1', printer: printer, requirePinCached: (_) async => false);
      Get.put(c);
      await c.load();
      return c;
    }

    test('no printer paired → says so and points at the PDF; nothing is sent', () async {
      when(() => printer.hasSavedPrinter).thenReturn(false);
      final c = await make();
      await c.printInvoice();
      expect(c.printNotice.value, contains('No printer is set up'));
      verifyNever(() => printer.printDocument(any()));
    });

    test('printed → "Printed."; the lines it was asked to print are the invoice / credit note / return receipt for the paper width', () async {
      when(() => printer.hasSavedPrinter).thenReturn(true);
      List<DocLine> Function(int)? built;
      when(() => printer.printDocument(any())).thenAnswer((i) async {
        built = i.positionalArguments.first as List<DocLine> Function(int);
        return null;
      });
      final c = await make();
      await c.printInvoice();
      expect(c.printOk.value, isTrue);
      expect(TaxDocumentEscPos.render(built!(32), 32), contains('TAX INVOICE'));
      await c.printCreditNote(cn);
      expect(TaxDocumentEscPos.render(built!(48), 48), contains('CREDIT NOTE'));
      await c.printReturnReceipt(cn);
      expect(TaxDocumentEscPos.render(built!(48), 48), contains('RETURN RECEIPT'));
    });

    test('the printer refuses → its message plus the PDF fallback; the button is usable again', () async {
      when(() => printer.hasSavedPrinter).thenReturn(true);
      when(() => printer.printDocument(any())).thenAnswer((_) async => 'Bluetooth is turned off. Turn it on to print.');
      final c = await make();
      await c.printCreditNote(cn);
      expect(c.printOk.value, isFalse);
      expect(c.printNotice.value, allOf(contains('Bluetooth is turned off'), contains('PDF')));
      expect(c.busy.value, isFalse);
    });

    test('a printer that throws never crashes the screen', () async {
      when(() => printer.hasSavedPrinter).thenReturn(true);
      when(() => printer.printDocument(any())).thenThrow(Exception('boom'));
      final c = await make();
      await c.printInvoice();
      expect(c.printNotice.value, contains('PDF'));
      expect(c.busy.value, isFalse);
    });
  });
}
