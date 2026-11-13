// G6.1 — "older backend" mode: the closed-testing app may talk to the G5.1 production API (c889af0), which has none of release #2's routes
// (they answer 404) and sends no fiscal contract, no connectors.ui, no display lines. Everything added after G5.1 must hide or fall back: no
// crash, no error on the cashier's screens; sales, refunds, shifts and printing unchanged. (The same app was also run against a real G5.1
// backend: tool/run_older_backend_e2e.sh.)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/fiscal_status_card.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/server_capabilities.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/send_receipt_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

class _Repo extends Mock implements PosRepository {}

/// A sale exactly as the G5.1 backend returns it: the G2.6 placeholder fiscal block, seller NTN / STRN, no display lines.
PosSaleModel _g51Sale() => PosSaleModel.fromJson({
      '_id': 'sale-1', 'saleNumber': 'POS-00007', 'storeId': 'store-1', 'sessionId': 's', 'registerId': 'r', 'employeeId': 'e', 'status': 'completed',
      'currency': 'PKR', 'currencyExponent': 2, 'subtotal': 10.0, 'discount': 0, 'tax': 0, 'total': 10.0, 'paymentMethod': 'card', 'customerName': 'Walk-in',
      'createdAt': '2026-11-12T10:00:00.000Z',
      'invoice': {
        'number': 'INV-000007', 'issuedAt': '2026-11-12T10:00:00.000Z',
        'seller': {'legalName': 'Karachi Mart', 'ntn': '1234567-8', 'strn': '3277876'},
        'fiscal': {'status': 'not_enabled', 'externalInvoiceNumber': null, 'qrPayload': null, 'attempts': 0, 'lastError': null},
      },
      'items': [{'_id': 'i1', 'productId': 'p1', 'variantId': 'v1', 'name': 'Tea', 'sku': 'TEA', 'qty': 1, 'price': 10.0, 'lineTotal': 10.0, 'netMinor': 1000, 'taxMinor': 0}],
      'payments': [{'method': 'card', 'amount': 10.0, 'reference': 'AUTH1'}],
    });

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
  });
  setUp(() {
    ConnectorUiStore.current = const ConnectorUi();
    ServerCapabilities.resetForTest(); // detection itself: test/g62_capabilities_test.dart
  });

  group('sales, receipts and documents from a G5.1 server print exactly as before', () {
    test('no fiscal contract → no fiscal band, no "Fiscal pending", nothing on screen', () async {
      final s = _g51Sale();
      final r = ReceiptData.fromSale(s, null, asciiSafeMoney: true);
      expect(r.fiscalPrint.isEmpty, isTrue);
      final txt = latin1.decode(await ReceiptEscPosBuilder.build(data: r), allowInvalid: true);
      expect(txt, isNot(contains('Fiscal')));
      final inv = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice(s, cols: 48, fiscal: PosDocumentsController.slotsOf(s.invoice!.fiscal)), 48);
      expect(inv, allOf(contains('NTN 1234567-8'), contains('STRN 3277876'), isNot(contains('Fiscal'))));
      expect(s.invoice!.fiscal!.required, isFalse);
    });

    testWidgets('the fiscal card stays hidden for the G2.6 placeholder', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: FiscalStatusCard(fiscal: _g51Sale().invoice!.fiscal))));
      expect(find.byKey(const Key('fiscalStatus')), findsNothing);
    });
  });

  group('release #2 routes answer 404 → hidden or the previous behaviour, never a cashier-facing error', () {
    test('no connectors.ui → the card-terminal switch is off, its fields and wording fall back; simulate only in debug as before', () {
      expect(ConnectorUiStore.current.terminalFields.first.label, 'Approval code');
      expect(ConnectorUiStore.current.raastPollAfterMs, 2000);
      expect(PosHomeController.qrSimulateAllowed, isTrue); // tests run in debug mode; release builds never show it
    });

    test('Integrations: the fiscal issues read failing (404) leaves the section hidden; the screen still loads', () async {
      Get.reset();
      final repo = _Repo();
      when(() => repo.getConnectors('st1')).thenAnswer((_) async => null);
      when(() => repo.getApiKeys('st1')).thenAnswer((_) async => null);
      when(() => repo.getFiscalIssues('st1')).thenAnswer((_) async => null);
      final c = PosIntegrationsController(repo: repo, storeId: 'st1', share: (_) async {}, clock: () => DateTime(2026, 11, 13));
      await c.load();
      expect(c.fiscalIssues.value, isNull);
    });

    testWidgets('send receipt: no receipt-delivery route → share link and WhatsApp only (no e-mail / SMS buttons, no error)', (t) async {
      final repo = _Repo();
      when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => null);
      await t.binding.setSurfaceSize(const Size(430, 1200));
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: SendReceiptSheet(
        storeId: 'st1', saleId: 's1', link: 'l', message: 'm', repository: repo, launcher: (_) async => true, share: (_) async {}))))));
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('sendShare')), findsOneWidget);
      expect(find.byKey(const Key('sendWhatsApp')), findsOneWidget);
      expect(find.byKey(const Key('sendSms')), findsNothing);
      expect(find.byKey(const Key('sendEmailButton')), findsNothing);
      expect(find.byKey(const Key('sendError')), findsNothing);
    });

    test('an unknown fiscal status from a NEWER server is treated as not required (nothing printed)', () {
      final s = PosSaleModel.fromJson({..._g51Sale().toJsonForTest(), 'invoice': {'number': 'INV-1', 'fiscal': {'status': 'queued_v2'}}});
      expect(s.invoice!.fiscal!.required, isFalse);
    });
  });
}

extension on PosSaleModel {
  Map<String, dynamic> toJsonForTest() => {
        '_id': id, 'saleNumber': saleNumber, 'storeId': storeId, 'sessionId': sessionId, 'registerId': registerId, 'employeeId': employeeId, 'status': status,
        'currency': currency, 'currencyExponent': currencyExponent, 'subtotal': subtotal, 'discount': discount, 'tax': tax, 'total': total, 'paymentMethod': paymentMethod,
        'customerName': customerName, 'createdAt': '2026-11-12T10:00:00.000Z', 'items': const [], 'payments': const [],
      };
}
