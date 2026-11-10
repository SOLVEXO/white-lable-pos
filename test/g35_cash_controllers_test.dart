// G3.5 controllers against a mocked PosRepository: request building at exponent 0 / 2 / 3, requestId stable on retry, the approval flow, the offline queue
// hand-off, the open shift, notes for "other", expenses with photos, the list / detail / daybook states.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/daybook_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_list_controller.dart';

import 'support/g35_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

/// A hand-written queue: records what was handed to it (the controller only enqueues, keeps the photo and asks for a sync).
class _Queue extends Fake implements PendingCashSyncService {
  Map<Symbol, dynamic> last = {};
  Map<Symbol, dynamic> lastReceipt = {};
  int syncs = 0;

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
    last = {
      #storeId: storeId,
      #requestId: requestId,
      #type: type,
      #category: category,
      #amountMinor: amountMinor,
      #sessionId: sessionId,
      #currency: currency,
      #currencyExponent: currencyExponent,
      #note: note,
      #occurredAt: occurredAt,
      #employeeToken: employeeToken,
    };
    return _rec();
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
    last = {
      #storeId: storeId,
      #requestId: requestId,
      #category: category,
      #amountMinor: amountMinor,
      #sessionId: sessionId,
      #currency: currency,
      #currencyExponent: currencyExponent,
      #payee: payee,
      #note: note,
      #occurredAt: occurredAt,
      #employeeToken: employeeToken,
    };
    return _rec();
  }

  @override
  Future<PendingCashRecord> enqueueReceipt({required String storeId, required String path, String? expenseRequestId, String? expenseId, String? employeeToken}) async {
    lastReceipt = {#storeId: storeId, #path: path, #expenseRequestId: expenseRequestId, #expenseId: expenseId};
    return _rec();
  }

  @override
  Future<String> keepPhoto(File source) async => source.path;

  @override
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) => syncs++;
}

class _Printer extends Mock implements ThermalPrinterService {}

typedef MoveRes = ({bool success, String? message, String? code, bool retryable, CashMovementResult? result});
typedef ExpRes = ({bool success, String? message, String? code, bool retryable, ExpenseSaved? result});

MoveRes moveOk() => (success: true, message: null, code: null, retryable: false, result: movementResult());
const MoveRes moveOffline = (success: false, message: 'Could not reach the server.', code: null, retryable: true, result: null);
MoveRes moveRefused(String code) => (success: false, message: 'x', code: code, retryable: false, result: null);
ExpRes expOk() => (success: true, message: null, code: null, retryable: false, result: expenseSaved());
const ExpRes expOffline = (success: false, message: 'Could not reach the server.', code: null, retryable: true, result: null);
ExpRes expRefused(String code) => (success: false, message: 'x', code: code, retryable: false, result: null);

void main() {
  late _Repo repo;
  late _Queue queue;
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
    repo = _Repo();
    queue = _Queue();
    cache = CashConfigCache();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.getCashConfig('st1')).thenAnswer((_) async => cashConfig());
  });

  Future<void> pause([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));
  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);

  void stubMove(Future<MoveRes> Function(Map<Symbol, dynamic> a) f) {
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
    ).thenAnswer((i) => f(i.namedArguments));
  }

  void stubExpense(Future<ExpRes> Function(Map<Symbol, dynamic> a) f) {
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
    ).thenAnswer((i) => f(i.namedArguments));
  }

  CashMovementController movement({String type = 'cash_in', String? session = 'se1', String Function()? ids, CashApprovalRequesterLike? approval, DateTime Function()? clock}) =>
      CashMovementController(
        initialType: type,
        repository: repo,
        cache: cache,
        queue: queue,
        storeId: 'st1',
        sessionIdProvider: () async => session,
        employeeTokenProvider: () async => 'tok-sam',
        approval: approval == null ? null : ({required String reason, repository}) => approval(reason),
        requestIdFactory: ids,
        clock: clock ?? () => DateTime.utc(2026, 11, 9, 8),
      );

  group('CashMovementController', () {
    test('loads the categories and currency from the server and remembers them for offline use', () async {
      final c = movement();
      c.onInit();
      await pause();
      expect(c.categories, ['float_topup', 'owner_injection', 'other_in']);
      expect(c.cur, usd);
      expect((await cache.load('st1'))!.cur, usd);
      c.setType('cash_out');
      expect(c.categories, contains('bank_deposit'));
      expect(c.category.value, isNull, reason: 'switching type clears the reason');
    });

    for (final (code, exp, text, minor) in [('USD', 2, '12.5', 1250), ('JPY', 0, '700', 700), ('KWD', 3, '1.234', 1234)]) {
      test('$code (exponent $exp): "$text" is sent as $minor minor units with the open shift, the category and the same occurredAt', () async {
        when(() => repo.getCashConfig('st1')).thenAnswer((_) async => cashConfig(currency: code, exponent: exp));
        final c = movement()..onInit();
        await pause();
        c.pickCategory('float_topup');
        c.amountText.value = text;
        Map<Symbol, dynamic>? sent;
        stubMove((a) async {
          sent = a;
          return moveOk();
        });
        expect(await c.submit(), isTrue);
        expect(sent![#amountMinor], minor);
        expect(sent![#type], 'cash_in');
        expect(sent![#category], 'float_topup');
        expect(sent![#sessionId], 'se1');
        expect(sent![#occurredAt], DateTime.utc(2026, 11, 9, 8));
        expect(c.outcome.value, CashOutcome.booked);
      });
    }

    test('cash out is sent as cash_out; a note is required for "other" and the server\'s rule is not faked otherwise', () async {
      final c = movement(type: 'cash_out')..onInit();
      await pause();
      c.pickCategory('other_out');
      c.amountText.value = '5';
      expect(c.noteRequired, isTrue);
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Add a short note when the reason is "Other".');
      c.note.value = ' float for a delivery ';
      expect(c.canSubmit, isTrue);
      Map<Symbol, dynamic>? sent;
      stubMove((a) async {
        sent = a;
        return moveOk();
      });
      await c.submit();
      expect(sent![#type], 'cash_out');
      expect(sent![#note], ' float for a delivery ');
      c.pickCategory('petty');
      expect(c.noteRequired, isFalse);
    });

    test('no open shift: nothing is sent and the reason is plain', () async {
      final c = movement(session: null)..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '5';
      expect(c.hasOpenShift, isFalse);
      expect(c.canSubmit, isFalse);
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'There is no open shift on this till. Open a shift first.');
    });

    test('requestId: a retry of the same movement keeps its id and device time; a changed amount is a new movement', () async {
      var n = 0;
      var t = 0;
      final c = movement(ids: () => 'req-${++n}', clock: () => DateTime.utc(2026, 11, 9, 8, t++))..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '10';
      final ids = <String>[];
      final times = <DateTime>[];
      stubMove((a) async {
        ids.add(a[#requestId] as String);
        times.add(a[#occurredAt] as DateTime);
        return moveRefused('POS_ACTION_FORBIDDEN');
      });
      await c.submit();
      await c.submit();
      expect(ids, ['req-1', 'req-1']);
      expect(times[0], times[1], reason: 'the device time of the movement does not move on a retry');
      c.amountText.value = '11';
      await c.submit();
      expect(ids.last, 'req-2');
    });

    test('POS_APPROVAL_REQUIRED asks a manager PIN and sends the SAME request again with the approver token', () async {
      String? asked;
      final c = movement(
        ids: () => 'req-x',
        approval: (reason) async {
          asked = reason;
          return 'tok-mgr';
        },
      )..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '500';
      final seen = <(String, String?)>[];
      stubMove((a) async {
        seen.add((a[#requestId] as String, a[#approverToken] as String?));
        return seen.length == 1 ? moveRefused('POS_APPROVAL_REQUIRED') : moveOk();
      });
      expect(await c.submit(), isTrue);
      expect(seen, [('req-x', null), ('req-x', 'tok-mgr')]);
      expect(asked, contains('approval'));
    });

    test('a cancelled approval sheet leaves it unsent with the approval message; POS_OWNER_REQUIRED is explained', () async {
      final c = movement(approval: (_) async => null)..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '500';
      stubMove((_) async => moveRefused('POS_APPROVAL_REQUIRED'));
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'A manager must approve this.');
      stubMove((_) async => moveRefused('POS_OWNER_REQUIRED'));
      await c.submit();
      expect(c.error.value, contains('store owner must do this'));
    });

    test('offline: the movement is queued with its request id, category, minor amount, shift, currency and the device time; nothing is sent', () async {
      final c = movement(ids: () => 'req-off')..onInit();
      await pause();
      offline();
      c.pickCategory('float_topup');
      c.amountText.value = '12.5';
      expect(await c.submit(), isTrue);
      expect(c.outcome.value, CashOutcome.queued);
      final l = queue.last;
      expect(l[#requestId], 'req-off');
      expect(l[#amountMinor], 1250);
      expect(l[#category], 'float_topup');
      expect(l[#type], 'cash_in');
      expect(l[#sessionId], 'se1');
      expect(l[#currency], 'USD');
      expect(l[#currencyExponent], 2);
      expect(l[#occurredAt], DateTime.utc(2026, 11, 9, 8));
      expect(l[#employeeToken], 'tok-sam');
      expect(queue.syncs, 1);
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

    test('offline with no remembered currency: it cannot be typed, with a plain reason (never a guessed currency)', () async {
      offline();
      final c = movement()..onInit();
      await pause();
      expect(c.cur, isNull);
      c.pickCategory('float_topup');
      c.amountText.value = '5';
      expect(c.amountMinor, isNull);
      expect(await c.submit(), isFalse);
      expect(c.error.value, contains('Connect once'));
    });

    test('offline it works from the remembered config (categories + currency)', () async {
      await cache.save('st1', cashConfig(currency: 'JPY', exponent: 0));
      offline();
      final c = movement()..onInit();
      await pause();
      expect(c.cur, jpy);
      c.pickCategory('float_topup');
      c.amountText.value = '500';
      expect(c.amountMinor, 500);
      expect(c.canSubmit, isTrue);
    });

    test('a timeout (no answer) while online queues the SAME request id, so the server can book it only once', () async {
      final c = movement(ids: () => 'req-t')..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '5';
      stubMove((a) async => moveOffline);
      expect(await c.submit(), isTrue);
      expect(c.outcome.value, CashOutcome.queued);
      expect(queue.last[#requestId], 'req-t');
    });

    test('double tap: one request in flight', () async {
      final c = movement()..onInit();
      await pause();
      c.pickCategory('float_topup');
      c.amountText.value = '5';
      var calls = 0;
      stubMove((_) async {
        calls++;
        await pause(30);
        return moveOk();
      });
      final a = c.submit();
      final b = c.submit();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(calls, 1);
    });
  });

  group('ExpenseFormController', () {
    ExpenseFormController form({String? session = 'se1', String Function()? ids, CashApprovalRequesterLike? approval}) => ExpenseFormController(
      repository: repo,
      cache: cache,
      queue: queue,
      storeId: 'st1',
      sessionIdProvider: () async => session,
      employeeTokenProvider: () async => 'tok-sam',
      approval: approval == null ? null : ({required String reason, repository}) => approval(reason),
      requestIdFactory: ids,
      clock: () => DateTime.utc(2026, 11, 9, 8),
    );

    for (final (code, exp, text, minor) in [('USD', 2, '120', 12000), ('JPY', 0, '700', 700), ('KWD', 3, '0.5', 500)]) {
      test('$code: "$text" is $minor minor units; category, method, payee and note go along', () async {
        when(() => repo.getCashConfig('st1')).thenAnswer((_) async => cashConfig(currency: code, exponent: exp));
        final c = form()..onInit();
        await pause();
        c.pickCategory('rent');
        c.amountText.value = text;
        c.payee.value = ' Landlord ';
        Map<Symbol, dynamic>? sent;
        stubExpense((a) async {
          sent = a;
          return expOk();
        });
        expect(await c.submit(), isTrue);
        expect(sent![#amountMinor], minor);
        expect(sent![#method], 'cash');
        expect(sent![#sessionId], 'se1');
        expect(sent![#category], 'rent');
        expect(c.saved.value!.number, 'EXP-000001');
      });
    }

    test('bank / other expenses send no session; "other" needs a note; with no open shift cash cannot be chosen', () async {
      final c = form(session: null)..onInit();
      await pause();
      expect(c.method.value, 'bank', reason: 'no open shift: it starts on bank');
      c.pickCategory('other');
      c.amountText.value = '5';
      expect(c.canSubmit, isFalse);
      c.note.value = 'bits';
      Map<Symbol, dynamic>? sent;
      stubExpense((a) async {
        sent = a;
        return expOk();
      });
      expect(await c.submit(), isTrue);
      expect(sent![#sessionId], isNull);
      expect(sent![#method], 'bank');
      c.pickMethod('cash');
      c.amountText.value = '6';
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'There is no open shift on this till. Open a shift first.');
    });

    test('requestId stable on retry; approval repeats the same id with the token', () async {
      var n = 0;
      final c = form(ids: () => 'ex-${++n}', approval: (_) async => 'tok-mgr')..onInit();
      await pause();
      c.pickCategory('rent');
      c.amountText.value = '500';
      final seen = <(String, String?)>[];
      stubExpense((a) async {
        seen.add((a[#requestId] as String, a[#approverToken] as String?));
        return seen.length == 1 ? expRefused('POS_APPROVAL_REQUIRED') : expRefused('POS_ACTION_FORBIDDEN');
      });
      await c.submit();
      await c.submit();
      expect(seen.map((e) => e.$1).toSet(), {'ex-1'});
      expect(seen.first.$2, isNull);
      expect(seen[1].$2, 'tok-mgr');
      expect(c.error.value, 'Your role is not allowed to do this.');
    });

    test('the receipt photo is uploaded after the expense is saved; a failed upload does not lose the expense and says why', () async {
      final c = form()..onInit();
      await pause();
      c.pickCategory('rent');
      c.amountText.value = '5';
      c.setPhoto(File('/tmp/p.jpg'));
      stubExpense((_) async => expOk());
      when(
        () => repo.uploadExpenseReceipt('st1', 'x1', any(), employeeToken: any(named: 'employeeToken')),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'FILE_TOO_LARGE', retryable: false));
      expect(await c.submit(), isTrue);
      expect(c.saved.value, isNotNull);
      expect(c.photoNotice.value, contains('That file is too large'));
    });

    test('offline a drawer expense is queued (request id, minor amount, shift, time) with its photo kept for after the sync', () async {
      offline();
      await cache.save('st1', cashConfig());
      final c = form(ids: () => 'ex-off')..onInit();
      await pause();
      c.pickCategory('supplies');
      c.amountText.value = '40';
      c.setPhoto(File('/tmp/receipt.jpg'));
      expect(await c.submit(), isTrue);
      expect(c.outcome.value, CashOutcome.queued);
      expect(queue.last[#requestId], 'ex-off');
      expect(queue.last[#amountMinor], 4000);
      expect(queue.last[#sessionId], 'se1');
      expect(queue.last[#occurredAt], DateTime.utc(2026, 11, 9, 8));
      expect(queue.lastReceipt[#expenseRequestId], 'ex-off');
      expect(queue.lastReceipt[#path], '/tmp/receipt.jpg');
      verifyNever(
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
      );
    });

    test('a photo whose upload cannot reach the server is queued against the saved expense id', () async {
      final c = form()..onInit();
      await pause();
      c.pickCategory('rent');
      c.amountText.value = '5';
      c.setPhoto(File('/tmp/p.jpg'));
      stubExpense((_) async => expOk());
      when(() => repo.uploadExpenseReceipt('st1', 'x1', any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((_) async => (success: false, message: 'offline', code: null, retryable: true));
      expect(await c.submit(), isTrue);
      expect(queue.lastReceipt[#expenseId], 'x1');
      expect(c.photoNotice.value, contains('upload when the till is online'));
    });

    test('offline a bank expense is refused (needs internet) and cannot be selected; a drawer expense is allowed', () async {
      offline();
      final c = form()..onInit();
      await pause();
      expect(c.methodAllowed('cash'), isTrue);
      expect(c.methodAllowed('bank'), isFalse);
      c.pickMethod('bank');
      expect(c.method.value, 'cash');
    });

    test('NOTE_REQUIRED / INVALID amount are caught before sending', () async {
      final c = form()..onInit();
      await pause();
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Choose a reason from the list.');
      c.pickCategory('rent');
      c.amountText.value = 'abc';
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'Enter a valid amount above zero.');
      verifyNever(
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
      );
    });
  });

  group('ExpenseListController', () {
    test('asks for the chosen period and status as local day boundaries, and keeps the category totals', () async {
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => expenseList([expense(), expense(id: 'x2', category: 'meals', amountMinor: 500)]));
      final c = ExpenseListController(repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 9, 15))..onInit();
      await pause();
      verify(() => repo.getExpenses('st1', status: 'all', from: DateTime(2026, 11, 3), to: DateTime(2026, 11, 10))).called(1);
      expect(c.totals['rent'], 12000);
      expect(c.totalMinor, 12500);
      c.setPeriod(ExpensePeriod.today);
      await pause();
      verify(() => repo.getExpenses('st1', status: 'all', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10))).called(1);
      c.setStatus('approved');
      await pause();
      verify(() => repo.getExpenses('st1', status: 'approved', from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 10))).called(1);
      c.onClose();
    });

    test('error shows the server code in words; offline makes no request', () async {
      when(
        () => repo.getExpenses(
          'st1',
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = ExpenseListController(repository: repo, storeId: 'st1')..onInit();
      await pause();
      expect(c.error.value, 'Your role is not allowed to do this.');
      c.onClose();
      Get.reset();
      offline();
      clearInteractions(repo);
      final d = ExpenseListController(repository: repo, storeId: 'st1')..onInit();
      await pause();
      verifyNever(
        () => repo.getExpenses(
          any(),
          status: any(named: 'status'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
      d.onClose();
    });
  });

  group('ExpenseDetailController', () {
    ExpenseDetailController detail({Expense? e}) {
      when(() => repo.getExpense('st1', 'x1')).thenAnswer((_) async => e ?? expense(hasReceipt: true));
      return ExpenseDetailController(expenseId: 'x1', repository: repo, storeId: 'st1')..onInit();
    }

    test('the receipt link is fetched FRESH every time it is opened, held in memory only and dropped on close', () async {
      final c = detail();
      await pause();
      var n = 0;
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => ReceiptLink(url: 'https://signed.example/${++n}?sig=abc', mimeType: 'image/png'));
      await c.openReceipt();
      expect(c.receipt.value!.url, endsWith('/1?sig=abc'));
      c.closeReceipt();
      expect(c.receipt.value, isNull);
      await c.openReceipt();
      expect(c.receipt.value!.url, endsWith('/2?sig=abc'));
      verify(() => repo.getExpenseReceiptLink('st1', 'x1')).called(2);
      c.onClose();
      expect(c.receipt.value, isNull);
    });

    test('the link is never printed (toString names only the kind)', () {
      const l = ReceiptLink(url: 'https://signed.example/secret?sig=zzz', mimeType: 'application/pdf');
      expect(l.toString().contains('secret'), isFalse);
      expect(l.isPdf, isTrue);
    });

    test('NO_RECEIPT and offline are explained', () async {
      final c = detail();
      await pause();
      when(() => repo.getExpenseReceiptLink('st1', 'x1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('NO_RECEIPT');
      await c.openReceipt();
      expect(c.receiptError.value, 'This expense has no receipt photo.');
      offline();
      await c.openReceipt();
      expect(c.receiptError.value, 'Needs internet.');
    });

    test('approve / reject: a rejection needs a reason; ALREADY_DECIDED is explained; the result replaces the expense', () async {
      final c = detail(e: expense());
      await pause();
      c.canManageHint.value = true;
      expect(c.canDecide, isTrue);
      expect(await c.decide(approve: false), isFalse);
      expect(c.actionError.value, 'Add a short note when the reason is "Other".');
      verifyNever(
        () => repo.decideExpense(
          any(),
          any(),
          approve: any(named: 'approve'),
          note: any(named: 'note'),
        ),
      );
      when(
        () => repo.decideExpense('st1', 'x1', approve: false, note: 'no receipt'),
      ).thenAnswer((_) async => (success: true, message: null, code: null, expense: expense(status: 'rejected', decisionNote: 'no receipt')));
      expect(await c.decide(approve: false, note: 'no receipt'), isTrue);
      expect(c.expense.value!.status, 'rejected');
      expect(c.canDecide, isFalse, reason: 'already decided');
      when(() => repo.decideExpense('st1', 'x1', approve: true, note: null)).thenAnswer((_) async => (success: false, message: 'x', code: 'ALREADY_DECIDED', expense: null));
      await c.decide(approve: true);
      expect(c.actionError.value, 'This expense was already approved or rejected.');
    });

    test('a cashier (no manager hint) is not offered the decision', () async {
      final c = detail();
      await pause();
      expect(c.canDecide, isFalse);
    });
  });

  group('DaybookController', () {
    DaybookController book({DateTime? now, ThermalPrinterService? printer, Future<void> Function(ShareParams)? share}) =>
        DaybookController(repository: repo, storeId: 'st1', clock: () => now ?? DateTime(2026, 11, 9, 15), printer: printer, share: share, storeName: () async => 'Dev Store');

    test('asks for the local day [midnight, next midnight) and moves day by day, never past today', () async {
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => daybook());
      final c = book()..onInit();
      await pause();
      verify(() => repo.getDaybookDay('st1', date: '2026-11-09')).called(1);
      expect(c.isToday, isTrue);
      c.nextDay();
      expect(c.day.value.day, 9, reason: 'cannot go past today');
      c.previousDay();
      await pause();
      verify(() => repo.getDaybookDay('st1', date: '2026-11-08')).called(1);
      c.onClose();
    });

    test('a slow answer for an older day never overwrites a newer day', () async {
      final slow = Future<Daybook?>.delayed(const Duration(milliseconds: 60), () => daybook(shifts: const []));
      when(() => repo.getDaybookDay('st1', date: '2026-11-09')).thenAnswer((_) => slow);
      when(() => repo.getDaybookDay('st1', date: '2026-11-08')).thenAnswer((_) async => daybook());
      final c = book()..onInit();
      await pause(5);
      c.previousDay();
      await pause(100);
      expect(c.daybook.value!.shifts, hasLength(1));
      c.onClose();
    });

    test('error in words, and offline makes no request', () async {
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('RANGE_TOO_LONG');
      final c = book()..onInit();
      await pause();
      expect(c.error.value, 'A daybook covers at most 31 days.');
      c.onClose();
      Get.reset();
      offline();
      clearInteractions(repo);
      final d = book()..onInit();
      await pause();
      verifyNever(
        () => repo.getDaybookDay(any(), date: any(named: 'date')),
      );
      d.onClose();
    });

    test('print: no printer says so; a printer gets the builder\'s lines for ITS column count; share builds a PDF named by the day', () async {
      when(
        () => repo.getDaybookDay('st1', date: any(named: 'date')),
      ).thenAnswer((_) async => daybook());
      final printer = _Printer();
      when(() => printer.hasSavedPrinter).thenReturn(false);
      var c = book(printer: printer)..onInit();
      await pause();
      await c.printIt();
      expect(c.printNotice.value, contains('No printer is set up'));
      c.onClose();
      Get.reset();
      when(() => printer.hasSavedPrinter).thenReturn(true);
      var cols = 0;
      when(() => printer.printDocument(any())).thenAnswer((i) async {
        final lines = (i.positionalArguments.first as dynamic Function(int))(48) as List;
        cols = lines.length;
        return null;
      });
      ShareParams? shared;
      c = book(printer: printer, share: (p) async => shared = p)..onInit();
      await pause();
      await c.printIt();
      expect(c.printOk.value, isTrue);
      expect(cols, greaterThan(10));
      await c.sharePdf();
      expect(shared!.subject, 'Daybook 2026-11-09');
      expect(shared!.files!.single.mimeType, 'application/pdf');
      expect(c.previewText(32).split('\n').every((l) => l.length <= 32), isTrue);
      c.onClose();
    });
  });

  group('models', () {
    test('daybook JSON: reconciled false with the difference, ownShiftsOnly, lines in order; sale / void open the sale, a refund does not', () {
      final d = Daybook.fromJson(daybookJson());
      expect(d.reconciled, isFalse);
      expect(d.unreconciledMinor, -300);
      expect(d.ownShiftsOnly, isTrue);
      expect(d.cur, usd);
      expect(d.shifts.single.lines.first.runningMinor, 10000);
      expect(const DaybookLine(type: 'cash_sale', label: '', amountMinor: 1, runningMinor: 1, refType: 'sale', refId: 's').opensSale, isTrue);
      expect(const DaybookLine(type: 'cash_refund', label: '', amountMinor: 1, runningMinor: 1, refType: 'void', refId: 's').opensSale, isTrue);
      expect(
        const DaybookLine(type: 'cash_refund', label: '', amountMinor: 1, runningMinor: 1, refType: 'refund', refId: 'rf').opensSale,
        isFalse,
        reason: 'a refund id is not a sale id: without saleId it is not tappable',
      );
      const refund = DaybookLine(type: 'cash_refund', label: '', amountMinor: 1, runningMinor: 1, refType: 'refund', refId: 'rf', saleId: 'sale7');
      expect(refund.opensSale, isTrue);
      expect(refund.saleTarget, 'sale7', reason: 'the sale to open is the refund\'s saleId, never the refund id');
      expect(const DaybookLine(type: 'cash_sale', label: '', amountMinor: 1, runningMinor: 1, refType: 'sale', refId: 's', saleId: 'other').saleTarget, 's');
      expect(const DaybookLine(type: 'expense', label: '', amountMinor: 1, runningMinor: 1, refType: 'expense', refId: 'x').opensSale, isFalse);
    });

    test('who recorded an expense and what its receipt is come from the expense itself; employee names and sale ids on daybook lines', () {
      final e = Expense.fromJson(expenseJson(hasReceipt: true, receiptMime: 'application/pdf'));
      expect(e.employeeName, 'Sam');
      expect(e.receiptMimeType, 'application/pdf');
      expect(e.receiptIsPdf, isTrue);
      expect(Expense.fromJson(expenseJson(hasReceipt: true)).receiptIsPdf, isFalse);
      expect(Expense.fromJson(expenseJson(hasReceipt: false, receiptMime: 'application/pdf')).receiptIsPdf, isFalse, reason: 'no receipt: nothing to say about it');
      final d = Daybook.fromJson(daybookJson());
      expect(d.shifts.single.lines.first.employeeName, 'Sam');
      expect(d.shifts.single.lines.last.saleTarget, 'sale9');
    });

    test('expense status, decision note, currency of the row, total of categories', () {
      final e = Expense.fromJson(expenseJson(status: 'rejected', decisionNote: 'duplicate', hasReceipt: true));
      expect(e.decided, isTrue);
      expect(e.decisionNote, 'duplicate');
      expect(e.cur, usd);
      expect(e.hasReceipt, isTrue);
      expect(
        ExpenseList.fromJson({
          'currency': 'USD',
          'currencyExponent': 2,
          'expenses': [expenseJson()],
          'totalsByCategoryMinor': {'rent': 12000, 'meals': 300},
        }).totalMinor,
        12300,
      );
    });

    test('a config without lists falls back to the known categories; a config remembers its limits', () {
      final c = CashConfig.fromJson({'currency': 'USD', 'currencyExponent': 2});
      expect(c.cashInCategories, contains('float_topup'));
      expect(CashConfig.fromJson(cashConfig().toJson()).cashOutApprovalAboveMinor, 5000);
    });

    test('error codes in words', () {
      for (final code in ['NO_OPEN_SHIFT', 'NOTE_REQUIRED', 'POS_APPROVAL_REQUIRED', 'POS_OWNER_REQUIRED', 'ALREADY_DECIDED', 'FILE_TOO_LARGE', 'FILE_TYPE', 'NO_RECEIPT', 'RANGE_REQUIRED']) {
        expect(cashErrorMessage(code), isNot(contains('Something went wrong')), reason: code);
      }
      expect(cashErrorMessage('WHAT', fallback: 'server said'), 'server said');
    });
  });
}

typedef CashApprovalRequesterLike = Future<String?> Function(String reason);

PendingCashRecord _rec() => PendingCashRecord(seq: 1, id: 'q', kind: 'movement', payload: const {}, status: 'pending', createdAt: DateTime(2026));
