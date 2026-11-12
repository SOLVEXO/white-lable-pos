// G5.3: send a receipt — share link, WhatsApp to the customer's number (wa.me, falling back to the share sheet), e-mail / SMS only when the store has them on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/send_receipt_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _Repo extends Mock implements PosRepository {}

void main() {
  late _Repo repo;
  final launched = <Uri>[];
  final shared = <String>[];
  setUp(() {
    Get.testMode = true;
    repo = _Repo();
    launched.clear();
    shared.clear();
  });
  Future<void> pump(WidgetTester t, {String? phone, String? email, bool launchOk = true}) async {
    await t.binding.setSurfaceSize(const Size(430, 1200));
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: SendReceiptSheet(key: UniqueKey(), 
      storeId: 'st1', saleId: 's1', link: 'https://solvexo.store/r/s/shop/pos-1-x', message: 'Karachi Mart: your receipt (PKR 1,250.00) — https://solvexo.store/r/s/shop/pos-1-x',
      customerPhone: phone, customerEmail: email, repository: repo,
      launcher: (u) async { launched.add(u); return launchOk; },
      share: (p) async => shared.add(p.text ?? ''),
    ))))));
    await t.pump(const Duration(milliseconds: 200));
  }

  test('wa.me link: digits only, the message URL-encoded', () {
    expect(whatsAppUri('+92 300 1234567', 'Hi & bye').toString(), 'https://wa.me/923001234567?text=Hi%20%26%20bye');
  });

  testWidgets('WhatsApp opens wa.me with the customer\'s number on file; no number → the share sheet; channels off → no e-mail / SMS buttons', (t) async {
    when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => (email: false, sms: false));
    await pump(t, phone: '+923001234567');
    expect(find.byKey(const Key('sendSms')), findsNothing);
    expect(find.byKey(const Key('sendEmailButton')), findsNothing);
    await t.tap(find.byKey(const Key('sendWhatsApp')));
    await t.pump();
    expect(launched.single.host, 'wa.me');
    expect(launched.single.path, '/923001234567');
    await pump(t);
    await t.tap(find.byKey(const Key('sendWhatsApp')));
    await t.pump();
    expect(shared.single, contains('/r/s/shop/'));
  });

  testWidgets('WhatsApp not installed (launch fails) → the share sheet', (t) async {
    when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => (email: false, sms: false));
    await pump(t, phone: '+923001234567', launchOk: false);
    await t.tap(find.byKey(const Key('sendWhatsApp')));
    await t.pump();
    expect([launched.length, shared.length], [1, 1]);
  });

  testWidgets('e-mail on: to the address on file without the consent tick; another address needs the tick', (t) async {
    when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => (email: true, sms: true));
    when(() => repo.sendReceipt('st1', 's1', channel: any(named: 'channel'), to: any(named: 'to'), givenForSale: any(named: 'givenForSale'))).thenAnswer((_) async => (success: true, code: null, message: null));
    await pump(t, email: 'ayesha@shop.pk');
    await t.tap(find.byKey(const Key('sendEmailButton')));
    await t.pump();
    expect(find.text('E-mail sent.'), findsOneWidget);
    verify(() => repo.sendReceipt('st1', 's1', channel: 'email', to: 'ayesha@shop.pk', givenForSale: false)).called(1);
    await t.enterText(find.byKey(const Key('sendEmail')), 'other@mail.pk');
    await t.tap(find.byKey(const Key('sendEmailButton')));
    await t.pump();
    expect(find.byKey(const Key('sendError')), findsOneWidget);
    await t.tap(find.byKey(const Key('sendGiven')));
    await t.tap(find.byKey(const Key('sendEmailButton')));
    await t.pump();
    verify(() => repo.sendReceipt('st1', 's1', channel: 'email', to: 'other@mail.pk', givenForSale: true)).called(1);
  });
}
