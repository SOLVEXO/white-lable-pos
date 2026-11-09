// G3.1 on the till: the inventory controllers against a mocked repository (paging / search / filter, adjust incl. the manager approval
// retry and error mapping, the double-submit guard, stock counts, role visibility).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_adjust_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_count_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_limits_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_movements_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';

import 'support/inventory_fixtures.dart';
import 'support/sale_harness.dart';

typedef _Adjust = ({bool success, String? message, String? code, Map<String, dynamic>? data});

void main() {
  late MockPosRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.testMode = true;
    Get.reset();
    repo = MockPosRepository();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  void stubStock(Future<InvPage<InvRow>?> Function(Invocation) f) {
    when(
      () => repo.getInventoryStock(
        any(),
        search: any(named: 'search'),
        filter: any(named: 'filter'),
        page: any(named: 'page'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(f);
  }

  group('overview', () {
    test('manager sees value; a cashier overview has none and cannot manage', () async {
      when(() => repo.getInventoryOverview('s1')).thenAnswer((_) async => overview(openCount: true));
      final c = InvOverviewController(repository: repo, storeId: 's1');
      await c.load();
      expect(c.canManage, isTrue);
      expect(c.overview.value!.stockValueMinor, 1234500);
      expect(c.overview.value!.hasOpenCount, isTrue);

      when(() => repo.getInventoryOverview('s1')).thenAnswer((_) async => overview(role: 'cashier'));
      await c.load();
      expect(c.canManage, isFalse);
      expect(c.overview.value!.stockValueMinor, isNull);
    });

    test('a failed load keeps an error message and no data', () async {
      when(() => repo.getInventoryOverview(any())).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = InvOverviewController(repository: repo, storeId: 's1');
      await c.load();
      expect(c.overview.value, isNull);
      expect(c.error.value, 'Your role is not allowed to do this.');
      expect(c.loading.value, isFalse);
    });

    test('money is formatted from minor units with the store exponent', () {
      expect(invMoney(1234500, 2), '\$12,345.00');
      expect(invMoney(1500, 0), '\$1,500');
      expect(invMoney(1500, 3), '\$1.500');
    });
  });

  group('stock list', () {
    test('first page, then the next page is appended (infinite scroll), stopping when there is no more', () async {
      stubStock((i) async {
        final page = i.namedArguments[#page] as int;
        return page == 1 ? rowsPage([row(id: 'a'), row(id: 'b')], total: 3, hasMore: true) : rowsPage([row(id: 'c')], total: 3, page: 2);
      });
      final c = InvStockListController(repository: repo, storeId: 's1', pageSize: 2);
      await c.reload();
      expect(c.items.map((e) => e.variantId), ['a', 'b']);
      expect(c.hasMore.value, isTrue);
      await c.loadMore();
      expect(c.items.map((e) => e.variantId), ['a', 'b', 'c']);
      expect(c.hasMore.value, isFalse);
      await c.loadMore(); // nothing more: no extra request
      verify(
        () => repo.getInventoryStock(
          's1',
          search: '',
          filter: 'all',
          page: any(named: 'page'),
          limit: 2,
        ),
      ).called(2);
    });

    test('search is debounced to one request and the filter restarts at page 1', () async {
      stubStock((i) async => rowsPage([row()]));
      final c = InvStockListController(repository: repo, storeId: 's1', debounce: const Duration(milliseconds: 20));
      await c.reload();
      c.onQueryChanged('l');
      c.onQueryChanged('la');
      c.onQueryChanged('latte');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      verify(() => repo.getInventoryStock('s1', search: 'latte', filter: 'all', page: 1, limit: 30)).called(1);
      verifyNever(
        () => repo.getInventoryStock(
          's1',
          search: 'la',
          filter: any(named: 'filter'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      );
      c.setFilter('out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => repo.getInventoryStock('s1', search: 'latte', filter: 'out', page: 1, limit: 30)).called(1);
      c.onClose();
    });

    test('a slow answer to an older search never overwrites a newer one', () async {
      final slow = Completer<InvPage<InvRow>?>();
      var n = 0;
      stubStock((i) {
        n++;
        return n == 1 ? slow.future : Future.value(rowsPage([row(id: 'new')]));
      });
      final c = InvStockListController(repository: repo, storeId: 's1');
      final first = c.reload();
      await Future<void>.delayed(Duration.zero);
      await c.reload();
      slow.complete(rowsPage([row(id: 'old')]));
      await first;
      expect(c.items.single.variantId, 'new');
    });

    test('low-only starts pre-filtered and ignores filter changes; an error is shown, not thrown', () async {
      stubStock((i) async => null);
      when(() => repo.lastErrorCode).thenReturn(null);
      final c = InvStockListController(repository: repo, storeId: 's1', lowOnly: true);
      c.onInit();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verify(() => repo.getInventoryStock('s1', search: '', filter: 'low', page: 1, limit: 30)).called(1);
      c.setFilter('out');
      expect(c.filter.value, 'low');
      expect(c.error.value, isNotNull);
    });

    test('cost and value are shown only when the server sent them (role visibility)', () {
      expect(row(manager: true).costMinor, 250);
      expect(row(manager: false).costMinor, isNull);
      expect(row(manager: false).valueMinor, isNull);
    });
  });

  group('detail', () {
    test('loads the detail; manager is known from the role or from cost being present', () async {
      when(() => repo.getInventoryVariant('s1', 'v1')).thenAnswer((_) async => detail());
      final c = InvDetailController(variantId: 'v1', repository: repo, storeId: 's1', role: 'cashier');
      await c.load();
      expect(c.detail.value!.lots.length, 3);
      expect(c.canManage, isTrue); // cost present

      when(() => repo.getInventoryVariant('s1', 'v1')).thenAnswer((_) async => detail(manager: false));
      await c.load();
      expect(c.canManage, isFalse);
    });

    test('lot expiry days are counted by calendar day', () {
      final lot = InvLot(lotId: 'l', lotNumber: 'x', expiryDate: DateTime(2026, 11, 12), remaining: 1);
      expect(lot.daysLeft(DateTime(2026, 11, 9, 23, 59)), 3);
      expect(lot.daysLeft(DateTime(2026, 11, 12, 1)), 0);
      expect(lot.daysLeft(DateTime(2026, 11, 13)), -1);
    });

    test('movement labels are plain words and damaged shows as Marked damaged', () {
      expect(movement(type: 'sale').typeLabel, 'Sale');
      expect(movement(type: 'void').typeLabel, 'Voided sale');
      expect(movement(type: 'adjustment', qty: 0, damaged: 2, reason: 'damaged').typeLabel, 'Marked damaged');
      expect(movement(type: 'write_off').typeLabel, 'Written off');
    });
  });

  group('adjust', () {
    InvAdjustController make({InvApprovalRequester? approval}) => InvAdjustController(variantId: 'v1', currentStock: 20, repository: repo, storeId: 's1', approval: approval);
    void stubAdjust(Future<_Adjust> Function(Invocation) f) {
      when(
        () => repo.adjustInventory(
          any(),
          any(),
          delta: any(named: 'delta'),
          reason: any(named: 'reason'),
          note: any(named: 'note'),
          locationId: any(named: 'locationId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer(f);
    }

    const ok = (success: true, message: 'ok', code: null, data: <String, dynamic>{});

    test('happy path sends the change once and reports success; the preview says what will happen', () async {
      stubAdjust((_) async => ok);
      final c = make();
      expect(c.canSubmit, isFalse); // no change, no reason yet
      c.step(-2);
      c.pickReason('correction');
      expect(c.preview, 'Stock goes from 20 to 18.');
      expect(await c.submit(), isTrue);
      expect(c.result.value, 'Stock updated');
      verify(() => repo.adjustInventory('s1', 'v1', delta: -2, reason: 'correction', note: '', locationId: null, approverToken: null)).called(1);
    });

    test('damaged is reported as Marked damaged', () async {
      stubAdjust((_) async => ok);
      final c = make()..setDelta(1);
      c.pickReason('damaged');
      expect(c.preview, startsWith('Marked damaged'));
      await c.submit();
      expect(c.result.value, 'Marked damaged');
    });

    test('POS_APPROVAL_REQUIRED asks a manager and sends the SAME change again with the approver token', () async {
      var asked = 0;
      stubAdjust((i) async => i.namedArguments[#approverToken] == null ? (success: false, message: 'x', code: 'POS_APPROVAL_REQUIRED', data: null) : ok);
      final c = make(
        approval: ({required reason, repository}) async {
          asked++;
          return 'tok-mgr';
        },
      );
      c.setDelta(-9);
      c.pickReason('correction');
      expect(await c.submit(), isTrue);
      expect(asked, 1);
      verify(() => repo.adjustInventory('s1', 'v1', delta: -9, reason: 'correction', note: '', locationId: null, approverToken: null)).called(1);
      verify(() => repo.adjustInventory('s1', 'v1', delta: -9, reason: 'correction', note: '', locationId: null, approverToken: 'tok-mgr')).called(1);
    });

    test('declining the approval sends nothing more and says a manager must approve', () async {
      stubAdjust((_) async => (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', data: null));
      final c = make(approval: ({required reason, repository}) async => null);
      c.setDelta(-9);
      c.pickReason('correction');
      expect(await c.submit(), isFalse);
      expect(c.error.value, 'A manager must approve this change.');
      verify(
        () => repo.adjustInventory(
          any(),
          any(),
          delta: any(named: 'delta'),
          reason: any(named: 'reason'),
          note: any(named: 'note'),
          locationId: any(named: 'locationId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).called(1);
    });

    test('server error codes are mapped to plain English', () async {
      final cases = {
        'DELTA_INVALID': 'Enter a whole number of units that is not zero.',
        'REASON_INVALID': 'Pick a reason for the change.',
        'NOTE_REQUIRED': 'Add a short note when the reason is "Other".',
        'UNLIMITED_STOCK': 'This item has unlimited stock, so there is nothing to adjust.',
        'POS_PIN_REQUIRED': 'Sign in with your PIN to change stock.',
        'POS_ACTION_FORBIDDEN': 'Your role is not allowed to do this.',
        'POS_OWNER_REQUIRED': 'Only the store owner can do this.',
      };
      for (final e in cases.entries) {
        stubAdjust((_) async => (success: false, message: 'raw', code: e.key, data: null));
        final c = make()..setDelta(1);
        c.pickReason('other');
        expect(await c.submit(), isFalse, reason: e.key);
        expect(c.error.value, e.value, reason: e.key);
        expect(c.busy.value, isFalse);
      }
      stubAdjust((_) async => (success: false, message: 'Server said no', code: 'SOMETHING_NEW', data: null));
      final c = make()..setDelta(1);
      c.pickReason('other');
      await c.submit();
      expect(c.error.value, 'Server said no');
    });

    test('double submit: a second tap while the first is in flight sends nothing', () async {
      final gate = Completer<_Adjust>();
      stubAdjust((_) => gate.future);
      final c = make()..setDelta(-1);
      c.pickReason('correction');
      final first = c.submit();
      await Future<void>.delayed(Duration.zero);
      expect(c.busy.value, isTrue);
      expect(await c.submit(), isFalse);
      gate.complete(ok);
      expect(await first, isTrue);
      verify(
        () => repo.adjustInventory(
          any(),
          any(),
          delta: any(named: 'delta'),
          reason: any(named: 'reason'),
          note: any(named: 'note'),
          locationId: any(named: 'locationId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).called(1);
    });

    test('double submit also covers the manager approval sheet being open', () async {
      final sheet = Completer<String?>();
      stubAdjust((i) async => i.namedArguments[#approverToken] == null ? (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', data: null) : ok);
      final c = make(approval: ({required reason, repository}) => sheet.future);
      c.setDelta(-9);
      c.pickReason('correction');
      final first = c.submit();
      await Future<void>.delayed(Duration.zero);
      expect(await c.submit(), isFalse);
      sheet.complete('t');
      expect(await first, isTrue);
    });
  });

  group('movements', () {
    test('type filter restarts the list; paging appends', () async {
      when(
        () => repo.getInventoryMovements(
          's1',
          variantId: any(named: 'variantId'),
          type: any(named: 'type'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((i) async {
        final page = i.namedArguments[#page] as int;
        return InvPage(
          items: [movement(id: 'p$page-${i.namedArguments[#type]}')],
          total: 2,
          page: page,
          hasMore: page == 1,
        );
      });
      final c = InvMovementsController(repository: repo, storeId: 's1');
      await c.reload();
      expect(c.items.single.id, 'p1-null');
      await c.loadMore();
      expect(c.items.map((e) => e.id), ['p1-null', 'p2-null']);
      c.setType('sale');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.items.single.id, 'p1-sale');
    });

    test('a cashier gets the forbidden state (403 POS_ACTION_FORBIDDEN)', () async {
      when(
        () => repo.getInventoryMovements(
          any(),
          variantId: any(named: 'variantId'),
          type: any(named: 'type'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      final c = InvMovementsController(repository: repo, storeId: 's1');
      await c.reload();
      expect(c.forbidden.value, isTrue);
      expect(c.items, isEmpty);
    });
  });

  group('limits', () {
    test('reads the limits; money limits format from minor units, quantities as numbers', () async {
      when(() => repo.getInventoryLimits('s1')).thenAnswer(
        (_) async => (
          exponent: 2,
          limits: [
            const InvLimit(key: 'q', label: 'Units', kind: 'qty', value: 5, defaultValue: 5),
            const InvLimit(key: 'm', label: 'Value', kind: 'minor', value: 2000, defaultValue: 2000),
          ],
        ),
      );
      final c = InvLimitsController(repository: repo, storeId: 's1');
      await c.load();
      expect(c.limits.length, 2);
      expect(c.limits[0].format(c.limits[0].value, 2), '5');
      expect(c.limits[1].format(c.limits[1].value, 2), '\$20.00');
    });
  });

  group('stock count', () {
    InvCountController make({String role = 'manager'}) => InvCountController(repository: repo, storeId: 's1', role: role);

    void stubOpen({InvCount? c}) {
      when(() => repo.listInventoryCounts('s1')).thenAnswer((_) async => [c ?? count()]);
      when(() => repo.getInventoryCount('s1', 'c1')).thenAnswer((_) async => c ?? count());
    }

    test('opens the existing open count and shows progress', () async {
      stubOpen();
      final c = make();
      await c.load();
      expect(c.hasOpenCount, isTrue);
      expect(c.count.value!.countedCount, 1);
      expect(c.count.value!.items.length, 3);
    });

    test('no open count: a manager can start one; a cashier cannot (nothing is sent)', () async {
      when(() => repo.listInventoryCounts('s1')).thenAnswer((_) async => []);
      when(() => repo.startInventoryCount('s1')).thenAnswer((_) async => (success: true, message: null, code: null, count: count(counted: 0)));
      final m = make();
      await m.load();
      expect(m.hasOpenCount, isFalse);
      expect(await m.start(), isTrue);
      expect(m.count.value!.countedCount, 0);

      final cashier = make(role: 'cashier');
      await cashier.load();
      expect(await cashier.start(), isFalse);
      verify(() => repo.startInventoryCount('s1')).called(1);
    });

    test('a refused start (server) shows a plain message', () async {
      when(() => repo.listInventoryCounts('s1')).thenAnswer((_) async => []);
      when(() => repo.startInventoryCount('s1')).thenAnswer((_) async => (success: false, message: 'A stock count is already open for this store', code: null, count: null));
      final c = make();
      await c.load();
      expect(await c.start(), isFalse);
      expect(c.error.value, contains('already open'));
    });

    test('find -> pre-filled quantity -> enter saves it and updates progress', () async {
      stubOpen();
      final c = make();
      await c.load();
      when(() => repo.findInventoryCountItem('s1', 'c1', '1000000000011')).thenAnswer((_) async => (found: true, item: count().items[0]));
      expect(await c.find('1000000000011'), isTrue);
      expect(c.current.value!.productName, 'Dev Latte');
      expect(c.qty.value, 18); // the previous counted value
      c.setQty(19);
      when(() => repo.enterInventoryCount('s1', 'c1', 'i1', 19)).thenAnswer((_) async => (success: true, message: null, code: null, count: count(item2Counted: true)));
      expect(await c.saveCurrent(), isTrue);
      expect(c.current.value, isNull);
      expect(c.count.value!.countedCount, 2);
    });

    test('a line that was not counted yet starts at 0; "not on this count" is reported', () async {
      stubOpen();
      final c = make();
      await c.load();
      when(() => repo.findInventoryCountItem('s1', 'c1', '1000000000042')).thenAnswer((_) async => (found: true, item: count().items[1]));
      await c.find('1000000000042');
      expect(c.qty.value, 0);
      when(() => repo.findInventoryCountItem('s1', 'c1', 'nope')).thenAnswer((_) async => (found: false, item: null));
      expect(await c.find('nope'), isFalse);
      expect(c.notOnCount.value, isTrue);
      expect(c.current.value, isNull);
    });

    test('tapping a line selects it for editing; a negative quantity is not possible; QTY_INVALID is mapped', () async {
      stubOpen();
      final c = make();
      await c.load();
      c.select(c.count.value!.items[0]);
      expect(c.qty.value, 18);
      c.setQty(-4);
      expect(c.qty.value, 0);
      when(() => repo.enterInventoryCount(any(), any(), any(), any())).thenAnswer((_) async => (success: false, message: 'x', code: 'QTY_INVALID', count: null));
      expect(await c.saveCurrent(), isFalse);
      expect(c.error.value, 'Enter a whole number of units, zero or more.');
    });

    test('variance review lists only counted lines that differ; uncounted lines are never in it', () async {
      final cnt = count(item2Counted: true); // v1: 20 -> 18 (differs), v2: 8 -> 8 (same), v3 uncounted
      expect(cnt.variances.map((e) => e.variantId), ['v1']);
      expect(cnt.variances.single.variance, -2);
      expect(cnt.items.length - cnt.countedCount, 1);
    });

    test('finish (manager) posts once and returns what was applied; the count is then closed', () async {
      stubOpen();
      final c = make();
      await c.load();
      when(() => repo.finishInventoryCount('s1', 'c1')).thenAnswer((_) async => (success: true, message: null, code: null, result: const InvCountResult(applied: 1, skipped: ['Beans: recount it'])));
      expect(await c.finish(), isTrue);
      expect(c.result.value!.applied, 1);
      expect(c.result.value!.skipped.single, contains('Beans'));
      expect(c.count.value, isNull);
    });

    test('a cashier may enter counts but cannot finish or cancel (nothing is sent)', () async {
      stubOpen();
      final c = make(role: 'cashier');
      await c.load();
      expect(c.canManage, isFalse);
      expect(await c.finish(), isFalse);
      expect(await c.cancel(), isFalse);
      verifyNever(() => repo.finishInventoryCount(any(), any()));
      verifyNever(() => repo.cancelInventoryCount(any(), any()));
    });

    test('cancel closes the count; a refused finish keeps it open and shows why', () async {
      stubOpen();
      final c = make();
      await c.load();
      when(() => repo.finishInventoryCount('s1', 'c1')).thenAnswer((_) async => (success: false, message: 'no longer open', code: null, result: null));
      expect(await c.finish(), isFalse);
      expect(c.error.value, 'no longer open');
      expect(c.count.value, isNotNull);
      when(() => repo.cancelInventoryCount('s1', 'c1')).thenAnswer((_) async => (success: true, message: null, code: null));
      expect(await c.cancel(), isTrue);
      expect(c.count.value, isNull);
    });
  });
}
