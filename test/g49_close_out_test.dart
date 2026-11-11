// G4.9: the receipt QR from the offline-built link (store link base + the sale's client key), online or offline, at checkout and on reprint; the
// points balance after the sale when the server returns it; the documents screen's first print is the ORIGINAL, later prints REPRINT #n, offline COPY.
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/reprint_gate.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'g25_returns_documents_test.dart' show invoiceSale, note;

class _Repo extends Mock implements PosRepository {}

class _Printer extends Mock implements ThermalPrinterService {}

const _key = 'pos-1762851600000000-0123456789abcdef01234567';
const _base = 'https://api.solvexo.app/r/s/karachi-mart/';

PosSettingsModel _settings({Map<String, dynamic> receipt = const {}, bool pin = false, String? base = _base}) => PosSettingsModel.fromJson({
  'storeId': 'st1',
  'taxRate': 0,
  'receiptOptions': receipt,
  'securityPrefs': {'requirePinForReprint': pin},
  'storePublicId': 'karachi-mart',
  'receiptLinkBase': ?base,
});

PosSaleModel _sale({String? key = _key, int? balance, int earned = 12, int redeemed = 0}) => PosSaleModel.fromJson({
  '_id': 's1',
  'saleNumber': 'S-1042',
  'storeId': 'st1',
  'sessionId': 'x',
  'registerId': 'r',
  'employeeId': 'e',
  'items': [],
  'discount': 0,
  'tax': 0,
  'subtotal': 10.0,
  'total': 10.0,
  'paymentMethod': 'cash',
  'customerName': 'Ayesha',
  'notes': '',
  'status': 'completed',
  'createdAt': '2026-11-10T10:00:00.000Z',
  'currency': 'PKR',
  'currencyExponent': 2,
  'idempotencyKey': ?key,
  'loyaltyBalanceAfterPoints': ?balance,
  'loyalty': {'ledgerId': 'c1', 'earnedPoints': earned, 'redeemedPoints': redeemed},
});

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  group('the offline-built receipt link', () {
    test('base + client key; nothing without a base or with a key that is not a till key; cached with the settings', () {
      expect(offlineReceiptLink(_settings(), _key), '$_base$_key');
      expect(offlineReceiptLink(_settings(base: 'https://x/r/s/a'), _key), 'https://x/r/s/a/$_key');
      expect(offlineReceiptLink(_settings(base: null), _key), isNull);
      expect(offlineReceiptLink(_settings(), 'checkout-1'), isNull);
      expect(offlineReceiptLink(_settings(), null), isNull);
      final cached = PosSettingsModel.fromJson(_settings().toCacheJson());
      expect([cached.receiptLinkBase, cached.storePublicId], [_base, 'karachi-mart']);
      expect(cached.withPricing(taxRate: 0.1, settingsVersion: 2).receiptLinkBase, _base);
    });

    test('a sale prints the offline-built QR — even when the token link is known; G5.1: never any other link (no client key or no base → no QR)', () {
      final s = _settings(receipt: {'showQr': true});
      expect(ReceiptData.fromSale(_sale(), s, receiptUrl: 'https://api.solvexo.app/r/tok').qrPayload, '$_base$_key');
      expect(ReceiptData.fromSale(_sale(), s).qrPayload, '$_base$_key', reason: 'reprint offline: no token link, still a QR');
      expect(ReceiptData.fromSale(_sale(key: null), s, receiptUrl: 'https://api.solvexo.app/r/tok').qrPayload, isNull);
      expect(ReceiptData.fromSale(_sale(), _settings(receipt: {'showQr': true}, base: null), receiptUrl: 'https://api.solvexo.app/r/tok').qrPayload, isNull, reason: 'no cached base: no QR, never a guessed URL');
      expect(ReceiptData.fromSale(_sale(), _settings(receipt: {'showQr': false})).qrPayload, isNull);
      expect(_sale().clientKey, _key);
    });

    test('an offline (queued) sale prints the QR from its client key under the provisional number; it survives the stored copy', () {
      final r = ReceiptData.forOfflineSale(
        provisionalNumber: 'OFF-AB12-0007',
        madeAt: DateTime.utc(2026, 11, 11, 9),
        settings: _settings(receipt: {'showQr': true}),
        currency: 'PKR',
        exponent: 2,
        items: [(name: 'Rice', qty: 1, unitPrice: 10.0)],
        subtotal: 10,
        discount: 0,
        tax: 0,
        total: 10,
        payments: [(method: 'cash', amount: 10.0, reference: null)],
        change: 0,
        clientKey: _key,
      );
      expect([r.qrPayload, r.offlineNote], ['$_base$_key', ReceiptData.offlinePendingNote]);
      expect(ReceiptData.fromJson(r.toJson()).qrPayload, '$_base$_key');
    });
  });

  group('points on the receipt', () {
    test('the balance after the sale when the server returned it (instead of earned / redeemed); otherwise earned / redeemed as before', () {
      final s = _settings(receipt: {'showLoyaltyBalance': true});
      final withBal = ReceiptData.fromSale(_sale(balance: 140, redeemed: 5), s);
      expect([withBal.pointsBalance, withBal.pointsEarned, withBal.pointsRedeemed], [140, null, null]);
      final old = ReceiptData.fromSale(_sale(redeemed: 5), s);
      expect([old.pointsBalance, old.pointsEarned, old.pointsRedeemed], [null, 12, 5]);
      expect(ReceiptData.fromSale(_sale(balance: 140), _settings(receipt: {'showLoyaltyBalance': false})).pointsBalance, isNull);
      expect(ReceiptData.fromJson(withBal.toJson()).pointsBalance, 140);
    });

    test('thermal and PDF print "Points balance"', () async {
      final d = ReceiptData.fromSale(_sale(balance: 140), _settings(receipt: {'showLoyaltyBalance': true}), asciiSafeMoney: true);
      final text = String.fromCharCodes(await ReceiptEscPosBuilder.build(data: d, paperSize: PaperSize.mm80));
      expect(text, contains('Points balance'));
      expect(text, contains('140'));
      expect(text, isNot(contains('Points earned')));
      expect((await ReceiptPdfBuilder.build(data: d)).isNotEmpty, isTrue);
    });
  });

  group('documents: original vs reprint', () {
    late _Repo repo;
    late _Printer printer;
    late List<DocLine> Function(int) built;
    final sale = invoiceSale();
    final cn = note();
    String? lastKind;

    setUp(() {
      Get.testMode = true;
      Get.reset();
      repo = _Repo();
      printer = _Printer();
      lastKind = null;
      when(() => printer.hasSavedPrinter).thenReturn(true);
      when(() => printer.printDocument(any())).thenAnswer((i) async {
        built = i.positionalArguments.first as List<DocLine> Function(int);
        return null;
      });
      when(() => repo.getSaleById(any())).thenAnswer((_) async => sale);
    });

    void docs({bool invoicePrinted = false, bool notePrinted = false}) => when(() => repo.getSaleDocuments(any())).thenAnswer(
      (_) async => PosSaleDocuments(
        saleNumber: sale.saleNumber,
        status: 'completed',
        invoiceJson: {'number': 'INV-000001', 'printed': invoicePrinted},
        creditNotes: [PosCreditNote.fromJson({'_id': cn.id, 'number': cn.number, 'printed': notePrinted, 'currency': 'PKR', 'currencyExponent': 2})],
      ),
    );
    // the server: the first print of a document is the original (0), every later one a reprint — whatever the till asked for
    void server({bool offline = false}) {
      final count = <String, int>{};
      when(
        () => repo.recordReprint(any(), documentType: any(named: 'documentType'), documentId: any(named: 'documentId'), approverToken: any(named: 'approverToken'), kind: any(named: 'kind')),
      ).thenAnswer((i) async {
        lastKind = i.namedArguments[#kind] as String?;
        if (offline) return (success: false, code: null, message: null, reprintNumber: null, kind: null);
        final id = '${i.namedArguments[#documentType]}:${i.namedArguments[#documentId]}';
        final n = count[id] = (count[id] ?? -1) + 1;
        return (success: true, code: null, message: null, reprintNumber: n, kind: n == 0 ? 'original' : 'reprint');
      });
    }

    Future<PosDocumentsController> make({bool pin = false}) async {
      final c = PosDocumentsController(repository: repo, saleId: sale.id, printer: printer, requirePinCached: (_) async => pin);
      Get.put(c);
      await c.load();
      return c;
    }

    String printed() => TaxDocumentEscPos.render(built(48), 48);

    test('first print asks for and prints ORIGINAL; the next is REPRINT #1, then #2 — for the invoice and for a credit note', () async {
      docs();
      server();
      final c = await make();
      expect(c.isPrinted('invoice', sale.id), isFalse);
      await c.printInvoice();
      expect([lastKind, printed().contains('ORIGINAL'), printed().contains('REPRINT')], ['original', true, false]);
      expect(c.isPrinted('invoice', sale.id), isTrue);
      await c.printInvoice();
      expect([lastKind, printed().contains('REPRINT #1'), printed().contains('ORIGINAL')], ['reprint', true, false]);
      await c.printInvoice();
      expect(printed(), contains('REPRINT #2'));
      final n = c.creditNotes.first;
      await c.printCreditNote(n);
      expect([lastKind, printed().contains('ORIGINAL')], ['original', true]);
      await c.printCreditNote(n);
      expect(printed(), contains('REPRINT #1'));
    });

    test('a document the server says was printed before (from any screen) asks for a reprint', () async {
      docs(invoicePrinted: true, notePrinted: true);
      server();
      final c = await make();
      expect([c.isPrinted('invoice', sale.id), c.isPrinted('credit_note', cn.id)], [true, true]);
      await c.printInvoice();
      expect(lastKind, 'reprint');
    });

    test('offline follows the G4.8 PIN rule: a store that requires a PIN refuses; otherwise COPY (never ORIGINAL — nothing was recorded)', () async {
      docs();
      server(offline: true);
      final strict = await make(pin: true);
      await strict.printInvoice();
      expect([strict.printOk.value, strict.printNotice.value], [false, contains('internet')]);
      Get.reset();
      final open = await make();
      await open.printInvoice();
      expect([printed().contains('COPY'), printed().contains('ORIGINAL')], [true, false]);
      expect(open.isPrinted('invoice', sale.id), isFalse, reason: 'the original is still to be printed once online');
    });

    test('the gate passes the kind and reports the original', () async {
      server();
      final go = await ReprintGate(repository: repo, askManager: (_) async => null).record(storeId: 'st1', documentType: 'invoice', documentId: 'x', requirePinCached: true, kind: 'original');
      expect([go.ok, go.original, go.number, lastKind], [true, true, 0, 'original']);
    });
  });
}
