// G3.4 receive screen dates, driven through the REAL showDatePicker dialog: the expiry date of a lot line and the supplier invoice date.
// A picked date is shown and sent as an ISO day; clearing it removes the key; a past expiry shows a non-blocking warning; the invoice date cannot be in the future.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/receive_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/g34_fixtures.dart';
import 'support/sale_harness.dart' show MockPosRepository;

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  late MockPosRepository repo;
  late ReceiveController c;
  Map<String, dynamic>? sent;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    Money.configure(currency: 'USD', exponent: 2);
    sent = null;
    repo = MockPosRepository();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
    when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer(
      (_) async => PoDetail(
        order: po(costs: false, items: [poLineJson(costs: false, trackLots: true)]),
        cur: usd,
      ),
    );
    when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
      sent = i.positionalArguments[1] as Map<String, dynamic>;
      return (success: true, message: null, code: null, result: receiveResult(costs: false));
    });
  });

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    c = Get.put(
      ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1'),
      tag: 'recv_po1',
    );
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          theme: AppTheme.light,
          home: ReceiveView(orderId: 'po1', controller: c),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    c.lines[0].good.value = 2;
    await t.pump();
  }

  Future<void> openPicker(WidgetTester t, String fieldKey) async {
    final f = find.byKey(Key(fieldKey));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget, reason: 'the real date picker dialog is open');
  }

  Future<void> pickDay(WidgetTester t, int day, {int monthsForward = 0, int monthsBack = 0}) async {
    for (var i = 0; i < monthsForward; i++) {
      await t.tap(find.byTooltip('Next month'));
      await t.pumpAndSettle();
    }
    for (var i = 0; i < monthsBack; i++) {
      await t.tap(find.byTooltip('Previous month'));
      await t.pumpAndSettle();
    }
    await t.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('$day')).first);
    await t.pumpAndSettle();
  }

  Future<void> ok(WidgetTester t) async {
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t) async {
    final f = find.byKey(const Key('recvConfirm'));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Map<String, dynamic> firstLine() => (sent!['lines'] as List).single as Map<String, dynamic>;

  group('expiry date of a lot line', () {
    testWidgets('picking a future day shows it in the field and sends it as an ISO date; no warning', (t) async {
      await mount(t);
      final now = DateTime.now();
      await openPicker(t, 'recvExpiry_li1');
      await pickDay(t, 15, monthsForward: 1);
      await ok(t);
      final want = DateTime(now.year, now.month + 1, 15);
      expect(c.lines[0].expiry.value, isNotNull);
      expect(_iso(c.lines[0].expiry.value!), _iso(want));
      expect(find.textContaining('Expiry date: '), findsOneWidget);
      expect(find.byKey(const Key('recvExpiryPast_li1')), findsNothing);
      await submit(t);
      expect(firstLine()['expiryDate'], _iso(want));
    });

    testWidgets('a date in the PAST is allowed but shows a visible, non-blocking warning, and is still sent', (t) async {
      await mount(t);
      final now = DateTime.now();
      await openPicker(t, 'recvExpiry_li1');
      // the 1st of this month, or of last month when today is the 1st: always already passed
      final back = now.day == 1 ? 1 : 0;
      await pickDay(t, 1, monthsBack: back);
      await ok(t);
      final want = DateTime(now.year, now.month - back, 1);
      expect(_iso(c.lines[0].expiry.value!), _iso(want));
      expect(find.byKey(const Key('recvExpiryPast_li1')), findsOneWidget);
      expect(find.text('This date has already passed — the stock will be treated as expired.'), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('recvConfirm'))).onPressed, isNotNull, reason: 'the warning does not block; the server decides');
      await submit(t);
      expect(firstLine()['expiryDate'], _iso(want));
    });

    testWidgets('clearing the date removes it, the warning, and the payload key', (t) async {
      await mount(t);
      c.lines[0].expiry.value = DateTime.now().subtract(const Duration(days: 30));
      await t.pump();
      expect(find.byKey(const Key('recvExpiryPast_li1')), findsOneWidget);
      await t.tap(find.descendant(of: find.byKey(const Key('recvExpiry_li1')), matching: find.byTooltip('Clear')));
      await t.pump();
      expect(c.lines[0].expiry.value, isNull);
      expect(find.byKey(const Key('recvExpiryPast_li1')), findsNothing);
      expect(find.text('Expiry date'), findsOneWidget);
      await submit(t);
      expect(firstLine().containsKey('expiryDate'), isFalse);
    });

    testWidgets('cancelling the picker keeps what was there', (t) async {
      await mount(t);
      await openPicker(t, 'recvExpiry_li1');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.lines[0].expiry.value, isNull);
    });
  });

  group('supplier invoice date', () {
    testWidgets('picking a day shows it and sends supplierInvoiceDate as an ISO date', (t) async {
      await mount(t);
      final now = DateTime.now();
      await openPicker(t, 'recvInvoiceDate');
      await pickDay(t, 1);
      await ok(t);
      expect(_iso(c.invoiceDate.value!), _iso(DateTime(now.year, now.month, 1)));
      expect(find.textContaining('Invoice date: '), findsOneWidget);
      await submit(t);
      expect(sent!['supplierInvoiceDate'], _iso(DateTime(now.year, now.month, 1)));
    });

    testWidgets('clearing it removes supplierInvoiceDate from the payload', (t) async {
      await mount(t);
      c.invoiceDate.value = DateTime.now().subtract(const Duration(days: 3));
      await t.pump();
      await t.tap(find.descendant(of: find.byKey(const Key('recvInvoiceDate')), matching: find.byTooltip('Clear')));
      await t.pump();
      expect(c.invoiceDate.value, isNull);
      expect(find.text('Invoice date'), findsOneWidget);
      await submit(t);
      expect(sent!.containsKey('supplierInvoiceDate'), isFalse);
    });

    testWidgets('the invoice date cannot be in the future: the picker stops at today and a future day cannot be chosen', (t) async {
      await mount(t);
      final now = DateTime.now();
      await openPicker(t, 'recvInvoiceDate');
      final last = t.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).lastDate;
      expect(DateTime(last.year, last.month, last.day).isAfter(DateTime(now.year, now.month, now.day)), isFalse, reason: 'lastDate is today');
      // there is no later month to go to: the chevron is absent or disabled
      final next = find.byTooltip('Next month');
      if (next.evaluate().isNotEmpty) {
        expect(t.widget<IconButton>(find.ancestor(of: next, matching: find.byType(IconButton)).first).onPressed, isNull);
      }
      await ok(t);
      final picked = c.invoiceDate.value!;
      expect(_iso(picked), _iso(now), reason: 'OK returns the day the picker opened on: today');
      await submit(t);
      final sentDate = sent?['supplierInvoiceDate'] as String?;
      expect(sentDate == null || sentDate.compareTo(_iso(now)) <= 0, isTrue, reason: 'nothing in the future is ever sent');
    });
  });

  testWidgets('a lot line without a date sends no expiryDate and no supplierInvoiceDate at all', (t) async {
    await mount(t);
    await submit(t);
    expect(firstLine().containsKey('expiryDate'), isFalse);
    expect(sent!.containsKey('supplierInvoiceDate'), isFalse);
  });
}
