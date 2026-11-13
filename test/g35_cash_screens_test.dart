// G3.5 screens on phone, tablet and dark: every state (loading, empty, error, needs-internet / offline), the role-limited cashier views, reconciled vs not
// reconciled, the offline queue's "Waiting to sync" and Needs-attention entries, and the success flows against mocked repositories.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
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
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/fake_payments.dart';
import 'support/g35_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

/// A queue that records what it is handed and shows the rows it is given (nothing touches a database or the network).
class _FakeCashQueue extends PendingCashSyncService {
  _FakeCashQueue()
    : super(
        posRepository: _Repo(),
        localStore: PendingCashLocalStore(dbPath: 'unused.db'),
      );
  final retried = <String>[];
  final dismissed = <String>[];
  Map<Symbol, dynamic> last = {};
  int syncs = 0;

  void setRows(List<PendingCashRecord> rows) {
    items.assignAll(rows);
    pendingCount.value = rows.where((r) => r.isPending).length;
    failedCount.value = rows.where((r) => r.isFailed).length;
    unresolvedCount.value = pendingCount.value + failedCount.value;
  }

  @override
  Future<void> refreshCounts() async {}
  @override
  Future<void> syncNow({bool ignoreBackoff = false}) async => syncs++;
  @override
  Future<void> retry(String id) async => retried.add(id);
  @override
  Future<void> dismiss(String id) async => dismissed.add(id);
  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) => syncs++;
  @override
  Future<String> keepPhoto(File source) async => source.path;
  @override
  Future<PendingCashRecord> enqueueMovement({
    required String storeId,
    required String requestId,
    required String type,
    required String category,
    required int amountMinor,
    required String sessionId,
    required String currency,
    required int currencyExponent,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
  }) async {
    last = {#requestId: requestId, #amountMinor: amountMinor};
    return rec(requestId);
  }

  @override
  Future<PendingCashRecord> enqueueExpense({
    required String storeId,
    required String requestId,
    required String category,
    required int amountMinor,
    required String sessionId,
    required String currency,
    required int currencyExponent,
    String? payee,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
  }) async {
    last = {#requestId: requestId, #amountMinor: amountMinor};
    return rec(requestId);
  }

  @override
  Future<PendingCashRecord> enqueueReceipt({required String storeId, required String path, String? expenseRequestId, String? expenseId, String? employeeToken}) async => rec('rcpt');
}

PendingCashRecord rec(String id, {String status = 'pending', String kind = 'movement', String? code, String? message, int amount = 1500, String session = 'se1', int attempts = 0}) =>
    PendingCashRecord(
      seq: 1,
      id: id,
      kind: kind,
      payload: {'type': 'cash_out', 'category': 'bank_deposit', 'amountMinor': amount, 'currency': 'USD', 'currencyExponent': 2, 'occurredAt': '2026-11-09T09:00:00.000Z'},
      status: status,
      createdAt: DateTime(2026, 11, 9, 9),
      storeId: 'st1',
      sessionId: session,
      errorCode: code,
      errorMessage: message,
      attempts: attempts,
    );

class _MockSync extends Mock implements PendingSaleSyncService {}

const _phone = Size(390, 1500);
const _tablet = Size(834, 1194);

enum _Env { phone, tablet, dark }

void main() {
  late _Repo repo;
  late CashConfigCache cache;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(File('x'));
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    Money.configure(currency: 'USD', exponent: 2);
    repo = _Repo();
    cache = CashConfigCache();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getCashConfig('st1')).thenAnswer((_) async => cashConfig());
  });

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(
              name: Routes.posSaleDetail,
              page: () => Scaffold(body: Text('SALE:${Get.arguments}')),
            ),
          ],
          home: w,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.enterText(find.descendant(of: f, matching: find.byType(TextField)), text);
    await t.pump();
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
  bool hasNoMoney(WidgetTester t) => find.textContaining(RegExp(r'\$\s?\d')).evaluate().isEmpty;

  // ── cash home ──────────────────────────────────────────────────────────────────────────────────
  group('CashHomeView', () {
    for (final env in _Env.values) {
      testWidgets('${env.name}: cash in, cash out, expenses and the daybook', (t) async {
        await pump(t, const CashHomeView(), env);
        for (final k in ['cashIn', 'cashOut', 'cashExpenses', 'cashDaybook']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('queued offline entries show "Waiting to sync" and the refused ones link to Needs attention', (t) async {
      final q = _FakeCashQueue()..setRows([rec('a'), rec('b'), rec('c', status: 'failed', code: 'NO_OPEN_SHIFT')]);
      Get.put<PendingCashSyncService>(q);
      await pump(t, const CashHomeView());
      expect(find.text('Waiting to sync · 2'), findsOneWidget);
      expect(find.byKey(const Key('cashNeedsAttention')), findsOneWidget);
      expect(find.text('1 need attention'), findsOneWidget);
    });

    testWidgets('nothing queued: no badge', (t) async {
      Get.put<PendingCashSyncService>(_FakeCashQueue());
      await pump(t, const CashHomeView());
      expect(find.textContaining('Waiting to sync'), findsNothing);
    });
  });

  // ── cash movement sheet ────────────────────────────────────────────────────────────────────────
  group('CashMovementSheet', () {
    CashMovementController make({String type = 'cash_in', String? session = 'se1', String Function()? ids, Future<String?> Function(String)? approval, PendingCashSyncService? queue}) =>
        CashMovementController(
          initialType: type,
          repository: repo,
          cache: cache,
          queue: queue,
          storeId: 'st1',
          sessionIdProvider: () async => session,
          employeeTokenProvider: () async => 'tok',
          approval: approval == null ? null : ({required String reason, repository}) => approval(reason),
          requestIdFactory: ids ?? () => 'req-1',
          clock: () => DateTime.utc(2026, 11, 9, 8),
        );
    Future<CashMovementController> mount(WidgetTester t, CashMovementController c, [_Env env = _Env.phone]) async {
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: CashMovementSheet(controller: c)),
        ),
        env,
      );
      return c;
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: reasons, amount in the store currency, note; Record needs a reason and an amount', (t) async {
        final c = await mount(t, make(), env);
        for (final k in ['cmCat_float_topup', 'cmCat_owner_injection', 'cmCat_other_in']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('Amount (USD)'), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNull);
        await tapKey(t, 'cmCat_float_topup');
        await typeKey(t, 'cmAmount', '12.5');
        expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNotNull);
        expect(c.amountMinor, 1250);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('cash out shows the cash-out reasons; "other" makes the note required', (t) async {
      await mount(t, make());
      await tapKey(t, 'cmOut');
      for (final k in ['cmCat_bank_deposit', 'cmCat_safe_drop', 'cmCat_petty', 'cmCat_owner_draw', 'cmCat_other_out']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      await tapKey(t, 'cmCat_other_out');
      await typeKey(t, 'cmAmount', '5');
      expect(find.text('Note (required)'), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNull);
      await typeKey(t, 'cmNote', 'delivery float');
      expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNotNull);
    });

    testWidgets('no open shift: says so and cannot record', (t) async {
      await mount(t, make(session: null));
      expect(find.byKey(const Key('cmNoShift')), findsOneWidget);
      expect(find.text('Open a shift to record cash in or out.'), findsOneWidget);
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '5');
      expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNull);
    });

    testWidgets('success: sends the minor amount with the request id, outcome booked', (t) async {
      final c = await mount(t, make());
      Map<Symbol, dynamic>? sent;
      when(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        sent = i.namedArguments;
        return (success: true, message: null, code: null, retryable: false, result: movementResult());
      });
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '12.5');
      await tapKey(t, 'cmConfirm');
      expect(sent![#amountMinor], 1250);
      expect(sent![#requestId], 'req-1');
      expect(c.outcome.value, CashOutcome.booked);
    });

    testWidgets('over the limit: the manager approval is asked and the same request repeats with the token', (t) async {
      final c = await mount(t, make(approval: (_) async => 'tok-mgr'));
      final tokens = <String?>[];
      when(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        tokens.add(i.namedArguments[#approverToken] as String?);
        return tokens.length == 1
            ? (success: false, message: 'x', code: 'POS_APPROVAL_REQUIRED', retryable: false, result: null)
            : (success: true, message: null, code: null, retryable: false, result: movementResult());
      });
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '500');
      await tapKey(t, 'cmConfirm');
      expect(tokens, [null, 'tok-mgr']);
      expect(c.outcome.value, CashOutcome.booked);
    });

    testWidgets('a server refusal stays on the sheet in plain words (NO_OPEN_SHIFT: the shift was closed elsewhere)', (t) async {
      await mount(t, make());
      when(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'NO_OPEN_SHIFT', retryable: false, result: null));
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '5');
      await tapKey(t, 'cmConfirm');
      expect(find.byKey(const Key('cmError')), findsOneWidget);
      expect(find.text('There is no open shift on this till. Open a shift first.'), findsOneWidget);
    });

    testWidgets('offline with a remembered currency: allowed, labelled "Save on this device", and it is queued', (t) async {
      await cache.save('st1', cashConfig());
      offline();
      final q = _FakeCashQueue();
      final c = await mount(t, make(queue: q));
      expect(find.byKey(const Key('cmOffline')), findsOneWidget);
      expect(find.text('Save on this device'), findsOneWidget);
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '12.5');
      await tapKey(t, 'cmConfirm');
      expect(c.outcome.value, CashOutcome.queued);
      expect(q.last[#amountMinor], 1250);
      verifyNever(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      );
    });

    testWidgets('this shift\'s movements waiting to sync are counted on the sheet', (t) async {
      final q = _FakeCashQueue()..setRows([rec('a'), rec('b', session: 'other-shift')]);
      await mount(t, make(queue: q));
      expect(find.text('Waiting to sync · 1'), findsOneWidget);
    });

    testWidgets('offline and never online: no currency to type in, said plainly', (t) async {
      offline();
      await mount(t, make());
      expect(find.byKey(const Key('cmNoCurrency')), findsOneWidget);
      await tapKey(t, 'cmCat_float_topup');
      await typeKey(t, 'cmAmount', '5');
      expect(t.widget<AppButton>(find.byKey(const Key('cmConfirm'))).onPressed, isNull);
    });
  });

  // ── expense form ───────────────────────────────────────────────────────────────────────────────
  group('ExpenseFormSheet', () {
    ExpenseFormController make({String? session = 'se1', PendingCashSyncService? queue}) => ExpenseFormController(
      repository: repo,
      cache: cache,
      queue: queue,
      storeId: 'st1',
      sessionIdProvider: () async => session,
      employeeTokenProvider: () async => 'tok',
      requestIdFactory: () => 'ex-1',
      clock: () => DateTime.utc(2026, 11, 9, 8),
    );
    Future<ExpenseFormController> mount(WidgetTester t, ExpenseFormController c, {_Env env = _Env.phone, void Function(ValueChanged<File>)? pick}) async {
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: ExpenseFormSheet(controller: c, pickPhoto: pick),
          ),
        ),
        env,
      );
      return c;
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: categories, methods, amount, payee, note and a receipt photo button', (t) async {
        await mount(t, make(), env: env);
        for (final k in ['exCat_rent', 'exCat_utilities', 'exCat_other', 'exMethod_cash', 'exMethod_bank', 'exMethod_other', 'exAmount', 'exPayee', 'exNote', 'exPhoto']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(t.widget<AppButton>(find.byKey(const Key('exConfirm'))).onPressed, isNull);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('saving a drawer expense with a photo: the expense is sent in minor units, then the photo is uploaded', (t) async {
      final c = await mount(t, make(), pick: (cb) => cb(File('/tmp/r.jpg')));
      Map<Symbol, dynamic>? sent;
      when(
        () => repo.recordExpense(
          any(),
          category: any(named: 'category'),
          method: any(named: 'method'),
          amountMinor: any(named: 'amountMinor'),
          requestId: any(named: 'requestId'),
          sessionId: any(named: 'sessionId'),
          payee: any(named: 'payee'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        sent = i.namedArguments;
        return (success: true, message: null, code: null, retryable: false, result: expenseSaved());
      });
      when(() => repo.uploadExpenseReceipt('st1', 'x1', any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((_) async => (success: true, message: null, code: null, retryable: false));
      await tapKey(t, 'exCat_rent');
      await typeKey(t, 'exAmount', '120');
      await typeKey(t, 'exPayee', 'Landlord');
      await tapKey(t, 'exPhoto');
      expect(find.byKey(const Key('exPhotoThumb')), findsOneWidget);
      await tapKey(t, 'exConfirm');
      expect(sent![#amountMinor], 12000);
      expect(sent![#method], 'cash');
      expect(sent![#payee], 'Landlord');
      expect(c.outcome.value, CashOutcome.booked);
      expect(c.photoNotice.value, 'Receipt photo saved.');
      verify(() => repo.uploadExpenseReceipt('st1', 'x1', any(), employeeToken: any(named: 'employeeToken'))).called(1);
    });

    testWidgets('the photo can be removed again', (t) async {
      final c = await mount(t, make(), pick: (cb) => cb(File('/tmp/r.jpg')));
      await tapKey(t, 'exPhoto');
      expect(c.photo.value, isNotNull);
      await tapKey(t, 'exPhotoRemove');
      expect(c.photo.value, isNull);
      expect(find.byKey(const Key('exPhotoThumb')), findsNothing);
    });

    testWidgets('"other" needs a note; with no open shift the drawer is not offered', (t) async {
      final c = await mount(t, make(session: null));
      expect(find.byKey(const Key('exNoShift')), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('exMethod_cash'))).onSelected, isNull);
      await tapKey(t, 'exCat_other');
      await typeKey(t, 'exAmount', '5');
      expect(find.text('Note (required)'), findsOneWidget);
      expect(c.canSubmit, isFalse);
      await typeKey(t, 'exNote', 'misc');
      expect(c.canSubmit, isTrue);
    });

    testWidgets('a server error stays on the sheet', (t) async {
      await mount(t, make());
      when(
        () => repo.recordExpense(
          any(),
          category: any(named: 'category'),
          method: any(named: 'method'),
          amountMinor: any(named: 'amountMinor'),
          requestId: any(named: 'requestId'),
          sessionId: any(named: 'sessionId'),
          payee: any(named: 'payee'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED', retryable: false, result: null));
      await tapKey(t, 'exCat_rent');
      await typeKey(t, 'exAmount', '5000');
      await tapKey(t, 'exConfirm');
      expect(find.byKey(const Key('exError')), findsOneWidget);
      expect(find.textContaining('store owner must do this'), findsOneWidget);
    });

    testWidgets('offline: a drawer expense is queued ("Save on this device"); bank and other cannot be chosen', (t) async {
      await cache.save('st1', cashConfig());
      offline();
      final q = _FakeCashQueue();
      final c = await mount(t, make(queue: q));
      expect(find.byKey(const Key('exOffline')), findsOneWidget);
      expect(find.text('Save on this device'), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('exMethod_bank'))).onSelected, isNull);
      await tapKey(t, 'exCat_supplies');
      await typeKey(t, 'exAmount', '40');
      await tapKey(t, 'exConfirm');
      expect(c.outcome.value, CashOutcome.queued);
      expect(q.last[#amountMinor], 4000);
      expect(q.last[#requestId], 'ex-1');
    });
  });

  // ── expense list ───────────────────────────────────────────────────────────────────────────────
  group('ExpenseListView', () {
    ExpenseListController put() => Get.put(ExpenseListController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15)));
    void stubList(ExpenseList l) => when(
      () => repo.getExpenses(
        'st1',
        status: any(named: 'status'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => l);

    for (final env in _Env.values) {
      testWidgets('${env.name}: period and status chips, totals per category, rows with status badges', (t) async {
        stubList(expenseList([expense(), expense(id: 'x2', status: 'approved', category: 'meals', amountMinor: 800), expense(id: 'x3', status: 'rejected', category: 'repairs', amountMinor: 999)]));
        await pump(t, ExpenseListView(controller: put()), env);
        for (final k in ['expensePeriod_today', 'expensePeriod_week', 'expensePeriod_month', 'expenseStatus_all', 'expenseStatus_recorded', 'expenseStatus_approved', 'expenseStatus_rejected']) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.byKey(const Key('expenseTotals')), findsOneWidget);
        expect(find.byKey(const Key('expenseCat_rent')), findsOneWidget);
        expect(find.byKey(const Key('expenseCat_repairs')), findsNothing, reason: 'rejected is not counted');
        expect(find.text(r'$128.00'), findsOneWidget);
        expect(find.text('Approved'), findsWidgets);
        expect(find.text('Rejected'), findsWidgets);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a chip reloads with that status and period', (t) async {
      stubList(expenseList([expense()]));
      await pump(t, ExpenseListView(controller: put()));
      await tapKey(t, 'expenseStatus_approved');
      verify(() => repo.getExpenses('st1', status: 'approved', from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 10))).called(1);
      await tapKey(t, 'expensePeriod_today');
      verify(() => repo.getExpenses('st1', status: 'approved', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10))).called(1);
    });

    testWidgets('a row without a stated currency shows no amount', (t) async {
      stubList(
        ExpenseList(
          expenses: [
            Expense.fromJson({...expenseJson(), 'currency': null, 'currencyExponent': null}),
          ],
        ),
      );
      await pump(t, ExpenseListView(controller: put()));
      expect(find.byKey(const Key('expense_x1')), findsOneWidget);
      expect(find.byKey(const Key('expenseAmount_x1')), findsNothing);
      expect(find.byKey(const Key('expenseTotals')), findsNothing);
    });

    testWidgets('loading / empty / error / offline', (t) async {
      final comp = Completer<ExpenseList?>();
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) => comp.future);
      await pump(t, ExpenseListView(controller: put()));
      expect(find.byKey(const Key('cashLoading')), findsOneWidget);
      comp.complete(expenseList([]));
      await t.pump();
      await t.pump();
      expect(find.text('No expenses'), findsOneWidget);
    });

    testWidgets('error shows the server message with Try again', (t) async {
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      await pump(t, ExpenseListView(controller: put()));
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline: Needs internet, no request, but adding a drawer expense is still offered', (t) async {
      offline();
      await pump(t, ExpenseListView(controller: put()));
      expect(find.byKey(const Key('cashNeedsInternet')), findsOneWidget);
      expect(find.byKey(const Key('expenseAdd')), findsOneWidget);
      verifyNever(
        () => repo.getExpenses(
          any(),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    });
  });

  // ── expense detail ─────────────────────────────────────────────────────────────────────────────
  group('ExpenseDetailView', () {
    ExpenseDetailController put(Expense e, {bool manager = false}) {
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) async => e);
      final c = Get.put(
        ExpenseDetailController(expenseId: 'x1', repository: repo, storeId: 'st1'),
        tag: 'x1',
      );
      if (manager) c.canManageHint.value = true;
      return c;
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: manager sees the details, the receipt button and Approve / Reject', (t) async {
        final c = put(expense(hasReceipt: true), manager: true);
        await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c), env);
        await t.pump(const Duration(milliseconds: 100));
        c.canManageHint.value = true;
        await t.pump();
        expect(find.text('Rent'), findsWidgets);
        expect(find.byKey(const Key('expenseDetailAmount')), findsOneWidget);
        expect(find.text('EXP-000001'), findsOneWidget);
        expect(find.text('Landlord'), findsOneWidget);
        expect(find.byKey(const Key('viewReceipt')), findsOneWidget);
        expect(find.byKey(const Key('expenseApprove')), findsOneWidget);
        expect(find.byKey(const Key('expenseReject')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a cashier sees the expense and its receipt but no Approve / Reject', (t) async {
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense(hasReceipt: true))));
      expect(find.byKey(const Key('viewReceipt')), findsOneWidget);
      expect(find.byKey(const Key('expenseApprove')), findsNothing);
      expect(find.byKey(const Key('expenseReject')), findsNothing);
    });

    testWidgets('a decided expense shows its status and the decision note, and offers no decision', (t) async {
      await pump(
        t,
        ExpenseDetailView(
          expenseId: 'x1',
          controller: put(expense(status: 'rejected', decisionNote: 'duplicate of EXP-3'), manager: true),
        ),
      );
      expect(find.text('Rejected'), findsWidgets);
      expect(find.text('Rejected because'), findsOneWidget);
      expect(find.text('duplicate of EXP-3'), findsOneWidget);
      expect(find.byKey(const Key('expenseApprove')), findsNothing);
    });

    testWidgets('the receipt type is known from the expense: a PDF gets "View PDF receipt" with NO link request yet; an image gets the button', (t) async {
      await pump(
        t,
        ExpenseDetailView(
          expenseId: 'x1',
          controller: put(expense(hasReceipt: true, receiptMime: 'application/pdf')),
        ),
      );
      expect(find.byKey(const Key('viewReceiptPdf')), findsOneWidget);
      expect(find.byKey(const Key('viewReceipt')), findsNothing);
      verifyNever(() => repo.getExpenseReceiptLink(any(), any()));
      Get.reset();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense(hasReceipt: true))));
      expect(find.byKey(const Key('viewReceipt')), findsOneWidget);
      expect(find.byKey(const Key('viewReceiptPdf')), findsNothing);
    });

    testWidgets('who recorded the expense is shown on the row and on the detail', (t) async {
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => expenseList([expense()]));
      await pump(
        t,
        ExpenseListView(
          controller: Get.put(ExpenseListController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15))),
        ),
      );
      expect(find.textContaining('by Sam'), findsOneWidget);
      Get.reset();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense())));
      expect(find.text('Recorded by'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('no receipt: says so; with a receipt, "View receipt" fetches a fresh link every time and "Hide" drops it', (t) async {
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense())));
      expect(find.byKey(const Key('noReceipt')), findsOneWidget);
      Get.reset();
      var n = 0;
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => ReceiptLink(url: 'https://signed.example/${++n}', mimeType: 'application/pdf'));
      final c = put(expense(hasReceipt: true));
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      await tapKey(t, 'viewReceipt');
      expect(find.byKey(const Key('viewReceiptPdf')), findsOneWidget);
      expect(find.byKey(const Key('hideReceipt')), findsOneWidget);
      await tapKey(t, 'hideReceipt');
      expect(find.byKey(const Key('viewReceiptPdf')), findsNothing);
      await tapKey(t, 'viewReceipt');
      verify(() => repo.getExpenseReceiptLink('st1', 'x1')).called(2);
      expect(c.receipt.value!.url, endsWith('/2'));
    });

    testWidgets('an image receipt is shown from the link (and the link is not on screen)', (t) async {
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => const ReceiptLink(url: 'https://signed.example/img?sig=SECRET', mimeType: 'image/png'));
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense(hasReceipt: true))));
      await tapKey(t, 'viewReceipt');
      expect(find.byKey(const Key('receiptImage')), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
    });

    testWidgets('receipt problems are explained (no receipt / offline link)', (t) async {
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('NO_RECEIPT');
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense(hasReceipt: true))));
      await tapKey(t, 'viewReceipt');
      expect(find.text('This expense has no receipt photo.'), findsOneWidget);
    });

    testWidgets('Approve updates the status; Reject asks for a reason first and sends it', (t) async {
      final c = put(expense());
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      c.canManageHint.value = true;
      await t.pump();
      when(
        () => repo.decideExpense('st1', 'x1', approve: false, note: 'no receipt'),
      ).thenAnswer((_) async => (success: true, message: null, code: null, expense: expense(status: 'rejected', decisionNote: 'no receipt')));
      await tapKey(t, 'expenseReject');
      expect(find.byKey(const Key('rejectReason')), findsOneWidget);
      await t.tap(find.byKey(const Key('rejectConfirm')));
      await t.pump();
      verifyNever(
        () => repo.decideExpense(
          any(),
          any(),
          approve: any(named: 'approve'),
          note: any(named: 'note'),
        ),
      );
      await t.enterText(find.byKey(const Key('rejectReason')), 'no receipt');
      await t.tap(find.byKey(const Key('rejectConfirm')));
      await t.pumpAndSettle();
      verify(() => repo.decideExpense('st1', 'x1', approve: false, note: 'no receipt')).called(1);
      expect(find.byKey(const Key('expenseNotice')), findsOneWidget);
      expect(find.byKey(const Key('expenseApprove')), findsNothing);
    });

    testWidgets('a decision refused by the server is shown in words', (t) async {
      final c = put(expense());
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: c));
      c.canManageHint.value = true;
      await t.pump();
      when(() => repo.decideExpense('st1', 'x1', approve: true, note: null)).thenAnswer((_) async => (success: false, message: 'x', code: 'ALREADY_DECIDED', expense: null));
      await tapKey(t, 'expenseApprove');
      expect(find.byKey(const Key('expenseActionError')), findsOneWidget);
      expect(find.text('This expense was already approved or rejected.'), findsOneWidget);
    });

    testWidgets('loading / error / offline', (t) async {
      final comp = Completer<Expense?>();
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) => comp.future);
      await pump(
        t,
        ExpenseDetailView(
          expenseId: 'x1',
          controller: Get.put(
            ExpenseDetailController(expenseId: 'x1', repository: repo, storeId: 'st1'),
            tag: 'x1',
          ),
        ),
      );
      expect(find.byKey(const Key('cashLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('EXPENSE_NOT_FOUND');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('That expense was not found.'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, ExpenseDetailView(expenseId: 'x1', controller: put(expense())));
      expect(find.byKey(const Key('cashNeedsInternet')), findsOneWidget);
    });
  });

  // ── daybook ────────────────────────────────────────────────────────────────────────────────────
  group('DaybookView', () {
    DaybookController put({Future<void> Function(ShareParams)? share}) =>
        Get.put(DaybookController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15), share: share, storeName: () async => 'Dev Store'));
    void stubBook(Daybook d) => when(
      () => repo.getDaybookDay('st1', date: any(named: 'date')),
    ).thenAnswer((_) async => d);

    for (final env in _Env.values) {
      testWidgets('${env.name}: day picker, the shift with every line and its running balance, the summary, the totals and Print / Share', (t) async {
        stubBook(daybook());
        await pump(t, DaybookView(controller: put()), env);
        expect(find.text('Today · Mon 9 Nov 2026'), findsOneWidget);
        expect(find.byKey(const Key('shift_se1')), findsOneWidget);
        expect(find.text('Main till'), findsOneWidget);
        expect(find.text('Closed'), findsOneWidget);
        expect(find.text('Opening float'), findsOneWidget);
        expect(find.text('Sale S-0001'), findsOneWidget);
        expect(find.text(r'Balance $100.00'), findsOneWidget);
        expect(find.text(r'Balance $125.00'), findsOneWidget);
        expect(find.text(r'Balance $107.00'), findsWidgets);
        expect(find.text('Expected cash'), findsOneWidget);
        expect(find.text('Counted at close'), findsOneWidget);
        expect(find.text('Variance'), findsWidgets);
        expect(find.byKey(const Key('daybookTotals')), findsOneWidget);
        expect(find.byKey(const Key('daybookPrint')), findsOneWidget);
        expect(find.byKey(const Key('daybookShare')), findsOneWidget);
        expect(find.byKey(const Key('daybookUnreconciledTop')), findsNothing, reason: 'reconciled: no warning');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('does not reconcile: a warning on the day and on the shift with the difference', (t) async {
      stubBook(daybook(shifts: [shift(reconciled: false, unreconciled: -300)]));
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('daybookUnreconciledTop')), findsOneWidget);
      expect(find.byKey(const Key('daybookUnreconciled_se1')), findsOneWidget);
      expect(find.textContaining('Does not reconcile'), findsWidgets);
      expect(find.textContaining(r'−$3.00'), findsWidgets);
    });

    testWidgets('a cashier is told it is their own shifts only', (t) async {
      stubBook(daybook(own: true));
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('daybookOwnOnly')), findsOneWidget);
    });

    testWidgets('a sale line opens the existing sale detail with the sale id; an expense and a cash movement are not tappable', (t) async {
      stubBook(daybook());
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('daybookLine_sale1')), findsOneWidget);
      expect(find.byKey(const Key('daybookLine_x1')), findsNothing);
      expect(find.byKey(const Key('daybookLine_req1')), findsNothing);
      await tapKey(t, 'daybookLine_sale1');
      expect(find.text('SALE:sale1'), findsOneWidget);
    });

    testWidgets('a refund line opens the SALE it belongs to (its saleId, not the refund id); a refund with no saleId is not tappable', (t) async {
      stubBook(
        daybook(
          shifts: [
            shift(
              lines: [
                DaybookLine(type: 'cash_refund', label: 'Refund R-1', amountMinor: -500, runningMinor: 9500, at: DateTime(2026, 11, 9, 10), refType: 'refund', refId: 'rf1', saleId: 'sale-of-rf1'),
                DaybookLine(type: 'cash_refund', label: 'Refund R-2', amountMinor: -100, runningMinor: 9400, at: DateTime(2026, 11, 9, 11), refType: 'refund', refId: 'rf2'),
              ],
            ),
          ],
        ),
      );
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('daybookLine_rf1')), findsOneWidget);
      expect(find.byKey(const Key('daybookLine_rf2')), findsNothing);
      await tapKey(t, 'daybookLine_rf1');
      expect(find.text('SALE:sale-of-rf1'), findsOneWidget);
    });

    testWidgets('each daybook line names the employee who made it', (t) async {
      stubBook(daybook());
      await pump(t, DaybookView(controller: put()));
      expect(find.text('09:30 · Sam'), findsOneWidget);
      expect(find.text('13:00 · Ali'), findsOneWidget);
    });

    testWidgets('a voided sale (refType void, the sale id) also opens the sale', (t) async {
      stubBook(
        daybook(
          shifts: [
            shift(
              lines: [
                DaybookLine(type: 'opening', label: 'Opening float', amountMinor: 10000, runningMinor: 10000, at: DateTime(2026, 11, 9, 9), refType: 'session', refId: 'se1'),
                DaybookLine(type: 'cash_refund', label: 'Void S-0002', amountMinor: -700, runningMinor: 9300, at: DateTime(2026, 11, 9, 10), refType: 'void', refId: 'sale2'),
              ],
            ),
          ],
        ),
      );
      await pump(t, DaybookView(controller: put()));
      await tapKey(t, 'daybookLine_sale2');
      expect(find.text('SALE:sale2'), findsOneWidget);
    });

    testWidgets('the day arrows: previous loads yesterday, next is disabled on today', (t) async {
      stubBook(daybook());
      await pump(t, DaybookView(controller: put()));
      expect(t.widget<IconButton>(find.byKey(const Key('daybookNext'))).onPressed, isNull);
      await tapKey(t, 'daybookPrev');
      verify(() => repo.getDaybookDay('st1', date: '2026-11-08')).called(1);
      expect(find.text('Sun 8 Nov 2026'), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('daybookNext'))).onPressed, isNotNull);
    });

    testWidgets('Share PDF hands a PDF to the share sheet; Print without a printer says so', (t) async {
      stubBook(daybook());
      ShareParams? shared;
      await pump(t, DaybookView(controller: put(share: (p) async => shared = p)));
      await tapKey(t, 'daybookShare');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await t.pump();
      expect(shared?.files?.single.mimeType, 'application/pdf');
      await tapKey(t, 'daybookPrint');
      expect(find.byKey(const Key('daybookPrintNotice')), findsOneWidget);
      expect(find.textContaining('No printer is set up'), findsOneWidget);
    });

    testWidgets('no shifts that day', (t) async {
      stubBook(daybook(shifts: const []));
      await pump(t, DaybookView(controller: put()));
      expect(find.text('No shifts'), findsOneWidget);
      expect(find.byKey(const Key('daybookPrint')), findsNothing);
    });

    testWidgets('a response with no currency shows no money', (t) async {
      stubBook(daybook(cur: null));
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('shift_se1')), findsOneWidget);
      expect(hasNoMoney(t), isTrue);
    });

    testWidgets('loading / error / offline', (t) async {
      final comp = Completer<Daybook?>();
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) => comp.future);
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('cashLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
    });

    testWidgets('offline: Needs internet and no request', (t) async {
      offline();
      await pump(t, DaybookView(controller: put()));
      expect(find.byKey(const Key('cashNeedsInternet')), findsOneWidget);
      verifyNever(
        () => repo.getDaybookDay(any(), date: any(named: 'date')),
      );
    });
  });

  // ── needs attention ────────────────────────────────────────────────────────────────────────────
  group('Needs attention: cash entries', () {
    Future<(_FakeCashQueue, PosNeedsAttentionController)> mount(WidgetTester t, List<PendingCashRecord> rows, {bool manager = false}) async {
      final q = _FakeCashQueue()..setRows(rows);
      final sync = _MockSync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => repo.getSalesNeedingReview(any())).thenAnswer((_) async => []);
      final c = PosNeedsAttentionController(syncService: sync, posRepository: repo, paymentsRepository: FakePaymentsRepo(), cashQueue: q);
      Get.put<PosNeedsAttentionController>(c);
      await pump(t, PosNeedsAttentionView(controller: c));
      c.isManager.value = manager;
      await t.pump();
      return (q, c);
    }

    testWidgets('a waiting entry and a refused one: the refused one says why and offers Retry / Dismiss (manager)', (t) async {
      final (q, _) = await mount(t, [rec('w1', attempts: 2), rec('f1', status: 'failed', code: 'NO_OPEN_SHIFT', message: 'There is no open shift on this till. Open a shift first.')], manager: true);
      expect(find.text('Cash & expenses not yet on the server'), findsOneWidget);
      expect(find.textContaining('Cash out · Bank deposit'), findsNWidgets(2));
      expect(find.textContaining(r'$15.00'), findsNWidgets(2));
      expect(find.text('Waiting to retry (attempt 2)'), findsOneWidget);
      expect(find.text('Refused by the server — needs a decision'), findsOneWidget);
      expect(find.text('There is no open shift on this till. Open a shift first.'), findsOneWidget);
      expect(find.byKey(const Key('cashRetry_w1')), findsNothing, reason: 'a waiting one retries by itself');
      await t.tap(find.byKey(const Key('cashRetry_f1')));
      await t.pump();
      expect(q.retried, ['f1']);
    });

    testWidgets('Dismiss is a manager decision and asks first; a cashier gets a disabled "Dismiss (manager)"', (t) async {
      final (q, c) = await mount(t, [rec('f1', status: 'failed', code: 'POS_OWNER_REQUIRED', message: 'owner')], manager: true);
      await t.tap(find.byKey(const Key('cashDismiss_f1')));
      await t.pumpAndSettle();
      expect(find.text('Dismiss this entry?'), findsOneWidget);
      await t.tap(find.text('Dismiss').last);
      await t.pumpAndSettle();
      expect(q.dismissed, ['f1']);
      expect(c.isManager.value, isTrue);
    });

    testWidgets('a cashier cannot dismiss', (t) async {
      final (q, _) = await mount(t, [rec('f1', status: 'failed', code: 'NO_OPEN_SHIFT', message: 'x')]);
      expect(t.widget<OutlinedButton>(find.byKey(const Key('cashDismiss_f1'))).onPressed, isNull);
      expect(find.text('Dismiss (manager)'), findsOneWidget);
      expect(q.dismissed, isEmpty);
    });

    testWidgets('a receipt photo is listed without an amount', (t) async {
      await mount(t, [rec('p1', kind: 'receipt')]);
      expect(find.text('Receipt photo'), findsOneWidget);
    });

    testWidgets('nothing queued: "Everything is synced"', (t) async {
      await mount(t, []);
      expect(find.text('Everything is synced. Nothing needs attention.'), findsOneWidget);
    });
  });
}
