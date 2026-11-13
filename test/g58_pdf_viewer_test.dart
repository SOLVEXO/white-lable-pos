// G5.8: the in-app PDF viewer — receipt, tax invoice, credit note and an expense's PDF attachment open in the viewer (view, print, share);
// the existing "Share PDF" buttons stay.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/expense_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_pdf_viewer/pdf_viewer_view.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'g25_returns_documents_test.dart' show invoiceSale, note;
import 'support/g35_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

bool _isPdf(Uint8List b) => b.length > 4 && String.fromCharCodes(b.sublist(0, 4)) == '%PDF';

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(430, 1400));
  await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: w)));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  late _Repo repo;
  late List<PdfDoc> opened;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = _Repo();
    opened = [];
    when(() => repo.lastErrorCode).thenReturn(null);
  });
  Future<void> open(PdfDoc d) async => opened.add(d);

  group('tax invoice and credit note', () {
    test('View PDF opens the same document the share button sends, with its number in the title and file name', () async {
      final sale = invoiceSale();
      final PosCreditNote cn = note();
      when(() => repo.getSaleById(any())).thenAnswer((_) async => sale);
      when(() => repo.getSaleDocuments(any())).thenAnswer((_) async => PosSaleDocuments(saleNumber: sale.saleNumber, status: 'completed', creditNotes: [cn]));
      final c = PosDocumentsController(repository: repo, saleId: sale.id, requirePinCached: (_) async => false, openPdf: open);
      Get.put(c);
      await c.load();
      await c.viewInvoicePdf();
      await c.viewCreditNotePdf(cn);
      final no = sale.invoice?.number ?? sale.saleNumber;
      expect(opened.map((d) => d.title), ['Tax invoice $no', 'Credit note ${cn.number}']);
      expect(opened.map((d) => d.fileName), ['invoice-$no.pdf', 'credit-note-${cn.number}.pdf']);
      for (final d in opened) {
        expect(_isPdf(await d.bytes()), isTrue);
      }
    });
  });

  group('sale receipt', () {
    test('View PDF opens the receipt PDF', () async {
      Get.put<ThermalPrinterService>(ThermalPrinterService());
      final c = PosSaleDetailController(posRepository: repo);
      c.saleId = 'sale-1';
      c.sale.value = invoiceSale();
      await c.viewReceiptPdf(open: open);
      expect(opened.single.title, 'Receipt ${c.sale.value!.saleNumber}');
      expect(opened.single.fileName, endsWith('.pdf'));
      expect(_isPdf(await opened.single.bytes()), isTrue);
    });
  });

  group('expense PDF attachment', () {
    late List<String> fetched;
    ExpenseDetailController make() {
      fetched = [];
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) async => expense(hasReceipt: true, receiptMime: 'application/pdf'));
      return Get.put(
        ExpenseDetailController(
          expenseId: 'x1',
          repository: repo,
          storeId: 'st1',
          openPdf: open,
          fetchBytes: (url) async {
            fetched.add(url);
            return Uint8List.fromList('%PDF-1.4'.codeUnits);
          },
        ),
        tag: 'x1',
      );
    }

    testWidgets('"View PDF receipt" fetches a FRESH link each time and the viewer downloads from it (no "open it on the web" note)', (t) async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);
      var n = 0;
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => ReceiptLink(url: 'https://signed.example/${++n}', mimeType: 'application/pdf'));
      final c = make();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      expect(find.textContaining('web dashboard'), findsNothing);
      await t.tap(find.byKey(const Key('viewReceiptPdf')));
      await t.pump();
      await t.tap(find.byKey(const Key('viewReceiptPdf')));
      await t.pump();
      expect(opened.length, 2);
      expect(opened.first.fileName, startsWith('expense-receipt'));
      await opened.first.bytes();
      await opened.last.bytes();
      expect(fetched, ['https://signed.example/1', 'https://signed.example/2']);
    });

    testWidgets('offline: "Needs internet." and nothing opens', (t) async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = make();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      await c.viewReceiptPdf();
      await t.pump();
      expect(c.receiptError.value, 'Needs internet.');
      expect(opened, isEmpty);
      verifyNever(() => repo.getExpenseReceiptLink(any(), any()));
    });

    testWidgets('no link from the server: an error in place, nothing opens', (t) async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => null);
      final c = make();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      await c.viewReceiptPdf();
      await t.pump();
      expect(c.receiptError.value, isNotNull);
      expect(opened, isEmpty);
    });
  });
}
