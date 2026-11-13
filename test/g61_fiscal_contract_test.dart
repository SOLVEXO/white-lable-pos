// G6.1: the app renders and prints exactly what the server's fiscal contract sends (every status, mock-provider shapes), shows failed / refused
// to the cashier and owner without blocking, and takes provider-dependent wording / fields / rules from `connectors.ui` (with fallbacks).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/components/fiscal_status_card.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/views/pos_integrations_view.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/send_receipt_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/fiscal_print.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';

import 'g25_returns_documents_test.dart' show invoiceSale, note;

class _Repo extends Mock implements PosRepository {}

PosSaleModel _sale(Map<String, dynamic>? fiscal, {Map<String, dynamic>? seller}) => PosSaleModel.fromJson({
      '_id': 'sale-1', 'saleNumber': 'POS-00007', 'storeId': 'store-1', 'sessionId': 's', 'registerId': 'r', 'employeeId': 'e', 'status': 'completed',
      'currency': 'PKR', 'currencyExponent': 2, 'subtotal': 10.0, 'discount': 0, 'tax': 0, 'total': 10.0, 'paymentMethod': 'cash', 'customerName': 'Walk-in',
      'createdAt': '2026-11-12T10:00:00.000Z',
      'invoice': {'number': 'INV-000007', 'issuedAt': '2026-11-12T10:00:00.000Z', 'seller': ?seller, 'fiscal': ?fiscal},
      'items': [{'_id': 'i1', 'productId': 'p1', 'variantId': 'v1', 'name': 'Tea', 'sku': 'TEA', 'qty': 1, 'price': 10.0, 'lineTotal': 10.0, 'netMinor': 1000, 'taxMinor': 0}],
      'payments': [{'method': 'cash', 'amount': 10.0}],
    });

// What the server's mock provider sends for each status (backend pos.g61 spec)
const _confirmed = {
  'status': 'confirmed', 'externalInvoiceNumber': 'MOCK-FBR-I-INV-000007', 'qrPayload': 'mock-fiscal:MOCK-FBR-I-INV-000007:1000',
  'displayLines': [{'label': 'Authority invoice', 'value': 'MOCK-FBR-I-INV-000007'}, {'label': 'Mode', 'value': 'TEST'}],
  'message': null, 'willRetry': false, 'logoUrl': null, 'testMode': true, 'contractVersion': 1, 'attempts': 1, 'lastError': null,
};
const _pending = {'status': 'pending', 'externalInvoiceNumber': null, 'qrPayload': null, 'displayLines': [], 'message': null, 'willRetry': true, 'contractVersion': 1};
const _failed = {'status': 'failed', 'displayLines': [], 'message': 'Outcome unknown, not sent again. Check it, then retry.', 'willRetry': false, 'contractVersion': 1};
const _rejected = {'status': 'rejected', 'displayLines': [], 'message': 'The tax authority refused this document (invalid item code).', 'willRetry': false, 'contractVersion': 1};

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });
  setUp(() => ConnectorUiStore.current = const ConnectorUi());

  group('fiscal contract → what is printed', () {
    test('confirmed: the server\'s lines as given + QR; no app-chosen authority label anywhere', () {
      final f = PosFiscalInfo.fromJson(_confirmed)!;
      final p = FiscalPrint.of(f);
      expect(p.textLines, ['Authority invoice MOCK-FBR-I-INV-000007', 'Mode TEST']);
      expect(p.qr, 'mock-fiscal:MOCK-FBR-I-INV-000007:1000');
      final inv = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(_sale(_confirmed), cols: 48, fiscal: PosDocumentsController.slotsOf(f)), 48);
      expect(inv, contains('Authority invoice'));
      expect(inv, contains('MOCK-FBR-I-INV-000007'));
      expect(inv, contains('[QR mock-fiscal:'));
      expect(inv, isNot(contains('FBR Invoice No')));
    });

    test('confirmed by an older (G5.5) server without lines: the number alone', () {
      final p = FiscalPrint.of(PosFiscalInfo.fromJson({'status': 'confirmed', 'externalInvoiceNumber': 'N-1', 'qrPayload': 'q'}));
      expect([p.textLines, p.qr], [['N-1'], 'q']);
    });

    test('pending and failed print "Fiscal pending" (unless the server sends lines); rejected / not required / unknown print nothing', () {
      expect(FiscalPrint.of(PosFiscalInfo.fromJson(_pending)).textLines, ['Fiscal pending']);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson(_failed)).textLines, ['Fiscal pending']);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson(_rejected)).isEmpty, isTrue);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson({..._rejected, 'displayLines': [{'label': '', 'value': 'NOT FISCALISED'}]})).textLines, ['NOT FISCALISED']);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson({'status': 'not_enabled'})).isEmpty, isTrue);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson({'status': 'not_required'})).isEmpty, isTrue);
      expect(FiscalPrint.of(PosFiscalInfo.fromJson({'status': 'something_new'})).isEmpty, isTrue);
      expect(FiscalPrint.of(null).isEmpty, isTrue);
    });

    test('offline: "Fiscal pending" when the store fiscalises; after sync the reprint shows the confirmed block', () {
      expect(FiscalPrint.of(null, offlinePending: true).textLines, ['Fiscal pending']);
      final off = ReceiptData.forOfflineSale(provisionalNumber: 'OFF-1', madeAt: DateTime(2026, 11, 12), currency: 'PKR', exponent: 2, items: const [(name: 'Tea', qty: 1, unitPrice: 10)], subtotal: 10, discount: 0, tax: 0, total: 10, payments: const [(method: 'cash', amount: 10, reference: null)], change: 0, fiscalPending: true);
      expect(off.fiscalPrint.textLines, ['Fiscal pending']);
      final synced = ReceiptData.fromSale(_sale(_confirmed), null, asciiSafeMoney: true);
      expect(synced.fiscalPrint.textLines.first, 'Authority invoice MOCK-FBR-I-INV-000007');
      expect(ReceiptData.fromJson(synced.toJson()).fiscalPrint.textLines, synced.fiscalPrint.textLines); // saved receipts keep the lines
    });

    test('thermal receipt bytes carry the server\'s label and value; the PDFs build with the block', () async {
      final bytes = await ReceiptEscPosBuilder.build(data: ReceiptData.fromSale(_sale(_confirmed), null, asciiSafeMoney: true));
      final txt = latin1.decode(bytes, allowInvalid: true);
      expect(txt, contains('Authority invoice'));
      expect(txt, contains('MOCK-FBR-I-INV-000007'));
      expect((await TaxDocumentPdf.invoice(sale: invoiceSale(), fiscal: FiscalPrint.of(PosFiscalInfo.fromJson(_confirmed)))).length, greaterThan(500));
      expect((await TaxDocumentPdf.creditNote(note: note(), fiscal: FiscalPrint.of(PosFiscalInfo.fromJson(_pending)))).length, greaterThan(500));
    });

    test('seller tax ids: the server\'s labels when sent; NTN / STRN only as the fallback of an older server', () {
      final labelled = _sale(null, seller: {'legalName': 'Shop', 'taxIds': [{'label': 'Tax no.', 'value': '42'}], 'ntn': '1'});
      expect(TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(labelled, cols: 48), 48), allOf(contains('Tax no. 42'), isNot(contains('NTN'))));
      final legacy = _sale(null, seller: {'legalName': 'Shop', 'ntn': '1234567-8', 'strn': '99'});
      expect(legacy.invoice!.sellerTaxLines.map((l) => '${l.label} ${l.value}'), ['NTN 1234567-8', 'STRN 99']);
    });
  });

  group('fiscal state on screen (cashier and owner), never blocking', () {
    Future<void> pump(WidgetTester t, Map<String, dynamic>? f) async {
      await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: FiscalStatusCard(fiscal: PosFiscalInfo.fromJson(f)))));
    }

    testWidgets('confirmed / pending / failed / rejected / not enabled', (t) async {
      await pump(t, _confirmed);
      expect(find.text('Fiscal: confirmed'), findsOneWidget);
      expect(find.textContaining('MOCK-FBR-I-INV-000007'), findsOneWidget);
      expect(find.text('Test mode'), findsOneWidget);
      await pump(t, _pending);
      expect(find.text('Fiscal: pending'), findsOneWidget);
      expect(find.textContaining('automatically'), findsOneWidget);
      await pump(t, _failed);
      expect(find.text('Fiscal: not sent'), findsOneWidget);
      expect(find.text(_failed['message'] as String), findsOneWidget);
      expect(find.text(FiscalStatusCard.ownerHint), findsOneWidget);
      await pump(t, _rejected);
      expect(find.text('Fiscal: refused'), findsOneWidget);
      expect(find.text(_rejected['message'] as String), findsOneWidget);
      await pump(t, {'status': 'not_enabled'});
      expect(find.byKey(const Key('fiscalStatus')), findsNothing);
      await pump(t, null);
      expect(find.byKey(const Key('fiscalStatus')), findsNothing);
    });

    testWidgets('owner: Integrations lists failed / refused documents; "Send again" retries a failed one; hidden when the server has no route', (t) async {
      Get.reset();
      final repo = _Repo();
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => ConnectorsStatus.fromJson({'flags': {'fiscal': true}, 'cardGateway': {}, 'fiscal': {'provider': 'mock', 'testMode': true, 'configured': true}}));
      when(() => repo.getApiKeys('st1')).thenAnswer((_) async => null);
      final issues = [
        FiscalIssue.fromJson({'documentType': 'invoice', 'documentId': 'd1', 'documentNumber': 'INV-000001', 'status': 'failed', 'message': 'Outcome unknown', 'retryable': true}),
        FiscalIssue.fromJson({'documentType': 'credit_note', 'documentId': 'd2', 'documentNumber': 'CN-000001', 'status': 'rejected', 'message': 'Refused', 'retryable': false}),
      ];
      var calls = 0;
      when(() => repo.getFiscalIssues('st1')).thenAnswer((_) async => calls++ == 0 ? issues : [issues[1]]);
      when(() => repo.retryFiscal('st1', documentType: 'invoice', documentId: 'd1')).thenAnswer((_) async => (success: true, code: null, message: null, fiscal: PosFiscalInfo.fromJson(_confirmed)));
      final c = PosIntegrationsController(repo: repo, storeId: 'st1', share: (ShareParams p) async {}, clock: () => DateTime(2026, 11, 12));
      final loaded = c.load();
      t.view.physicalSize = const Size(430, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: PosIntegrationsView(key: UniqueKey(), controller: c))));
      await t.runAsync(() => loaded);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('fiscalIssues')), findsOneWidget);
      expect(find.text('Refused'), findsWidgets);
      expect(find.byKey(const Key('fiscalRetry-d2')), findsNothing); // refused: no retry
      await t.runAsync(() => c.retryFiscal(issues[0]));
      await t.pump(const Duration(milliseconds: 200));
      verify(() => repo.retryFiscal('st1', documentType: 'invoice', documentId: 'd1')).called(1);
      expect(c.notice.value, contains('fiscal confirmed'));
      expect(c.fiscalIssues.value!.single.documentId, 'd2');
      // an older server: the read fails → the section is hidden, the screen still works
      when(() => repo.getFiscalIssues('st1')).thenThrow(Exception('404'));
      await t.runAsync(() => c.load());
      await t.pump(const Duration(milliseconds: 200));
      expect(c.fiscalIssues.value, isNull);
      expect(find.byKey(const Key('fiscalIssues')), findsNothing);
    });
  });

  group('provider-dependent wording, fields and rules come from the server (connectors.ui)', () {
    test('an older server (no ui): the app keeps what it showed before', () {
      final s = ConnectorsStatus.fromJson({'flags': {}, 'cardGateway': {}, 'fiscal': {}});
      expect(s.ui.terminalFields.map((f) => [f.key, f.required]), [['approvalCode', true], ['last4', false], ['terminalLabel', false]]);
      expect(s.ui.raastPollAfterMs, 2000);
      expect(s.ui.raastSimulateAvailable, isNull);
      expect(s.ui.whatsappMode, 'link');
      expect(s.ui.fiscalTitle, 'Fiscal invoices');
      expect(ConnectorUiStore.current.raastCustomerInstructions, contains('scan'));
    });

    test('a server with ui: fields, rules, wording, poll interval and simulate are its own; the store is updated', () {
      final s = ConnectorsStatus.fromJson({'flags': {}, 'cardGateway': {}, 'fiscal': {}, 'ui': {
        'raast': {'customerInstructions': 'Scan with any banking app.', 'pollAfterMs': 5000, 'simulateAvailable': false, 'reasonText': 'Provider is onboarding you.'},
        'cardExternalTerminal': {'fields': [{'key': 'approvalCode', 'label': 'Auth code', 'required': false, 'pattern': r'^[A-Z0-9]{6}$', 'maxLength': 6}]},
        'cardGateway': {'statusText': 'Coming soon'},
        'fiscal': {'title': 'Fiscal invoices (X)'},
        'receipts': {'whatsapp': {'mode': 'off'}, 'minPhoneDigits': 11, 'consentText': 'Customer agreed', 'privacyNote': 'Only the link is sent.'},
      }});
      final ui = ConnectorUiStore.current;
      expect(identical(ui, s.ui), isTrue);
      expect([ui.raastCustomerInstructions, ui.raastPollAfterMs, ui.raastSimulateAvailable, ui.raastReasonText], ['Scan with any banking app.', 5000, false, 'Provider is onboarding you.']);
      expect(ui.terminalFields.single.label, 'Auth code');
      expect(ui.field('last4'), isNull); // not listed → not shown, not sent
      expect(ui.field('approvalCode')!.validate('ab'), 'Check the Auth code.');
      expect(ui.field('approvalCode')!.validate('AB12CD'), isNull);
      expect(ui.field('approvalCode')!.validate(''), isNull); // not required by this server
      expect([ui.cardGatewayStatusText, ui.fiscalTitle, ui.whatsappMode, ui.minPhoneDigits, ui.consentText], ['Coming soon', 'Fiscal invoices (X)', 'off', 11, 'Customer agreed']);
      expect(PosHomeController.qrSimulateAllowed, isFalse); // the server says its provider is not the mock
      ConnectorUiStore.current = const ConnectorUi();
      expect(PosHomeController.qrSimulateAllowed, isTrue); // an older server in a debug build (tests): as before
    });

    testWidgets('send receipt: WhatsApp hidden when the server turns it off; its consent / privacy words; its error message first', (t) async {
      final repo = _Repo();
      when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => (email: false, sms: true));
      when(() => repo.sendReceipt('st1', 's1', channel: 'sms', to: '+923001234567', givenForSale: false)).thenAnswer((_) async => (success: false, code: 'RATE_LIMITED', message: 'Try again in 20 minutes.'));
      ConnectorUiStore.current = ConnectorUi.fromJson({'receipts': {'whatsapp': {'mode': 'off'}, 'consentText': 'Customer agreed', 'privacyNote': 'Only the link is sent.'}});
      await t.binding.setSurfaceSize(const Size(430, 1200));
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: SendReceiptSheet(
        storeId: 'st1', saleId: 's1', link: 'l', message: 'm', customerPhone: '+923001234567', repository: repo, launcher: (_) async => true, share: (_) async {}))))));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('sendWhatsApp')), findsNothing);
      expect(find.text('Only the link is sent.'), findsOneWidget);
      expect(find.text('Customer agreed'), findsOneWidget);
      await t.tap(find.byKey(const Key('sendSms')));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Try again in 20 minutes.'), findsOneWidget);
    });
  });
}
