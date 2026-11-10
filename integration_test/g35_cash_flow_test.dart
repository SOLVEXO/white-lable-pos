// REAL end-to-end for G3.5 Cash & daybook on the iOS simulator against the dev stack (real repositories, real API):
//   manager opens a shift → cash in (float top-up) → cash out (safe drop) → the SAME request replayed is booked once
//   a cashier's cash-out above the store limit is refused (POS_APPROVAL_REQUIRED); a manager's is allowed (own approver, audited)
//   drawer expense (cash-out on the shift) + bank expense (recorded only), replay = duplicate; a cash sale
//   the daybook lists every movement in order with a running balance that equals the shift's expected cash; close with a 2.00 shortage →
//   the daybook shows the SAME expected cash and variance as the close report; after close, cash movements / drawer expenses are refused (NO_OPEN_SHIFT)
//   a cashier's daybook contains only the shifts they opened
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g35_cash_flow_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
    expect(await t.setUpDevice(name: 'g35 cash probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  String rid(String p) => '$p-${DateTime.now().microsecondsSinceEpoch}';

  testWidgets('G3.5 cash: movements, limits, replay, expenses, daybook = shift close, closed shift refuses', (tester) async {
    var t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final since = DateTime.now().subtract(const Duration(days: 1));
    final until = DateTime.now().add(const Duration(days: 1));

    final cfg = await t.repo.getCashConfig(storeId);
    expect(cfg, isNotNull);
    expect(cfg!.cashOutCategories, contains('safe_drop'));
    expect(cfg.cashInCategories, contains('float_topup'));
    print('config ok: ${cfg.cashInCategories} / ${cfg.cashOutCategories}');

    // ── a · cash in / out, replay ─────────────────────────────────────────────────────────────────────────────────────────────
    final inId = rid('in');
    final cashIn = await t.repo.recordCashMovement(storeId, type: 'cash_in', category: 'float_topup', amountMinor: 2000, sessionId: session.id, requestId: inId, occurredAt: DateTime.now());
    expect(cashIn.success, isTrue, reason: 'cash in: ${cashIn.message}');
    final replay = await t.repo.recordCashMovement(storeId, type: 'cash_in', category: 'float_topup', amountMinor: 2000, sessionId: session.id, requestId: inId, occurredAt: DateTime.now());
    expect(replay.result!.duplicate, isTrue, reason: 'the same request is booked once');
    final out = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'safe_drop', amountMinor: 500, sessionId: session.id, requestId: rid('out'));
    expect(out.success, isTrue, reason: 'cash out: ${out.message}');
    final noNote = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'other_out', amountMinor: 100, sessionId: session.id, requestId: rid('o'));
    expect(noNote.code, 'NOTE_REQUIRED');
    final big = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'bank_deposit', amountMinor: 15000, sessionId: session.id, requestId: rid('big'));
    expect(big.success, isTrue, reason: 'a manager above the limit approves themselves (audited): ${big.message}');
    print('a ok: in 20.00, out 5.00 + 150.00, replay duplicate');

    // ── b · expenses ──────────────────────────────────────────────────────────────────────────────────────────────────────────
    final exId = rid('ex');
    final drawer = await t.repo.recordExpense(storeId, category: 'supplies', method: 'cash', amountMinor: 750, sessionId: session.id, requestId: exId, payee: 'Corner shop', occurredAt: DateTime.now());
    expect(drawer.success, isTrue, reason: 'drawer expense: ${drawer.message}');
    expect(drawer.result!.expense.status, 'recorded');
    final again = await t.repo.recordExpense(storeId, category: 'supplies', method: 'cash', amountMinor: 750, sessionId: session.id, requestId: exId, payee: 'Corner shop');
    expect(again.result!.duplicate, isTrue);
    expect(again.result!.expense.id, drawer.result!.expense.id);
    final bank = await t.repo.recordExpense(storeId, category: 'rent', method: 'bank', amountMinor: 12000, requestId: rid('bank'), payee: 'Landlord');
    expect(bank.success, isTrue, reason: 'bank expense: ${bank.message}');
    final approved = await t.repo.decideExpense(storeId, drawer.result!.expense.id, approve: true);
    expect(approved.expense!.status, 'approved');
    final list = await t.repo.getExpenses(storeId);
    expect(list!.expenses.map((e) => e.id), containsAll([drawer.result!.expense.id, bank.result!.expense.id]));
    print('b ok: ${drawer.result!.expense.number} (drawer), ${bank.result!.expense.number} (bank)');

    // ── c · a cash sale, then the daybook ────────────────────────────────────────────────────────────────────────────────────
    final latte = await t.line('DEV-LATTE', 1);
    final sale = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [latte], paymentMethod: 'cash', status: 'completed');
    expect(sale.success, isTrue, reason: 'sale: ${sale.message}');
    final book = (await t.repo.getDaybook(storeId, from: since, to: until))!;
    final shift = book.shifts.firstWhere((s) => s.sessionId == session.id);
    final types = shift.lines.map((l) => l.type).toList();
    expect(types.first, 'opening');
    expect(types, containsAll(['cash_sale', 'cash_in', 'cash_out', 'expense']));
    expect(types.where((x) => x == 'expense'), hasLength(1), reason: 'the bank expense never touched the drawer');
    var run = 0;
    for (final l in shift.lines) {
      run += l.amountMinor;
      expect(l.runningMinor, run, reason: 'a real running balance');
    }
    expect(shift.reconciled, isTrue);
    expect(shift.expectedCashMinor, run);
    print('c ok: ${shift.lines.length} lines, expected ${shift.expectedCashMinor} minor, reconciled');

    // ── d · the cashier cannot take a big cash-out alone; sees only their own shifts ─────────────────────────────────────
    await t.dispose();
    t = await till(cashierEmail, cashierPin);
    final denied = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'petty', amountMinor: 10001, sessionId: session.id, requestId: rid('cbig'));
    expect(denied.success, isFalse);
    expect(denied.code, 'POS_APPROVAL_REQUIRED');
    final small = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'petty', amountMinor: 300, sessionId: session.id, requestId: rid('csmall'));
    expect(small.success, isTrue, reason: 'a cashier up to the limit: ${small.message}');
    final mine = (await t.repo.getDaybook(storeId, from: since, to: until))!;
    expect(mine.ownShiftsOnly, isTrue);
    expect(mine.shifts.where((s) => s.sessionId == session.id), isEmpty, reason: 'the shift was opened by the manager');
    print('d ok: cashier above the limit → ${denied.code}; own shifts only');
    await t.dispose();

    // ── e · close with a 2.00 shortage: the daybook says what the close report says ────────────────────────────────────────
    t = await till(managerEmail, managerPin);
    final before = (await t.repo.getDaybook(storeId, from: since, to: until))!.shifts.firstWhere((s) => s.sessionId == session.id);
    final counted = (before.expectedCashMinor - 200) / 100;
    final closed = await t.repo.closeSession(sessionId: session.id, closingCash: counted);
    expect(closed.success, isTrue, reason: 'close: ${closed.message}');
    final after = (await t.repo.getDaybook(storeId, from: since, to: until))!.shifts.firstWhere((s) => s.sessionId == session.id);
    expect(after.status, 'closed');
    expect(after.expectedCashMinor, (closed.session!.expectedCash * 100).round(), reason: 'the daybook equals the close report');
    expect(after.varianceMinor, -200);
    expect(after.countedMinor, (counted * 100).round());
    expect(after.reconciled, isTrue);
    print('e ok: expected ${after.expectedCashMinor}, counted ${after.countedMinor}, variance ${after.varianceMinor}');

    // ── f · a closed shift refuses cash movements and drawer expenses ───────────────────────────────────────────────────────
    final late = await t.repo.recordCashMovement(storeId, type: 'cash_out', category: 'petty', amountMinor: 100, sessionId: session.id, requestId: rid('late'));
    expect(late.code, 'NO_OPEN_SHIFT');
    final lateEx = await t.repo.recordExpense(storeId, category: 'supplies', method: 'cash', amountMinor: 100, sessionId: session.id, requestId: rid('lateex'));
    expect(lateEx.code, 'NO_OPEN_SHIFT');
    print('f ok: closed shift refuses');
    await t.dispose();
  });
}
