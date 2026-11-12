// REAL end-to-end for G5.2–G5.7 on the iOS simulator against the dev stack (real repositories, real API). Each flow switches its store setting on and
// back off, so the other flows (and the next run) see the defaults.
//   · RECEIPT_PUBLIC_URL: the receipt QR base is the customer-facing origin (dev: http://127.0.0.1:3102, different from the API URL), and it opens
//   · product edit with an image (the dev stack stubs storage: DEV_UPLOAD_STUB) — details, photo add / remove
//   · WhatsApp / share: the real receipt link → wa.me with the customer's number; WhatsApp absent → the share sheet with the link
//   · card on a bank terminal: approval code required live; sale + refund (credit note references the code) → the shift close line
//   · fiscal (mock provider): an online sale is confirmed; an OFFLINE sale prints "Fiscal pending" and is confirmed when it syncs; credit note too
//   · receipt logo: owner uploads → the till's settings carry it → the printed receipt carries the raster (bitmap made from the same image)
//   · role preset: preview diff → apply (version-guarded, audited) → back to Standard
//   · accounting export: the manager's CSV (store time zone, minor + formatted, cost columns while costs are visible)
//   · API key: create (shown once) → read sales with it → revoke → refused
// Run:  (solvexo-api) DEV_REBUILD=1 npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g52_g57_flow_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/send_receipt_sheet.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_logo.dart';
import 'package:solvexo_pos/utils/sound_util.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

import 'support/real_backend.dart';

final Dio _raw = Dio(BaseOptions(validateStatus: (_) => true, responseType: ResponseType.plain));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    SoundUtil.enabled = false;
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'g5x probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> connectors(Map<String, bool> flags) async {
    final r = await owner.patch('/api/pos/store/settings/$storeId', {'connectors': flags}, headers: {'Idempotency-Key': 'e2e-conn-${DateTime.now().microsecondsSinceEpoch}'});
    expect(r.statusCode, anyOf(200, 201), reason: 'connectors: ${r.data}');
  }

  Future<String> sell(Till t, String sessionId, {String method = 'card', List<Map<String, dynamic>>? payments}) async {
    final r = await t.repo.createSale(storeId: storeId, sessionId: sessionId, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-REFILL', 1)], paymentMethod: method, payments: payments, status: 'completed');
    expect(r.success, isTrue, reason: '${r.message}');
    return r.sale!.id;
  }

  Future<Uint8List> pngLogo() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = Colors.white);
    c.drawCircle(const Offset(100, 50), 40, Paint()..color = Colors.black);
    final img = await rec.endRecording().toImage(200, 100);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  testWidgets('G5.2.0b receipt QR comes from RECEIPT_PUBLIC_URL and opens', (tester) async {
    final t = await till(cashierEmail, cashierPin);
    final session = await t.openShift();
    try {
      final settings = (await t.repo.getPosSettings(storeId))!;
      expect(settings.receiptLinkBase, startsWith('http://127.0.0.1:3102/r/s/'), reason: 'the customer-facing origin, not the API URL (${AppEnv.apiBaseUrl})');
      final id = await sell(t, session.id);
      final sale = (await t.repo.getSaleById(id))!;
      final r = ReceiptData.fromSale(sale, settings, receiptUrl: null);
      expect(r.qrPayload, '${settings.receiptLinkBase}${sale.clientKey}');
      final res = await _raw.get('${AppEnv.apiBaseUrl}${Uri.parse(r.qrPayload!).path}');
      expect(res.statusCode, 200);
      expect('${res.data}', contains('<html'));
    } finally {
      await t.closeAnyOpenShift();
      await t.dispose();
    }
  });

  testWidgets('G5.2 product page: edit details, add and remove a photo', (tester) async {
    final t = await till(managerEmail, managerPin);
    try {
      final pid = (await t.productIdBySku())['DEV-REFILL']!;
      final page = (await t.repo.getProductPage(storeId, pid))!;
      final oldName = page.name;
      final renamed = await t.repo.updateProductDetails(storeId, pid, {'name': '$oldName (e2e)'});
      expect(renamed.success, isTrue, reason: '${renamed.message}');
      expect(renamed.data!.name, '$oldName (e2e)');
      final f = File('${Directory.systemTemp.path}/g52_photo.png')..writeAsBytesSync(await pngLogo());
      final up = await t.repo.uploadProductImage(storeId, pid, f);
      expect(up.success, isTrue, reason: '${up.message}');
      final added = up.data!.images.last.url;
      expect(added, startsWith('https://dev-upload.invalid/products/$storeId/'));
      final gone = await t.repo.removeProductImage(storeId, pid, added);
      expect(gone.data!.images.map((i) => i.url), isNot(contains(added)));
      await t.repo.updateProductDetails(storeId, pid, {'name': oldName});
    } finally {
      await t.dispose();
    }
  });

  testWidgets('G5.3 WhatsApp to the customer number with the real receipt link; without WhatsApp → the share sheet', (tester) async {
    final t = await till(cashierEmail, cashierPin);
    final session = await t.openShift();
    try {
      final id = await sell(t, session.id);
      final link = (await t.repo.getReceiptLink(id))!;
      expect(link, startsWith('http://127.0.0.1:3102/r/'));
      final launched = <Uri>[];
      final shared = <String>[];
      await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: SendReceiptSheet(storeId: storeId, saleId: id, link: link, message: 'Dev Coffee: your receipt — $link', customerPhone: '+92 300 1234567', repository: t.repo, launcher: (u) async { launched.add(u); return false; }, share: (p) async => shared.add(p.text ?? '')))))));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.byKey(const Key('sendWhatsApp')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(launched.single.host, 'wa.me');
      expect(launched.single.path, '/923001234567');
      expect(launched.single.queryParameters['text'], contains(link));
      expect(shared.single, contains(link), reason: 'WhatsApp is not on the simulator → the share sheet');
    } finally {
      await t.closeAnyOpenShift();
      await t.dispose();
    }
  });

  testWidgets('G5.4 card on a bank terminal: approval code required, sale + refund, the shift close line', (tester) async {
    await connectors({'cardExternalTerminal': true});
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift();
    try {
      final item = await t.line('DEV-REFILL', 1);
      final total = (await t.repo.quoteSale(storeId: storeId, items: [item])).quote!.total; // with tax, as the server prices it
      final refused = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [item], paymentMethod: 'card', payments: [{'method': 'card', 'amount': total}], status: 'completed');
      expect(refused.success, isFalse);
      expect(t.repo.lastErrorCode, 'CARD_APPROVAL_REQUIRED');
      final id = await sell(t, session.id, payments: [{'method': 'card', 'amount': total, 'approvalCode': 'E2E123', 'last4': '4242', 'terminalLabel': 'HBL #1'}]);
      // the shift close line (a fully refunded sale leaves the shift's sales, like the card total itself)
      final report = (await t.repo.getSessionReport(session.id))!;
      expect(report.cardTerminalCount, 1);
      expect(report.cardTerminalApprovalCodes, ['E2E123']);
      final ref = await t.repo.refundSale(id, reasonCode: 'wrong_item');
      expect(ref.success, isTrue, reason: '${ref.message}');
      final docs = (await t.repo.getSaleDocuments(id))!;
      final cn = await owner.get('/api/pos/sales/$id/documents');
      expect('${(cn.data['data']['creditNotes'] as List).first['tenders']}', contains('E2E123'));
      expect(docs.creditNotes, isNotEmpty);
    } finally {
      await t.closeAnyOpenShift();
      await connectors({'cardExternalTerminal': false});
      await t.dispose();
    }
  });

  testWidgets('G5.5 fiscal mock: online confirmed; offline prints "Fiscal pending" and is confirmed on sync; credit note confirmed', (tester) async {
    await connectors({'fiscal': true});
    final t = await till(managerEmail, managerPin); // refunds need a manager in this store
    final session = await t.openShift();
    try {
      final online = await sell(t, session.id);
      final d1 = (await t.repo.getSaleDocuments(online))!;
      expect(d1.invoiceFiscal!.confirmed, isTrue);
      expect(d1.invoiceFiscal!.number, startsWith('MOCK-FBR-I-'));
      final printed = TaxDocumentEscPos.render(TaxDocumentEscPos.invoice((await t.repo.getSaleById(online))!, cols: 48, fiscal: PosDocumentsController.slotsOf(d1.invoiceFiscal)), 48);
      expect(printed, contains(d1.invoiceFiscal!.number!));

      // offline: the API goes away, the sale is queued, the provisional receipt says "Fiscal pending"
      final item = await t.line('DEV-REFILL', 1); // read while online
      await Control.stopApi();
      final q = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [item], paymentMethod: 'cash', status: 'completed', idempotencyKey: 'pos-${DateTime.now().microsecondsSinceEpoch}-0123456789abcdef01234567');
      expect(q.queued, isTrue, reason: 'queued while the API is down');
      final offline = ReceiptData.forOfflineSale(provisionalNumber: 'OFF-1', madeAt: DateTime.now(), currency: 'PKR', exponent: 2, items: const [(name: 'Refill', qty: 1, unitPrice: 1)], subtotal: 1, discount: 0, tax: 0, total: 1, payments: const [(method: 'cash', amount: 1, reference: null)], change: 0, fiscalPending: true);
      final bytes = await ReceiptEscPosBuilder.build(data: offline);
      expect(String.fromCharCodes(bytes), contains('Fiscal pending'));
      await Control.startApi();
      await t.sync.syncNow(ignoreBackoff: true);
      await eventually(() async => t.sync.unresolvedCount.value == 0, reason: 'the offline sale synced');
      final sales = await owner.get('/api/pos/sales?storeId=$storeId&limit=5');
      final last = ((sales.data['data']['sales'] ?? sales.data['data']) as List).cast<Map>().first;
      await eventually(() async => (await t.repo.getSaleDocuments('${last['_id']}'))?.invoiceFiscal?.confirmed == true, reason: 'fiscalised when it synced');

      final ref = await t.repo.refundSale(online, reasonCode: 'wrong_item');
      expect(ref.success, isTrue);
      final d2 = (await t.repo.getSaleDocuments(online))!;
      expect(d2.creditNotes.single.fiscal!.confirmed, isTrue);
      expect(d2.creditNotes.single.fiscal!.number, startsWith('MOCK-FBR-C-'));
    } finally {
      await Control.startApi();
      await t.closeAnyOpenShift();
      await connectors({'fiscal': false});
      await t.dispose();
    }
  });

  testWidgets('G5.6 receipt logo: owner uploads, the till settings carry it, the receipt prints the raster', (tester) async {
    final png = await pngLogo();
    final up = await _raw.post('${AppEnv.apiBaseUrl}/api/pos/store/settings/$storeId/receipt-logo', data: FormData.fromMap({'file': MultipartFile.fromBytes(png, filename: 'logo.png')}), options: Options(headers: {'Authorization': 'Bearer ${owner.ownerToken}'}));
    expect(up.statusCode, anyOf(200, 201), reason: '${up.data}');
    final t = await till(cashierEmail, cashierPin);
    try {
      final settings = (await t.repo.getPosSettings(storeId))!;
      expect(settings.receiptLogoUrl, startsWith('https://dev-upload.invalid/receipt-logos/$storeId/'));
      final bmp = (await ReceiptLogo.fromImageBytes(png, paperMm: 80))!; // the dev stub serves no file: make the bitmap from the same image
      expect(bmp.width, 384);
      ReceiptLogoStore.put(settings.receiptLogoUrlToPrint!, 80, bmp);
      final r = ReceiptData.forOfflineSale(provisionalNumber: 'OFF-2', madeAt: DateTime.now(), settings: settings, currency: 'PKR', exponent: 2, items: const [(name: 'Refill', qty: 1, unitPrice: 1)], subtotal: 1, discount: 0, tax: 0, total: 1, payments: const [(method: 'cash', amount: 1, reference: null)], change: 0);
      final bytes = await ReceiptEscPosBuilder.build(data: r);
      final head = bmp.escPos().sublist(3, 11);
      var found = false;
      for (var i = 0; i + head.length <= bytes.length && !found; i++) {
        found = List.generate(head.length, (j) => bytes[i + j] == head[j]).every((x) => x);
      }
      expect(found, isTrue, reason: 'the GS v 0 raster of the logo is in the receipt');
    } finally {
      await owner.post('/api/pos/store/settings/$storeId/receipt-logo/remove');
      await t.dispose();
    }
  });

  testWidgets('G5.6 role preset: preview → apply → back to Standard (audited)', (tester) async {
    final before = await owner.get('/api/pos/permissions/$storeId');
    final v = before.data['data']['version'] as int;
    final prev = await owner.post('/api/pos/permissions/$storeId/preset', {'preset': 'strict', 'preview': true});
    expect((prev.data['data']['diff'] as List), isNotEmpty);
    final applied = await owner.post('/api/pos/permissions/$storeId/preset', {'preset': 'strict', 'expectedVersion': v});
    expect(applied.statusCode, anyOf(200, 201), reason: '${applied.data}');
    final adjust = (applied.data['data']['actions'] as List).cast<Map>().firstWhere((a) => a['action'] == 'inventory.adjust');
    expect(adjust['roles'], ['manager', 'owner']);
    final back = await owner.post('/api/pos/permissions/$storeId/preset', {'preset': 'standard'});
    expect(((back.data['data']['actions'] as List).cast<Map>()).every((a) => a['changed'] != true), isTrue);
    final logs = await owner.get('/api/pos/audit-logs/$storeId?action=permissions_preset_applied&limit=5');
    expect('${logs.data}', contains('permissions_preset_applied'));
  });

  testWidgets('G5.7 accounting export (manager) and an API key: create → read → revoke', (tester) async {
    final t = await till(managerEmail, managerPin);
    try {
      final now = DateTime.now();
      final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final csv = await t.repo.accountingExport(storeId, from: day, to: day);
      expect(csv.bytes, isNotNull, reason: '${csv.code} ${csv.message}');
      final text = String.fromCharCodes(csv.bytes!);
      expect(text.split('\n').first, startsWith('date_local,time_zone,type,number'));
      expect(text, contains(',invoice,'));

      final made = await owner.post('/api/pos/api-keys/$storeId', {'name': 'e2e books', 'scopes': ['sales:read'], 'expiresInDays': 1});
      expect(made.statusCode, anyOf(200, 201), reason: '${made.data}');
      final key = made.data['data']['key'] as String;
      final id = made.data['data']['apiKey']['id'] as String;
      final read = await Dio(BaseOptions(validateStatus: (_) => true)).get('${AppEnv.apiBaseUrl}/api/pos/ext/v1/sales', options: Options(headers: {'X-Api-Key': key}));
      expect(read.statusCode, 200, reason: '${read.data}');
      expect(read.data['data']['currency'], isNotNull);
      final listed = await owner.get('/api/pos/api-keys/$storeId');
      expect('${listed.data}', isNot(contains(key.split('_').last)));
      await owner.post('/api/pos/api-keys/$storeId/$id/revoke');
      final after = await Dio(BaseOptions(validateStatus: (_) => true)).get('${AppEnv.apiBaseUrl}/api/pos/ext/v1/sales', options: Options(headers: {'X-Api-Key': key}));
      expect(after.statusCode, 401);
      expect(after.data['code'], 'API_KEY_REVOKED');
    } finally {
      await t.dispose();
    }
  });
}
