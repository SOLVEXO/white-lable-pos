// REAL end-to-end for the G4 modules on the iOS simulator against the dev stack (real repositories, real API, USD store):
//   G4.2 roles: a manager reads the matrix (cannot edit), a cashier is refused, the owner previews → saves with the version read; a stale version →
//        VERSION_CONFLICT; reset to defaults
//   G4.3 audit: the integrity check answers for the period (managers)
//   G4.4 settings: the owner changes the receipt + auto-lock, a manager reads them and is refused a change
//   G4.5 pricing: a manager creates a modifier group + a price book; the quote and the sale are priced by the server with them (modifiers and base
//        price on the line); a book switched off → PRICE_BOOK_NOT_ACTIVE
//   G4.6 shift + stock: open with a notes & coins count (a wrong count → DENOMINATION_MISMATCH), close with one, the last close reads back; expiry
//        buckets, transfers and low stock → draft PO answer
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g4_flow_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
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
    expect(await t.setUpDevice(name: 'g4 probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  /// the owner's elevated session on this till (password re-authentication), as the app does before an owner-only screen
  Future<void> asOwner() async {
    final tok = await AuthRepository().verifyOwnerPassword(email: ownerEmail, password: ownerPassword);
    expect(tok, isNotNull, reason: 'owner re-authentication');
    OwnerSession.start(tok!);
  }

  testWidgets('G4.2 roles, G4.3 integrity, G4.4 settings', (tester) async {
    // cashier: refused
    var t = await till(cashierEmail, cashierPin);
    expect(await t.repo.getPermissionMatrix(storeId), isNull);
    expect(t.repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    await t.dispose();

    // manager: reads, cannot edit; integrity answers; settings read, change refused
    t = await till(managerEmail, managerPin);
    final m = (await t.repo.getPermissionMatrix(storeId))!;
    expect(m.canEdit, isFalse);
    expect(m.actions.where((a) => a.pinned), isNotEmpty);
    final v = await t.repo.verifyAuditSeals(storeId);
    expect(v, isNotNull, reason: 'integrity check: ${t.repo.lastErrorCode}');
    print('integrity: ok=${v!.ok} days=${v.days}');
    expect(v.results.every((d) => d.status == 'ok'), isTrue, reason: 'nothing on the dev stack was altered after sealing');
    final s0 = (await t.repo.getStoreSettings(storeId))!;
    expect(s0.canEdit, isFalse);
    final refused = await t.repo.updateStoreSettings(storeId, {'alerts': {'lowStock': false}});
    expect([refused.success, refused.code], [false, 'POS_ACTION_FORBIDDEN']);

    // owner: preview → save with the version read; a stale version → VERSION_CONFLICT; reset
    await asOwner();
    final om = (await t.repo.getPermissionMatrix(storeId))!;
    expect(om.canEdit, isTrue);
    // a REAL change read from the matrix: an editable action a cashier may do today → managers and the owner only
    final target = om.actions.firstWhere((a) => !a.pinned && a.roles.contains('cashier'));
    final changes = {
      target.action: {'roles': ['manager', 'owner']},
    };
    try {
      final preview = await t.repo.updatePermissions(storeId, changes, preview: true);
      expect(preview.success, isTrue, reason: 'preview: ${preview.message}');
      expect(preview.diff.single.action, target.action);
      final saved = await t.repo.updatePermissions(storeId, changes, expectedVersion: om.version);
      expect(saved.success, isTrue, reason: 'save: ${saved.code} ${saved.message}');
      expect(saved.matrix!.version, greaterThan(om.version));
      expect(saved.matrix!.actions.firstWhere((a) => a.action == target.action).roles, isNot(contains('cashier')));
      final stale = await t.repo.updatePermissions(storeId, {target.action: {'roles': ['cashier', 'manager', 'owner']}}, expectedVersion: om.version);
      expect([stale.success, stale.code], [false, 'VERSION_CONFLICT']);
      // settings: the owner changes the receipt and the auto-lock
      final up = await t.repo.updateStoreSettings(storeId, {
        'receipt': {'promoText': 'G4 e2e promo', 'showTaxId': false},
        'security': {'autoLockMinutes': 7},
      });
      expect(up.success, isTrue, reason: 'settings: ${up.code} ${up.message}');
      expect([up.settings!.receipt.promoText, up.settings!.receipt.showTaxId, up.settings!.security.autoLockMinutes], ['G4 e2e promo', false, 7]);
      // the till's own settings (which price and print receipts) carry the designer's options
      expect((await t.repo.getPosSettings(storeId))!.receiptOptions.promoText, 'G4 e2e promo');
    } finally {
      expect((await t.repo.resetPermissions(storeId)).success, isTrue, reason: 'reset to defaults');
      await t.repo.updateStoreSettings(storeId, {
        'receipt': {'promoText': null, 'showTaxId': true},
        'security': {'autoLockMinutes': 5},
      });
      OwnerSession.end();
    }
    await t.dispose();
  });

  testWidgets('G4.5 modifiers + price books priced by the server at quote and sale', (tester) async {
    final t = await till(managerEmail, managerPin);
    final line = await t.line('DEV-REFILL', 2); // 2.50 each, unlimited stock
    final pid = line['productId'] as String, vid = line['variantId'] as String;
    final g = await t.repo.saveModifierGroup(
      storeId,
      ModifierGroup(
        id: '',
        name: 'Size e2e ${DateTime.now().millisecondsSinceEpoch}',
        minSelect: 1,
        maxSelect: 1,
        productIds: [pid],
        options: const [ModifierOption(id: '', name: 'Small'), ModifierOption(id: '', name: 'Large', priceDeltaMinor: 100)],
      ),
    );
    expect(g.success, isTrue, reason: 'modifier group: ${g.code} ${g.message}');
    final group = g.data!;
    final large = group.options.firstWhere((o) => o.name == 'Large');
    final b = await t.repo.savePriceBook(storeId, {
      'name': 'Wholesale e2e ${DateTime.now().millisecondsSinceEpoch}',
      'entries': [
        {'variantId': vid, 'priceMinor': 200},
      ],
    });
    expect(b.success, isTrue, reason: 'price book: ${b.code} ${b.message}');
    final book = b.data!;
    try {
      final mods = [
        {'groupId': group.id, 'optionIds': [large.id]},
      ];
      // the options are required: a line without them is refused online
      final bare = await t.repo.quoteSale(storeId: storeId, items: [line]);
      expect(bare.code, 'MODIFIER_REQUIRED');
      // quote: book price 2.00 + Large 1.00 = 3.00 a unit, two units
      final q = await t.repo.quoteSale(storeId: storeId, items: [{...line, 'modifiers': mods}], priceBookId: book.id);
      expect(q.quote, isNotNull, reason: 'quote: ${q.code} ${q.message}');
      expect(q.quote!.lines.single.price, 3.0);
      expect(q.quote!.lines.single.priced, isTrue);
      expect(q.quote!.subtotal, 6.0);
      // sale: the same, server-priced; the line names the option and keeps the base price
      await t.openShift();
      final sale = await t.repo.createSale(
        storeId: storeId,
        sessionId: (await t.repo.getActiveSession(storeId: storeId, registerId: registerId))!.id,
        registerId: registerId,
        employeeId: t.employee!.id,
        items: [{...line, 'modifiers': mods}],
        paymentMethod: 'card',
        status: 'completed',
        priceBookId: book.id,
      );
      expect(sale.success, isTrue, reason: 'sale: ${t.repo.lastErrorCode} ${sale.message}');
      final it = sale.sale!.items.single;
      expect(it.name, contains('(Large)'));
      expect(it.price, 3.0);
      expect(it.basePriceMinor, 200);
      expect(it.modifiers.single.optionId, large.id);
      expect(sale.sale!.priceBookName, book.name);
      // switched off: the book is refused in words at the quote
      expect((await t.repo.savePriceBook(storeId, {'active': false}, id: book.id)).success, isTrue);
      final off = await t.repo.quoteSale(storeId: storeId, items: [{...line, 'modifiers': mods}], priceBookId: book.id);
      expect(off.code, 'PRICE_BOOK_NOT_ACTIVE');
      expect(catalogErrorMessage(off.code), contains('not available now'));
    } finally {
      await t.repo.saveModifierGroup(storeId, ModifierGroup(id: group.id, name: group.name, minSelect: 0, maxSelect: 1, productIds: const [], options: group.options, active: false));
      await t.repo.savePriceBook(storeId, {'active': false}, id: book.id);
      await t.closeAnyOpenShift();
    }
    await t.dispose();
  });

  testWidgets('G4.6 notes & coins at open/close, last close, expiry, transfers, draft PO', (tester) async {
    final t = await till(managerEmail, managerPin);
    await t.closeAnyOpenShift();
    // a count that does not add up to the float is refused; one that does is kept
    final bad = await t.repo.openSession(storeId: storeId, registerId: registerId, employeeId: t.employee!.id, openingCash: 100, denominations: [{'valueMinor': 5000, 'count': 1}]);
    expect([bad.success, t.repo.lastErrorCode], [false, 'DENOMINATION_MISMATCH']);
    final open = await t.repo.openSession(storeId: storeId, registerId: registerId, employeeId: t.employee!.id, openingCash: 100, denominations: [{'valueMinor': 5000, 'count': 1}, {'valueMinor': 2000, 'count': 2}, {'valueMinor': 1000, 'count': 1}]);
    expect(open.success, isTrue, reason: 'open with notes: ${t.repo.lastErrorCode} ${open.message}');
    // close: counted 99.00 against 100.00 expected, counted note by note → the last close reads short 1.00
    final closed = await t.repo.closeSession(sessionId: open.session!.id, closingCash: 99, denominations: [{'valueMinor': 5000, 'count': 1}, {'valueMinor': 2000, 'count': 2}, {'valueMinor': 500, 'count': 1}, {'valueMinor': 100, 'count': 4}]);
    expect(closed.success, isTrue, reason: 'close with notes: ${t.repo.lastErrorCode} ${closed.message}');
    final last = (await t.repo.getLastClose(storeId, registerId))!;
    expect([last.countedMinor, last.expectedMinor, last.varianceMinor], [9900, 10000, -100]);
    expect(last.denominations.fold<int>(0, (n, d) => n + d.valueMinor * d.count), 9900);
    // expiry buckets (the seeded yogurt has an expired lot and one expiring in 3 days)
    final ex = (await t.repo.getExpiry(storeId))!;
    expect(ex.expired.any((l) => l.lotNumber == 'LOT-OLD'), isTrue);
    expect(ex.within7.any((l) => l.lotNumber == 'LOT-SOON'), isTrue);
    expect(ex.showsValue, isTrue, reason: 'a manager sees the value at cost');
    // transfers list answers
    expect(await t.repo.getTransfers(storeId), isNotNull, reason: 'transfers: ${t.repo.lastErrorCode}');
    // low stock → a draft PO (or the server's NOTHING_LOW in words when no supplier's items are low)
    final sups = (await t.repo.getSuppliers(storeId))?.suppliers ?? const [];
    if (sups.isNotEmpty) {
      final d = await t.repo.draftPoFromLowStock(storeId, sups.first.id);
      expect(d.success || d.code == 'NOTHING_LOW', isTrue, reason: 'draft PO: ${d.code} ${d.message}');
      if (d.success) expect(d.order!.status, 'draft');
      print('draft PO: ${d.success ? d.order!.poNumber : d.message}');
    }
    await t.dispose();
  });
}
