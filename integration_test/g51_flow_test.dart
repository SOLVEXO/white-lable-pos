// REAL end-to-end for G5.1 on the iOS simulator against the dev stack (real repositories, real API):
//   · a till with no cached receipt base prints WITHOUT a QR (and with the server's base, the QR is base + client key)
//   · clocking someone else (G5.4): refused without a PIN, approved with the member's own PIN, approved with a manager's PIN
//   · the shared receipt link opens the public receipt
//   · the G5.1 screens against the real backend: staff profile, orders by cashier / register, stock by location, products a supplier supplied,
//     scan-to-add on a PO, scan-to-receive, About / Help / Hardware check
// Not driven here: the camera itself (continuous scan) and a real photo upload (the dev stack would send it to the real storage provider) —
// both are covered by unit / backend tests.
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g51_flow_test.dart
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/about_help_views.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/staff_profile_view.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/config/app_version.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

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
    expect(await t.setUpDevice(name: 'g51 probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> app(WidgetTester tester, Widget w) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), theme: AppTheme.light, home: w)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<({int status, String body})> open(String url) async {
    final res = await Dio(BaseOptions(validateStatus: (_) => true, responseType: ResponseType.plain)).get('${AppEnv.apiBaseUrl}${Uri.parse(url).path}');
    return (status: res.statusCode ?? 0, body: '${res.data}');
  }

  testWidgets('G5.1 receipt QR only from the server base; the shared link opens the public receipt', (tester) async {
    final t = await till(cashierEmail, cashierPin);
    await t.closeAnyOpenShift();
    final session = await t.openShift();
    try {
      final settings = (await t.repo.getPosSettings(storeId))!;
      expect(settings.receiptLinkBase, isNotNull);
      final sold = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-REFILL', 1)], paymentMethod: 'card', status: 'completed');
      expect(sold.success, isTrue, reason: '${sold.message}');
      final s = sold.sale!;
      // a till that never received the base (fresh install, never online since G4.9): the receipt prints WITHOUT a QR
      final noBase = PosSettingsModel.fromJson({...settings.toCacheJson(), 'receiptLinkBase': null, 'storePublicId': null});
      expect(ReceiptData.fromSale(s, noBase, receiptUrl: 'https://would-be-ignored.example/r/x').qrPayload, isNull);
      // with the server's base: base + the sale's client key — and that link (shared through the share sheet) opens the receipt
      final link = ReceiptData.fromSale(s, settings).qrPayload!;
      expect(link, '${settings.receiptLinkBase}${s.clientKey}');
      final page = await open(link);
      expect([page.status, page.body.contains(s.saleNumber)], [200, true], reason: page.body);
      print('shared link $link → receipt ${s.saleNumber}');
    } finally {
      await t.closeAnyOpenShift();
    }
    await t.dispose();
  });

  testWidgets('G5.4 clocking someone else: refused without a PIN, approved with the member\'s PIN, approved with a manager\'s PIN', (tester) async {
    final t = await till(managerEmail, managerPin);
    final people = (await t.repo.getTeamMembers(storeId))!;
    final cashier = people.firstWhere((e) => e.email == cashierEmail);
    final clock = Get.put(TeamClockController(repository: t.repo, storeId: storeId), tag: 'g51clock');
    await clock.load();
    String rid() => 'g51-${DateTime.now().microsecondsSinceEpoch}';
    // start from "not clocked in" (a previous run may have left the cashier in)
    final m0 = (await t.repo.pinLogin(storeId: storeId, email: managerEmail, pin: managerPin)).employeeToken!;
    await t.repo.teamClock(storeId, action: ClockAction.clockOut, requestId: rid(), deviceAt: DateTime.now(), onBehalfOf: cashier.id, approverToken: m0);

    final none = await t.repo.teamClock(storeId, action: ClockAction.clockIn, requestId: rid(), deviceAt: DateTime.now(), onBehalfOf: cashier.id);
    expect([none.success, none.code], [false, 'POS_APPROVAL_REQUIRED']);
    // the member's own PIN (the sheet does this PIN login; it is not kept as the till's session)
    final memberTok = (await t.repo.pinLogin(storeId: storeId, email: cashierEmail, pin: cashierPin)).employeeToken!;
    expect(await clock.clockOnBehalf(member: cashier, action: ClockAction.clockIn, approverToken: memberTok), isNull);
    // the till's own session is still the manager's
    expect((await t.repo.getTeamMe(storeId))!.employeeId, isNot(cashier.id));
    final mgrTok = (await t.repo.pinLogin(storeId: storeId, email: managerEmail, pin: managerPin)).employeeToken!;
    expect(await clock.clockOnBehalf(member: cashier, action: ClockAction.clockOut, approverToken: mgrTok), isNull);
    // both events are on the cashier's record, with who did it and who approved (the audit log has them too)
    final audit = ((await owner.get('/api/pos/audit-logs/$storeId?action=attendance_clocked_on_behalf')).data as Map)['data'];
    final rows = (audit is Map ? (audit['logs'] ?? audit['items'] ?? audit['rows']) : audit) as List? ?? const [];
    final mine = rows.where((r) => r is Map && '${r['targetId']}' == cashier.id).toList();
    expect(mine.length, greaterThanOrEqualTo(2), reason: 'audit rows: $audit');
    print('on-behalf: member_pin + manager_pin recorded for ${cashier.name}');
    Get.delete<TeamClockController>(tag: 'g51clock', force: true);
    await t.dispose();
  });

  testWidgets('G5.1 screens against the real backend: staff profile, orders filters, stock by location, products supplied, scan-to-add / receive, About / Help / Hardware', (tester) async {
    final t = await till(managerEmail, managerPin);
    final people = (await t.repo.getTeamMembers(storeId))!;
    final cashier = people.firstWhere((e) => e.email == cashierEmail);

    // staff profile (the cashier signed in on a till in this run → a last login exists)
    final prof = (await t.repo.getStaffProfile(storeId, cashier.id))!;
    expect([prof.name, prof.lastLoginAt != null, prof.cur != null], [cashier.name, true, true]);
    await app(tester, StaffProfileView(employeeId: cashier.id, repository: t.repo, storeId: storeId));
    expect(find.text(cashier.name), findsWidgets);
    expect(find.byKey(const Key('staffSales30')), findsOneWidget);

    // orders by cashier and by register
    final byCashier = await t.repo.getSales(storeId: storeId, employeeId: cashier.id);
    expect(byCashier.items.every((s) => s.employeeId == cashier.id), isTrue);
    final byRegister = await t.repo.getSales(storeId: storeId, registerId: registerId);
    expect(byRegister.items.every((s) => s.registerId == registerId), isTrue);
    expect(byRegister.items, isNotEmpty);

    // stock by location (a location the owner creates once on the dev stack)
    var locs = await t.repo.getStoreLocations(storeId) ?? [];
    if (!locs.any((l) => l.name == 'E2E Back store')) {
      await owner.post('/api/pos/locations/$storeId', {'name': 'E2E Back store'});
      locs = await t.repo.getStoreLocations(storeId) ?? [];
    }
    final back = locs.firstWhere((l) => l.name == 'E2E Back store');
    final atBack = await t.repo.getInventoryStock(storeId, locationId: back.id);
    expect(atBack, isNotNull, reason: 'the location filter answers (${t.repo.lastErrorCode})');
    expect(atBack!.items.every((r) => r.locationStock != null), isTrue);

    // products supplied (the seeded "Dev Bakery Supplier" has the G4 draft PO for the croissant)
    final sups = (await t.repo.getSuppliers(storeId))!;
    final bakery = sups.suppliers.firstWhere((s) => s.name == 'Dev Bakery Supplier');
    final profile = (await t.repo.getSupplier(storeId, bakery.id))!;
    print('products supplied by ${bakery.name}: ${profile.supplied.map((x) => '${x.name} ${x.receivedQty}/${x.orderedQty}').join(', ')}');
    expect(profile.supplied, isNotEmpty, reason: 'run the G4 flow once (it creates the draft PO), or npm run dev:seed');

    // scan-to-add / scan-to-receive (the camera's onCode path, with a real lookup by SKU)
    final po = Get.put(PoFormController(repository: t.repo, storeId: storeId), tag: 'g51po');
    expect(await po.addByCode('DEV-REFILL'), startsWith('Added '));
    expect(await po.addByCode('DEV-REFILL'), endsWith('— 2'));
    expect(await po.addByCode('NO-SUCH-CODE-E2E'), 'Not found: NO-SUCH-CODE-E2E');
    final rc = Get.put(ReceiveController(repository: t.repo, storeId: storeId), tag: 'g51rc');
    expect(await rc.addByCode('DEV-REFILL'), startsWith('Added '));
    expect(rc.lines.single.good.value, 1);

    // About / Help / Hardware check
    await app(tester, const AboutView());
    expect(find.text('Version ${AppVersion.label}'), findsOneWidget);
    expect(find.text(storeId), findsOneWidget);
    await app(tester, const HelpView());
    expect(find.text('Offline'), findsOneWidget);
    await app(tester, const HardwareCheckView());
    expect(find.byKey(const Key('hwTestPrint')), findsOneWidget);
    await t.dispose();
  });
}
