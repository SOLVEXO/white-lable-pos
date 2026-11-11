// Screenshot pass for the G4.9 screens on the iOS simulator — mocked repositories, real rendering, light AND dark (phone): the tax invoice before its
// first print ("Print original") and after it ("Reprint"), a credit note before its first print, and the receipt designer preview with the points balance.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/tax_invoice_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/g25_returns_documents_test.dart' show invoiceSale, note;

class _Repo extends Mock implements PosRepository {}

class _Printer extends Mock implements ThermalPrinterService {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 40; i++) { // the simulator capture is slower than the test: hold the frame
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;

    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(const SizedBox()); // a second GetMaterialApp in one test needs an empty frame first
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('G4.9 phone ($tn)', (t) async {
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'PKR', exponent: 2);
      final sale = invoiceSale();
      final cn = note();
      final repo = _Repo();
      final printer = _Printer();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getSaleById(any())).thenAnswer((_) async => sale);
      when(() => repo.getSaleDocuments(any())).thenAnswer(
        (_) async => PosSaleDocuments(
          saleNumber: sale.saleNumber,
          status: 'completed',
          invoiceJson: {'number': sale.invoice?.number, 'printed': false},
          creditNotes: [PosCreditNote.fromJson({'_id': cn.id, 'number': cn.number, 'printed': false, 'currency': cn.currency, 'currencyExponent': cn.exponent, 'totalMinor': cn.totalMinor, 'netMinor': cn.netMinor, 'taxMinor': cn.taxMinor, 'kind': cn.kind, 'scope': cn.scope, 'invoiceNumber': sale.invoice?.number})],
        ),
      );
      var n = -1;
      when(
        () => repo.recordReprint(any(), documentType: any(named: 'documentType'), documentId: any(named: 'documentId'), approverToken: any(named: 'approverToken'), kind: any(named: 'kind')),
      ).thenAnswer((_) async {
        n++;
        return (success: true, code: null, message: null, reprintNumber: n, kind: n == 0 ? 'original' : 'reprint');
      });
      when(() => printer.hasSavedPrinter).thenReturn(true);
      when(() => printer.printDocument(any())).thenAnswer((_) async => null);

      final c = Get.put(PosDocumentsController(repository: repo, saleId: sale.id, printer: printer, requirePinCached: (_) async => false), tag: 'docs_$tn');
      await c.load();
      await show(t, TaxInvoiceView(controller: c));
      await t.dragUntilVisible(find.byKey(const Key('invoicePrint')), find.byType(Scrollable).first, const Offset(0, -300));
      await shot(t, 'g49_01_invoice_print_original', tn);
      await c.printInvoice(); // recorded as the original → the button now reads Reprint
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'g49_02_invoice_after_original_reprint', tn);

      c.printNotice.value = null; // the invoice's "Printed." belongs to that screen
      await show(t, CreditNoteView(controller: c, number: cn.number));
      await t.dragUntilVisible(find.byKey(const Key('notePrint')), find.byType(Scrollable).first, const Offset(0, -300));
      await shot(t, 'g49_03_credit_note_print_original', tn);

      // receipt designer: the preview shows the points balance line
      final st = Get.put(StoreSettingsController(repository: repo, storeId: 'st1', applyLock: (_, __) async {}), tag: 'st_$tn');
      when(() => repo.getStoreSettings('st1')).thenAnswer(
        (_) async => StoreSettings.fromJson({
          'receipt': {'showQr': true, 'showBarcode': true, 'showLoyaltyBalance': true, 'defaultPaperWidth': 80, 'footer': 'Exchange within 7 days with receipt'},
          'security': {},
          'profile': {'businessName': 'Karachi Mart', 'businessAddress': 'Shop 12, Tariq Road, Karachi'},
          'timeZone': 'Asia/Karachi',
          'canEdit': true,
        }),
      );
      await st.load();
      await show(t, ReceiptDesignerView(controller: st));
      await t.dragUntilVisible(find.text('Points balance'), find.byType(Scrollable).first, const Offset(0, -300));
      await shot(t, 'g49_04_receipt_designer_points_balance', tn);
    });
  }
}
