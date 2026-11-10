// Screenshot pass for the G3.5 cash & expenses screens on the iOS simulator (real rendering, real fonts, mocked repositories), light AND dark in one run.
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g35_screens_shots_test.dart <outdir> <suffix>
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/daybook_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_home_view.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_movement_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/daybook_view.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/expense_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/expense_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/expense_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/views/pos_needs_attention_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import '../test/support/fake_payments.dart';
import '../test/support/g35_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

class _Sync extends Mock implements PendingSaleSyncService {}

/// A queue that only shows the rows it is given.
class _Queue extends PendingCashSyncService {
  _Queue()
    : super(
        posRepository: _Repo(),
        localStore: PendingCashLocalStore(dbPath: 'unused.db'),
      );
  void setRows(List<PendingCashRecord> rows) {
    items.assignAll(rows);
    pendingCount.value = rows.where((r) => r.isPending).length;
    failedCount.value = rows.where((r) => r.isFailed).length;
    unresolvedCount.value = pendingCount.value + failedCount.value;
  }

  @override
  Future<void> refreshCounts() async {}
  @override
  Future<void> syncNow({bool ignoreBackoff = false}) async {}
}

PendingCashRecord _rec(
  String id, {
  String status = 'pending',
  String? code,
  String? message,
  int amount = 1500,
  int attempts = 0,
  String type = 'cash_out',
  String category = 'bank_deposit',
  String kind = 'movement',
}) => PendingCashRecord(
  seq: 1,
  id: id,
  kind: kind,
  payload: {'type': type, 'category': category, 'amountMinor': amount, 'currency': 'USD', 'currencyExponent': 2, 'occurredAt': '2026-11-09T09:00:00.000Z'},
  status: status,
  createdAt: DateTime(2026, 11, 9, 9),
  storeId: 'st1',
  sessionId: 'se1',
  errorCode: code,
  errorMessage: message,
  attempts: attempts,
);

/// Registers an OFFLINE connectivity service while the app below it is being built (a replaced GetMaterialApp resets GetX when it is disposed, so a
/// service registered before the swap would be gone).
class _Offline extends StatefulWidget {
  const _Offline({required this.child});
  final Widget child;
  @override
  State<_Offline> createState() => _OfflineState();
}

class _OfflineState extends State<_Offline> {
  @override
  void initState() {
    super.initState();
    Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;

    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: w),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
    }

    _Repo fresh() {
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'USD', exponent: 2);
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getCashConfig('st1')).thenAnswer((_) async => cashConfig());
      return repo;
    }

    Future<void> sheet(WidgetTester t, Future<Object?> Function() open, {bool offline = false}) async {
      await show(t, offline ? const _Offline(child: Scaffold(body: SizedBox.shrink())) : const Scaffold(body: SizedBox.shrink()));
      open();
      await t.pump(const Duration(milliseconds: 900));
    }

    Future<void> type(WidgetTester t, String key, String text) async {
      await t.enterText(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)), text);
      await t.pump();
    }

    CashMovementController movement(_Repo repo, {String type = 'cash_in', String? session = 'se1', _Queue? queue}) => CashMovementController(
      initialType: type,
      repository: repo,
      cache: CashConfigCache(),
      queue: queue,
      storeId: 'st1',
      sessionIdProvider: () async => session,
      employeeTokenProvider: () async => 'tok',
    );

    testWidgets('G3.5 cash home and the cash sheet ($tn)', (t) async {
      var repo = fresh();
      final q = _Queue()
        ..setRows([
          _rec('a'),
          _rec('b', type: 'cash_in', category: 'float_topup', amount: 5000),
          _rec('c', status: 'failed', code: 'NO_OPEN_SHIFT', message: 'There is no open shift on this till. Open a shift first.'),
        ]);
      Get.put<PendingCashSyncService>(q);
      await show(t, const CashHomeView());
      await shot(t, 'g35_01_cash_home_waiting_to_sync', tn);

      repo = fresh();
      var c = movement(repo, queue: q);
      await sheet(t, () => CashMovementSheet.open(controller: c));
      c.pickCategory('float_topup');
      await t.pump();
      await type(t, 'cmAmount', '125.50');
      await shot(t, 'g35_02_cash_in_sheet', tn);

      repo = fresh();
      c = movement(repo, type: 'cash_out');
      await sheet(t, () => CashMovementSheet.open(controller: c));
      c.pickCategory('other_out');
      await t.pump();
      await type(t, 'cmAmount', '40');
      await shot(t, 'g35_03_cash_out_other_note_required', tn);

      repo = fresh();
      await sheet(t, () => CashMovementSheet.open(controller: movement(repo, session: null)));
      await shot(t, 'g35_04_cash_sheet_no_open_shift', tn);

      repo = fresh();
      await CashConfigCache().save('st1', cashConfig());
      c = movement(repo, queue: _Queue());
      await sheet(t, () => CashMovementSheet.open(controller: c), offline: true);
      c.pickCategory('float_topup');
      await t.pump();
      await type(t, 'cmAmount', '200');
      await shot(t, 'g35_05_cash_sheet_offline_save_on_device', tn);
    });

    testWidgets('G3.5 expenses ($tn)', (t) async {
      var repo = fresh();
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => expenseList([
          expense(),
          expense(id: 'x2', status: 'approved', category: 'meals', amountMinor: 1850, number: 'EXP-000002', payee: 'Corner Cafe'),
          expense(id: 'x3', status: 'rejected', category: 'repairs', amountMinor: 9900, number: 'EXP-000003', payee: 'Fix-It Plumbing'),
          expense(id: 'x4', category: 'utilities', amountMinor: 34000, hasReceipt: true, number: 'EXP-000004', payee: 'City Power'),
        ]),
      );
      await show(
        t,
        ExpenseListView(
          controller: Get.put(ExpenseListController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15))),
        ),
      );
      await shot(t, 'g35_06_expense_list', tn);

      repo = fresh();
      var f = ExpenseFormController(repository: repo, cache: CashConfigCache(), queue: null, storeId: 'st1', sessionIdProvider: () async => 'se1', employeeTokenProvider: () async => 'tok');
      await sheet(t, () => ExpenseFormSheet.open(controller: f));
      f.pickCategory('supplies');
      await t.pump();
      await type(t, 'exAmount', '42.75');
      await type(t, 'exPayee', 'Corner Hardware');
      await shot(t, 'g35_07_expense_form', tn);

      repo = fresh();
      await CashConfigCache().save('st1', cashConfig());
      f = ExpenseFormController(repository: repo, cache: CashConfigCache(), queue: _Queue(), storeId: 'st1', sessionIdProvider: () async => 'se1', employeeTokenProvider: () async => 'tok');
      await sheet(t, () => ExpenseFormSheet.open(controller: f), offline: true);
      f.pickCategory('transport');
      await t.pump();
      await type(t, 'exAmount', '15');
      await shot(t, 'g35_08_expense_form_offline_drawer_only', tn);

      repo = fresh();
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => null);
      await show(
        t,
        _Offline(
          child: ExpenseListView(
            controller: Get.put(ExpenseListController(repository: repo, storeId: 'st1')),
          ),
        ),
      );
      await shot(t, 'g35_09_expenses_offline_needs_internet', tn);

      repo = fresh();
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) async => expense(hasReceipt: true));
      var d = Get.put(
        ExpenseDetailController(expenseId: 'x1', repository: repo, storeId: 'st1'),
        tag: 'x1',
      );
      await show(t, ExpenseDetailView(expenseId: 'x1', controller: d));
      d.canManageHint.value = true;
      await t.pump();
      await shot(t, 'g35_10_expense_detail_manager_approve_reject', tn);

      repo = fresh();
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) async => expense(status: 'rejected', decisionNote: 'Duplicate of EXP-000003', hasReceipt: true));
      d = Get.put(
        ExpenseDetailController(expenseId: 'x1', repository: repo, storeId: 'st1'),
        tag: 'x1',
      );
      await show(t, ExpenseDetailView(expenseId: 'x1', controller: d));
      await shot(t, 'g35_11_expense_detail_rejected_cashier', tn);
    });

    testWidgets('G3.5 daybook ($tn)', (t) async {
      DaybookController book(_Repo repo) => Get.put(DaybookController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15), storeName: () async => 'Dev Store'));
      var repo = fresh();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => daybook());
      await show(t, DaybookView(controller: book(repo)));
      await shot(t, 'g35_12_daybook_reconciled', tn);
      await t.drag(find.byKey(const Key('daybookList')), const Offset(0, -900));
      await shot(t, 'g35_12b_daybook_totals_and_actions', tn);

      repo = fresh();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer(
        (_) async => daybook(
          shifts: [
            shift(reconciled: false, unreconciled: -300),
            shift(id: 'se2', employee: 'Ali', closed: false),
          ],
        ),
      );
      await show(t, DaybookView(controller: book(repo)));
      await shot(t, 'g35_13_daybook_does_not_reconcile', tn);

      repo = fresh();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => daybook(own: true));
      await show(t, DaybookView(controller: book(repo)));
      await shot(t, 'g35_14_daybook_cashier_own_shifts', tn);

      repo = fresh();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => daybook(shifts: const []));
      await show(t, DaybookView(controller: book(repo)));
      await shot(t, 'g35_15_daybook_empty_day', tn);

      repo = fresh();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => null);
      await show(t, _Offline(child: DaybookView(controller: book(repo))));
      await shot(t, 'g35_16_daybook_offline_needs_internet', tn);
    });

    testWidgets('G3.5 needs attention ($tn)', (t) async {
      final repo = fresh();
      final q = _Queue()
        ..setRows([
          _rec('w1', attempts: 2),
          _rec('f1', status: 'failed', code: 'NO_OPEN_SHIFT', message: 'There is no open shift on this till. Open a shift first.'),
          _rec(
            'f2',
            status: 'failed',
            code: 'POS_OWNER_REQUIRED',
            message: 'This amount is above the manager limit. The store owner must do this.',
            amount: 250000,
            type: 'cash_in',
            category: 'owner_injection',
          ),
          _rec('p1', kind: 'receipt'),
        ]);
      final sync = _Sync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => repo.getSalesNeedingReview(any())).thenAnswer((_) async => []);
      final c = PosNeedsAttentionController(syncService: sync, posRepository: repo, paymentsRepository: FakePaymentsRepo(), cashQueue: q);
      Get.put<PosNeedsAttentionController>(c);
      await show(t, PosNeedsAttentionView(controller: c));
      c.isManager.value = true;
      await t.pump();
      await shot(t, 'g35_17_needs_attention_cash_entries', tn);
    });
  }
}
