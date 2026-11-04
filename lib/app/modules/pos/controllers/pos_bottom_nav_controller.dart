import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_more_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_stock_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/views/pos_home_view.dart';
import 'package:solvexo_pos/app/modules/pos_orders/views/pos_orders_view.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosBottomNavController extends GetxController {
  // Blueprint order: Home, Sell, Orders, Stock, More.
  static const int homeTab = 0;
  static const int saleTab = 1;
  static const int ordersTab = 2;
  static const int stockTab = 3;
  static const int moreTab = 4;

  /// Where the shell opens before the signed-in role is known (one preferences read, a few ms): Sell.
  static const int initialTab = saleTab;

  /// Cashiers land on Sell (their first act is ringing a sale); managers and owners land on Home (their numbers).
  static int landingTabFor(PosAccess access) => access.canManage ? homeTab : saleTab;

  RxInt selectedIndex = initialTab.obs;
  bool _userChoseTab = false;

  Worker? _restrictedWorker;

  @override
  void onInit() {
    super.onInit();
    // Role-based landing: applied once the role is read, unless the user already tapped a tab or the store is restricted.
    PosAccess.current().then((a) {
      final restricted = PosEntitlementService.maybe?.restricted.value ?? false;
      if (!_userChoseTab && !restricted && selectedIndex.value == initialTab) selectedIndex.value = landingTabFor(a);
    });
    final service = PosEntitlementService.maybe;
    if (service == null) return;
    // Entering the shell already restricted, or becoming restricted while on a selling tab (the server
    // just refused a sale): land on Orders — where refund/void and the way to Settings/close-shift live.
    if (service.restricted.value) selectedIndex.value = ordersTab;
    _restrictedWorker = ever<bool>(service.restricted, (r) {
      if (r && _isSellingTab(selectedIndex.value)) selectedIndex.value = ordersTab;
    });
  }

  @override
  void onClose() {
    _restrictedWorker?.dispose();
    super.onClose();
  }

  /// Sale and the product catalogue (under Stock) are selling surfaces — off in restricted mode. Home, Orders and More stay
  /// open (reports, refund/void, sync and settings are how a lapsed store gets back on track).
  bool _isSellingTab(int i) => i == saleTab || i == stockTab;

  void changeTab(int index) {
    if (PosEntitlementService.isRestricted && _isSellingTab(index)) {
      CustomAppSnackbar.warning('POS plan not active for this store — selling is turned off.');
      return;
    }
    _userChoseTab = true;
    selectedIndex.value = index;
  }

  final List<Widget> screens = [
    PosHomeTabView(),
    PosHomeView(),
    PosOrdersView(),
    const PosStockHubView(),
    const PosMoreHubView(),
  ];
}
