// G5.1: the printed QR only from the server base; print notices per document; clocking someone else (G5.4); stock by location; scan-to-add /
// scan-to-receive; staff profile; About / Help / Hardware check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/about_help_views.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/on_behalf_clock_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/staff_profile_view.dart';
import 'package:solvexo_pos/config/app_version.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

import 'g25_returns_documents_test.dart' show invoiceSale, note;
import 'support/g36_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

class _Printer extends Mock implements ThermalPrinterService {}

class _Queue extends PendingTeamSyncService {
  _Queue() : super(hasCredentials: () => false);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {}
}

PosEmployeeModel emp(String id, String name, {String role = 'cashier', String email = ''}) =>
    PosEmployeeModel(id: id, storeId: 'st1', sellerId: 's', name: name, email: email.isEmpty ? '$id@e2e.test' : email, role: role, shiftIds: const [], status: 'active', createdAt: DateTime(2026));

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(430, 1400));
  await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: w)));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  late _Repo repo;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(DateTime(2026));
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
  });

  group('printed receipt QR: only the server-provided base', () {
    test('no base cached → no QR (never a guessed or another link); with the base → base + client key', () {
      final noBase = PosSettingsModel.fromJson({'storeId': 'st1', 'taxRate': 0});
      expect(printedReceiptQr(noBase, 'pos-1762851600000000-0123456789abcdef01234567'), isNull);
      final withBase = PosSettingsModel.fromJson({'storeId': 'st1', 'taxRate': 0, 'receiptLinkBase': 'https://api.solvexo.store/r/s/dev-coffee/'});
      expect(printedReceiptQr(withBase, 'pos-1762851600000000-0123456789abcdef01234567'), 'https://api.solvexo.store/r/s/dev-coffee/pos-1762851600000000-0123456789abcdef01234567');
      expect(printedReceiptQr(PosSettingsModel.fromJson({'storeId': 'st1', 'taxRate': 0, 'receiptLinkBase': 'https://x/r/s/a/', 'receiptOptions': {'showQr': false}}), 'pos-1762851600000000-0123456789abcdef01234567'), isNull);
    });
  });

  group('documents: the print notice belongs to its document', () {
    test('"Printed." on the invoice is not shown on the credit note, and the other way round', () async {
      final sale = invoiceSale();
      final cn = note();
      final printer = _Printer();
      when(() => printer.hasSavedPrinter).thenReturn(true);
      when(() => printer.printDocument(any())).thenAnswer((_) async => null);
      when(() => repo.getSaleById(any())).thenAnswer((_) async => sale);
      when(() => repo.getSaleDocuments(any())).thenAnswer((_) async => PosSaleDocuments(saleNumber: sale.saleNumber, status: 'completed', creditNotes: [cn]));
      when(() => repo.recordReprint(any(), documentType: any(named: 'documentType'), documentId: any(named: 'documentId'), approverToken: any(named: 'approverToken'), kind: any(named: 'kind')))
          .thenAnswer((_) async => (success: true, code: null, message: null, reprintNumber: 0, kind: 'original'));
      final c = PosDocumentsController(repository: repo, saleId: sale.id, printer: printer, requirePinCached: (_) async => false);
      Get.put(c);
      await c.load();
      await c.printInvoice();
      expect([c.noticeFor('invoice:${sale.id}'), c.noticeFor('credit_note:${cn.id}')], ['Printed.', null]);
      await c.printCreditNote(cn);
      expect([c.noticeFor('invoice:${sale.id}'), c.noticeFor('credit_note:${cn.id}')], [null, 'Printed.']);
    });
  });

  group('G5.4 clocking someone else', () {
    TeamClockController make() => TeamClockController(
      repository: repo,
      cache: testTeamCache(),
      queue: _Queue(),
      storeId: 'st1',
      employeeIdProvider: () async => 'e1',
      employeeNameProvider: () async => 'Sam',
      employeeTokenProvider: () async => 'tok-sam',
      requestIdFactory: () => 'rid-1',
      clock: () => DateTime(2026, 11, 11, 9),
    );
    void stub(({bool success, String? message, String? code, bool retryable, ClockResult? result}) r) => when(
      () => repo.teamClock('st1', action: any(named: 'action'), requestId: any(named: 'requestId'), deviceAt: any(named: 'deviceAt'), note: any(named: 'note'), employeeToken: any(named: 'employeeToken'), onBehalfOf: any(named: 'onBehalfOf'), approverToken: any(named: 'approverToken')),
    ).thenAnswer((_) async => r);

    test('online: sent with the member id and the approver token; the notice names the member; refusals in words', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);
      final c = make();
      stub((success: true, message: null, code: null, retryable: false, result: null));
      expect(await c.clockOnBehalf(member: emp('e2', 'Sana'), action: ClockAction.clockIn, approverToken: 'tok-sana'), isNull);
      final call = verify(() => repo.teamClock('st1', action: 'clock_in', requestId: 'rid-1', deviceAt: any(named: 'deviceAt'), note: any(named: 'note'), employeeToken: 'tok-sam', onBehalfOf: 'e2', approverToken: 'tok-sana'));
      call.called(1);
      expect(c.notice.value, contains('Sana'));
      stub((success: false, message: 'x', code: 'POS_APPROVAL_REQUIRED', retryable: false, result: null));
      expect(await c.clockOnBehalf(member: emp('e2', 'Sana'), action: ClockAction.clockIn, approverToken: 'bad'), contains('not Sana\'s or a manager\'s'));
    });

    test('offline: refused here, nothing sent or queued (a PIN cannot be checked without the server)', () async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
      final c = make();
      expect(await c.clockOnBehalf(member: emp('e2', 'Sana'), action: ClockAction.clockIn, approverToken: 't'), contains('needs a connection'));
      verifyNever(() => repo.teamClock(any(), action: any(named: 'action'), requestId: any(named: 'requestId'), deviceAt: any(named: 'deviceAt'), onBehalfOf: any(named: 'onBehalfOf'), approverToken: any(named: 'approverToken')));
    });

    testWidgets('the sheet: pick the member, they type THEIR PIN → clocked; another person\'s PIN is refused; "use a manager\'s PIN" asks for the manager email', (t) async {
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);
      final c = make();
      stub((success: true, message: null, code: null, retryable: false, result: null));
      final sana = emp('e2', 'Sana');
      when(() => repo.pinLogin(storeId: any(named: 'storeId'), email: 'e2@e2e.test', pin: '1234')).thenAnswer((_) async => (success: true, employee: sana, activeSession: null, employeeToken: 'tok-sana', message: null));
      when(() => repo.pinLogin(storeId: any(named: 'storeId'), email: 'e2@e2e.test', pin: '9999')).thenAnswer((_) async => (success: true, employee: emp('e3', 'Other'), activeSession: null, employeeToken: 'tok-x', message: null));
      await pump(t, Scaffold(body: SingleChildScrollView(child: OnBehalfClockSheet(controller: c, repository: repo, members: [sana]))));
      await t.tap(find.byKey(const Key('onBehalf_e2')));
      await t.pump();
      expect(find.text('Sana, enter your PIN.'), findsOneWidget);
      Future<void> pin(String p) async {
        for (final d in p.split('')) {
          await t.tap(find.text(d).last);
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 200));
      }

      await pin('9999');
      expect(find.text('That is not Sana\'s PIN.'), findsOneWidget);
      await pin('1234');
      verify(() => repo.teamClock('st1', action: 'clock_in', requestId: any(named: 'requestId'), deviceAt: any(named: 'deviceAt'), note: any(named: 'note'), employeeToken: 'tok-sam', onBehalfOf: 'e2', approverToken: 'tok-sana')).called(1);
    });
  });

  group('stock list by location', () {
    test('the locations load; picking one reloads with its id; All clears it', () async {
      final seen = <String?>[];
      when(() => repo.getInventoryStock('st1', search: any(named: 'search'), filter: any(named: 'filter'), page: any(named: 'page'), limit: any(named: 'limit'), locationId: any(named: 'locationId'))).thenAnswer((i) async {
        seen.add(i.namedArguments[#locationId] as String?);
        return InvPage<InvRow>(items: [InvRow(variantId: 'v1', productId: 'p1', productName: 'Rice', stock: 9, locationStock: i.namedArguments[#locationId] == null ? null : 4)], total: 1, page: 1, hasMore: false);
      });
      final c = InvStockListController(repository: repo, storeId: 'st1', locations: (_) async => [StoreLocationModel(id: 'l1', storeId: 'st1', sellerId: 's', name: 'Back store', status: 'active', createdAt: DateTime(2026))]);
      c.onInit();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.locations.map((l) => l.name), ['Back store']);
      c.setLocation('l1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.items.single.locationStock, 4);
      c.setLocation(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(seen, [null, 'l1', null]);
    });
  });

  group('scan-to-add / scan-to-receive', () {
    InvRow row(String v, String name) => InvRow(variantId: v, productId: 'p$v', productName: name, sku: 'SKU$v');

    test('PO form: a scan adds the line, a second scan adds one more; unknown codes say so', () async {
      when(() => repo.lookupInventory('st1', 'RICE5')).thenAnswer((_) async => [row('v1', 'Rice 5kg')]);
      when(() => repo.lookupInventory('st1', 'NOPE')).thenAnswer((_) async => <InvRow>[]);
      final c = PoFormController(repository: repo, storeId: 'st1');
      expect(await c.addByCode('RICE5'), 'Added Rice 5kg — 1');
      expect(await c.addByCode('RICE5'), 'Added Rice 5kg — 2');
      expect(await c.addByCode('NOPE'), 'Not found: NOPE');
      expect([c.lines.length, c.lines.single.qty.value], [1, 2]);
    });

    test('receiving without an order: a scan adds the product, the next adds a unit', () async {
      when(() => repo.lookupInventory('st1', 'OIL1')).thenAnswer((_) async => [row('v2', 'Oil 1L')]);
      final c = ReceiveController(repository: repo, storeId: 'st1', requestIdFactory: () => 'rid');
      expect(await c.addByCode('OIL1'), 'Added Oil 1L — 1');
      expect(await c.addByCode('OIL1'), 'Oil 1L — 2');
      expect(c.lines.single.good.value, 2);
    });
  });

  group('staff profile, About, Help, Hardware check', () {
    testWidgets('profile: last login, clocked in, sales windows in the store currency', (t) async {
      when(() => repo.getStaffProfile('st1', 'e2')).thenAnswer(
        (_) async => StaffProfile.fromJson({
          'employeeId': 'e2', 'name': 'Sana', 'role': 'cashier', 'lastLoginAt': '2026-11-11T08:00:00Z', 'state': {'clockedIn': true, 'since': '2026-11-11T08:05:00Z'},
          'currency': 'PKR', 'currencyExponent': 2,
          'sales': {'today': {'sales': 3, 'totalMinor': 450000}, 'last7Days': {'sales': 9, 'totalMinor': 1200000}, 'last30Days': {'sales': 40, 'totalMinor': 5100000}},
        }),
      );
      await pump(t, StaffProfileView(employeeId: 'e2', repository: repo, storeId: 'st1'));
      expect(find.text('Clocked in'), findsOneWidget);
      expect(find.textContaining('3 · '), findsOneWidget);
      expect(find.byKey(const Key('staffLastLogin')), findsOneWidget);
    });

    testWidgets('About shows the version, the store id and the environment; Help lists topics; Hardware says when no printer is set up', (t) async {
      await pump(t, const AboutView(storeIdOverride: 'st1', receiptBaseOverride: 'https://api.solvexo.store/r/s/dev/'));
      expect(find.text('Version ${AppVersion.label}'), findsOneWidget);
      expect(find.text('st1'), findsOneWidget);
      expect(find.byKey(const Key('aboutEnv')), findsOneWidget);
      expect(find.byKey(const Key('aboutLicences')), findsOneWidget);
      await pump(t, const HelpView());
      expect(find.text('Offline'), findsOneWidget);
      final pr = _Printer();
      when(() => pr.hasSavedPrinter).thenReturn(false);
      await pump(t, HardwareCheckView(printer: pr, cameraScan: () async => '4006381333931'));
      await t.tap(find.byKey(const Key('hwTestPrint')));
      await t.pump();
      expect(find.textContaining('No printer is set up'), findsOneWidget);
      await t.enterText(find.byKey(const Key('hwScanBox')), '1234567890');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Read: 1234567890'), findsOneWidget);
    });
  });
}
