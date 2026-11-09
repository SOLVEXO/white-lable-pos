// Screenshot pass for G2.7 on the iOS simulator (real rendering): permissions in every state, the document screens with the print outcome,
// and a "print preview" of what the thermal printer prints (58 and 80 mm) — the simulator has no Bluetooth printer.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/tax_invoice_view.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/controllers/pos_permissions_controller.dart';
import 'package:solvexo_pos/app/modules/pos_permissions/views/pos_permissions_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import '../test/g25_returns_documents_test.dart' show invoiceSale, note;
import '../test/g27_permissions_test.dart' show FakeGateway;
import '../test/support/sale_harness.dart';

class _Preview extends StatelessWidget {
  const _Preview(this.title, this.mm, this.lines);
  final String title;
  final int mm;
  final List<DocLine> Function(int cols) lines;

  @override
  Widget build(BuildContext context) {
    final cols = mm == 58 ? 32 : 48;
    final text = TaxDocumentEscPos.render(lines(cols), cols);
    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$title · $mm mm ($cols columns)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                color: Colors.white,
                child: Text(text, style: TextStyle(fontFamily: 'Courier', fontSize: mm == 58 ? 13 : 9.6, height: 1.25, color: Colors.black, fontFeatures: const [])),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;
    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('permissions + documents + thermal preview ($tn)', (t) async {
      Get.reset();
      final g = FakeGateway({AppPermission.camera: PermState.granted, AppPermission.bluetooth: PermState.permanentlyDenied, AppPermission.localNetwork: PermState.unknown, AppPermission.notifications: PermState.notRequired});
      final pc = PosPermissionsController(gateway: g, ios: true, afterSetup: true);
      Get.put(pc);
      await show(t, PosPermissionsView(controller: pc));
      await shot(t, 'g27_01_permissions_after_setup', tn);
      g.state[AppPermission.camera] = PermState.denied;
      g.state[AppPermission.bluetooth] = PermState.denied;
      await pc.refreshAll();
      await shot(t, 'g27_02_permissions_denied', tn);

      final sale = invoiceSale(extraLine: true);
      final repo = MockPosRepository();
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale);
      when(() => repo.getSaleDocuments('sale-1')).thenAnswer((_) async => PosSaleDocuments(saleNumber: 'POS-00007', status: 'partially_refunded', creditNotes: [note()]));
      final d = PosDocumentsController(repository: repo, saleId: 'sale-1');
      Get.put(d, tag: 'doc');
      await d.load();
      await show(t, TaxInvoiceView(controller: d));
      await d.printInvoice(); // no printer paired on the simulator → the plain explanation + the PDF route
      await shot(t, 'g27_03_invoice_print_no_printer', tn);
      await show(t, CreditNoteView(controller: d, number: 'CN-000001'));
      await shot(t, 'g27_04_credit_note_buttons', tn);

      final cn = note();
      for (final mm in [58, 80]) {
        await show(t, _Preview('Tax invoice', mm, (c) => TaxDocumentEscPos.invoice(sale, cols: c)));
        await shot(t, 'g27_05_preview_invoice_$mm', tn);
        await show(t, _Preview('Credit note', mm, (c) => TaxDocumentEscPos.creditNote(cn, cols: c)));
        await shot(t, 'g27_06_preview_credit_note_$mm', tn);
      }
      await show(t, _Preview('Return receipt', 58, (c) => TaxDocumentEscPos.returnReceipt(cn, cols: c, saleNumber: 'POS-00007')));
      await shot(t, 'g27_07_preview_return_receipt_58', tn);
      Get.reset();
    });
  }
}
