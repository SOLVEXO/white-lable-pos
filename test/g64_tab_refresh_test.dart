// G6.4: tabs are built once and kept alive, so returning to Orders (or Home) re-reads it — a sale rung up on Sell shows on Orders without a
// pull-to-refresh. Only the loads their pull-to-refresh already runs; a controller that is not created yet is left alone (it loads on creation).
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';

import 'support/sale_harness.dart' show MockPosRepository;

MockPosRepository _repo() {
  final r = MockPosRepository();
  when(() => r.getPosSettings(any())).thenAnswer((_) async => null); // the orders screen's store context on creation
  return r;
}

class _Orders extends PosOrdersController {
  _Orders() : super(posRepository: _repo());
  int reloads = 0;
  @override
  Future<void> loadSales() async {} // onInit's first load: nothing to fetch in this test
  @override
  Future<void> refreshData() async => reloads++;
}

class _Home extends PosHomeTabController {
  _Home() : super(posRepository: MockPosRepository());
  int reloads = 0;
  @override
  Future<void> load() async => reloads++;
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  test('switching TO Orders / Home re-reads it; staying on a tab or other tabs do not', () {
    final orders = Get.put<PosOrdersController>(_Orders()) as _Orders;
    final home = Get.put<PosHomeTabController>(_Home()) as _Home;
    final homeBase = home.reloads; // its own first load on creation
    final nav = PosBottomNavController();
    nav.selectedIndex.value = PosBottomNavController.saleTab;
    nav.changeTab(PosBottomNavController.ordersTab);
    expect(orders.reloads, 1);
    nav.changeTab(PosBottomNavController.ordersTab); // already there: no extra request
    expect(orders.reloads, 1);
    nav.changeTab(PosBottomNavController.stockTab);
    nav.changeTab(PosBottomNavController.homeTab);
    expect(home.reloads, homeBase + 1);
    expect(orders.reloads, 1);
    nav.changeTab(PosBottomNavController.ordersTab);
    expect(orders.reloads, 2);
  });

  test('a controller registered lazily but not created yet is left alone (it loads when the tab builds it)', () {
    var created = false;
    Get.lazyPut<PosOrdersController>(() {
      created = true;
      return _Orders();
    });
    final nav = PosBottomNavController()..selectedIndex.value = PosBottomNavController.saleTab;
    nav.refreshTab(PosBottomNavController.ordersTab);
    expect(created, isFalse);
  });
}
