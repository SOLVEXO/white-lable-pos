// REAL end-to-end for G4.8 on the iOS simulator against the dev stack (real repositories, real API, USD store, Asia/Karachi by country):
//   · integrity: a past day sealed by the real nightly code (dev seed) verifies OK; a deliberately tampered record (dev stack only) shows the day as
//     CHANGED in the app's integrity check; restored, it verifies OK again
//   · a manager with costs hidden: no cost data anywhere (inventory, reports, supply), every response says costsHidden; the owner still sees cost
//   · reprint with "PIN to reprint" on: a cashier is refused, a manager's PIN approves, the numbers count up
//   · a price book from the STORE's tomorrow switches at the store's midnight (UTC boundaries), not the device's
//   · CSV import from a file (the picker's own read + background decode; the system picker UI itself is not driven)
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g48_flow_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/data/services/reprint_gate.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/csv_file_picker.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
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
    expect(await t.setUpDevice(name: 'g48 probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> asOwner() async {
    final tok = await AuthRepository().verifyOwnerPassword(email: ownerEmail, password: ownerPassword);
    expect(tok, isNotNull);
    OwnerSession.start(tok!);
  }

  /// The owner flips a store security setting (from the till, through the owner session), then the session ends.
  Future<void> setSecurity(Till t, Map<String, dynamic> sec) async {
    await asOwner();
    final r = await t.repo.updateStoreSettings(storeId, {'security': sec});
    expect(r.success, isTrue, reason: 'settings: ${r.code} ${r.message}');
    OwnerSession.end();
  }

  /// A response exactly as the till receives it (device token + this PIN session), for a raw scan of its keys.
  Future<Map<String, dynamic>> raw(String path) async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    final res = await dio.get(
      '${AppEnv.apiBaseUrl}$path',
      options: Options(headers: {'Authorization': 'Bearer ${AppPreferences.cachedToken}', 'x-pos-employee-token': await AppPreferences.getPosEmployeeToken()}),
    );
    expect(res.statusCode, 200, reason: '$path → ${res.statusCode} ${res.data}');
    return (res.data as Map).cast<String, dynamic>();
  }

  List<String> costKeys(dynamic v, [String at = r'$']) {
    final out = <String>[];
    final cost = RegExp(r'^(cost|unitCost|wac|averageCost|stockValue|grossMargin|margin|marginPercent|afterExpenses|costOfGoodsSold|cogs|netWithCost|netNoCost|costUnknownNet|costCoverage)');
    if (v is List) {
      for (var i = 0; i < v.length; i++) {
        out.addAll(costKeys(v[i], '$at[$i]'));
      }
    } else if (v is Map) {
      for (final e in v.entries) {
        if (cost.hasMatch('${e.key}') && e.key != 'costsHidden') out.add('$at.${e.key}'); // (the flag itself is not cost)
        out.addAll(costKeys(e.value, '$at.${e.key}'));
      }
    }
    return out;
  }

  testWidgets('G4.8 integrity: a sealed past day verifies; a tampered record shows the day as changed; restored, OK again', (tester) async {
    final t = await till(managerEmail, managerPin);
    final audit = Get.put(PosAuditLogController(posRepository: t.repo, storeId: storeId), tag: 'audit');
    audit.setRange(audit.range.value); // last 7 store days
    await audit.checkIntegrity();
    final first = audit.integrity.value!;
    expect(first.days, greaterThan(0), reason: 'the dev seed seals the past days (npm run dev:seed)');
    expect(first.ok, isTrue, reason: 'nothing changed yet: ${first.results.where((d) => !d.ok).map((d) => d.day)}');

    final tamper = await Control.tamperSeal();
    print('tampered ${tamper['recordId']} on ${tamper['day']}');
    try {
      await audit.checkIntegrity();
      final bad = audit.integrity.value!;
      expect(bad.ok, isFalse);
      final day = bad.results.firstWhere((d) => d.day == tamper['day']);
      expect(day.status, 'changed');
      expect(day.changedParts.map((p) => p.part), contains('audit_log'));
    } finally {
      await Control.untamperSeal();
    }
    await audit.checkIntegrity();
    expect(audit.integrity.value!.ok, isTrue, reason: 'restored exactly');
    await t.dispose();
  });

  testWidgets('G4.8 costs hidden: a manager sees no cost anywhere (and is told so); the owner still sees cost', (tester) async {
    var t = await till(managerEmail, managerPin);
    await setSecurity(t, {'hideCostsFromManagers': true});
    try {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      for (final path in [
        '/api/pos/inventory/overview/$storeId',
        '/api/pos/inventory/stock/$storeId',
        '/api/pos/reports/profit/$storeId?from=$day&to=$day',
        '/api/pos/reports/products/$storeId?from=$day&to=$day',
        '/api/pos/supply/orders/$storeId',
        '/api/pos/supply/payables/$storeId',
      ]) {
        final body = await raw(path);
        expect(costKeys(body['data']), isEmpty, reason: '$path still carries cost');
        if (path.contains('/reports/')) expect((body['data'] as Map)['costsHidden'], isTrue, reason: path);
      }
      // through the app's own models: the flags the screens read
      expect((await t.repo.getInventoryOverview(storeId))!.costsHidden, isTrue);
      expect((await t.repo.getBizReport(storeId, ReportKind.profit, ReportQuery(from: day, to: day)))!.head.costsHidden, isTrue);
      // the owner, with their own login (the admin panel / an unregistered terminal), still sees the stock value
      final ownerView = await owner.get('/api/pos/inventory/overview/$storeId');
      final od = (ownerView.data as Map)['data'] as Map;
      expect([od['costsHidden'], od['stockValueMinor'] != null], [null, true], reason: 'owner: $od');
    } finally {
      await setSecurity(t, {'hideCostsFromManagers': false});
    }
    await t.dispose();
    // off again: a manager sees the stock value
    t = await till(managerEmail, managerPin);
    expect((await t.repo.getInventoryOverview(storeId))!.stockValueMinor, isNotNull);
    await t.dispose();
  });

  testWidgets('G4.8 reprint with "PIN to reprint": a cashier is refused, a manager PIN approves, numbers count up', (tester) async {
    final t = await till(cashierEmail, cashierPin);
    await setSecurity(t, {'requirePinForReprint': true});
    try {
      final session = await t.openShift();
      final sale = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-REFILL', 1)], paymentMethod: 'card', status: 'completed');
      expect(sale.success, isTrue, reason: 'sale: ${sale.message}');
      final id = sale.sale!.id;
      final refused = await t.repo.recordReprint(storeId, documentType: 'sale', documentId: id);
      expect([refused.success, refused.code], [false, 'POS_APPROVAL_REQUIRED']);
      // the manager enters their PIN on this till (a PIN login that is not kept) → their token approves
      final m = await t.repo.pinLogin(storeId: storeId, email: managerEmail, pin: managerPin);
      final mgr = m.employeeToken!;
      final ok = await t.repo.recordReprint(storeId, documentType: 'sale', documentId: id, approverToken: mgr);
      expect([ok.success, ok.reprintNumber], [true, 1]);
      // the app's gate: asks for the manager, records, returns the number the print shows
      final go = await ReprintGate(repository: t.repo, askManager: (_) async => mgr).record(storeId: storeId, documentType: 'sale', documentId: id, requirePinCached: true);
      expect([go.ok, go.number], [true, 2]);
      // a cashier's own PIN is not an approval
      final c = await t.repo.pinLogin(storeId: storeId, email: cashierEmail, pin: cashierPin);
      final no = await ReprintGate(repository: t.repo, askManager: (_) async => c.employeeToken).record(storeId: storeId, documentType: 'sale', documentId: id, requirePinCached: true);
      expect(no.ok, isFalse);
    } finally {
      await setSecurity(t, {'requirePinForReprint': false});
      await t.closeAnyOpenShift();
    }
    await t.dispose();
  });

  testWidgets('G4.8 price book from the store\'s tomorrow: switches at the store\'s midnight (UTC), whatever the device zone', (tester) async {
    final t = await till(managerEmail, managerPin);
    final tz = (await t.repo.getStoreTimeZone(storeId))!;
    final today = parseDayKey(tz.today)!;
    final tomorrow = dayKey(DateTime(today.year, today.month, today.day + 1));
    final variantId = (await t.line('DEV-REFILL', 1))['variantId'] as String;
    final made = await t.repo.savePriceBook(storeId, {
      'name': 'From tomorrow e2e ${DateTime.now().millisecondsSinceEpoch}',
      'validFrom': tomorrow,
      'validTo': tomorrow,
      'entries': [
        {'variantId': variantId, 'priceMinor': 200},
      ],
    });
    expect(made.success, isTrue, reason: 'book: ${made.code} ${made.message}');
    final b = made.data!;
    try {
      expect([b.validFromDay, b.validToDay, b.timeZone], [tomorrow, tomorrow, tz.timeZone]);
      // the store's midnight, as a UTC instant: Asia/Karachi is UTC+5 → 19:00Z the day before
      expect(b.validFromUtc!.isUtc, isTrue);
      print('validFromUtc ${b.validFromUtc!.toIso8601String()} (store ${tz.timeZone}), device offset ${DateTime.now().timeZoneOffset}');
      expect(b.inForceAt(b.validFromUtc!.subtract(const Duration(seconds: 1))), isFalse);
      expect(b.inForceAt(b.validFromUtc!), isTrue);
      expect(b.inForceAt(b.validToUtc!), isFalse, reason: 'the end is exclusive');
      expect(b.validToUtc!.difference(b.validFromUtc!), const Duration(hours: 24), reason: 'one store day (no DST in Karachi)');
      // listed: not in force yet (server and app agree), and the app's picker leaves it out
      final listed = (await t.repo.getPriceBooks(storeId))!.books.firstWhere((x) => x.id == b.id);
      expect([listed.inForce, listed.inForceAt(DateTime.now().toUtc()), listed.scheduledAt(DateTime.now())], [false, false, true]);
    } finally {
      await t.repo.savePriceBook(storeId, {'active': false}, id: b.id);
    }
    await t.dispose();
  });

  testWidgets('G4.8 CSV import from a file: read + decoded in the background, imported, reported', (tester) async {
    final t = await till(managerEmail, managerPin);
    final dir = await Directory.systemTemp.createTemp('g48csv');
    final name = 'E2E Cat ${DateTime.now().millisecondsSinceEpoch}';
    final f = File('${dir.path}/categories.csv')..writeAsStringSync('﻿name\n$name\n');
    // the same read the picker does after the system dialog (size check, then decode off the UI thread)
    Future<PickedCsv?> fromFile() async {
      final bytes = await f.readAsBytes();
      if (bytes.length > csvMaxBytes) throw CsvFileTooLarge(bytes.length);
      final d = await compute(decodeCsv, bytes);
      return (name: 'categories.csv', text: d.text, rows: d.rows);
    }

    final c = Get.put(CsvImportController(repository: t.repo, storeId: storeId, filePicker: fromFile), tag: 'csv');
    c.setKind('categories');
    await c.pickFile();
    expect([c.fileName.value, c.fileRows.value], ['categories.csv', 1]);
    expect(await c.submit(), isTrue, reason: 'import: ${c.saveError.value}');
    final r = c.report.value!;
    expect(r.created + r.updated, greaterThanOrEqualTo(1), reason: 'created ${r.created} updated ${r.updated} failed ${r.failed} ${r.errors}');
    expect((await t.repo.getCatalogCategories(storeId))!.any((x) => x.name == name), isTrue);
    await dir.delete(recursive: true);
    await t.dispose();
  });
}
