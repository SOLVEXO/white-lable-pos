import 'package:solvexo_pos/app/modules/pos_home/views/pos_home_view.dart';
import 'package:solvexo_pos/app/modules/pos_orders/views/pos_orders_view.dart';
import 'package:solvexo_pos/app/modules/pos_products/views/pos_products_view.dart';
import 'package:solvexo_pos/app/modules/pos_settings/views/pos_settings_view.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosBottomNavController extends GetxController {
  static const int saleTab = 0;
  static const int ordersTab = 1;
  static const int productsTab = 2;

  RxInt selectedIndex = 0.obs;

  Worker? _restrictedWorker;

  @override
  void onInit() {
    super.onInit();
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

  /// Sale and the product catalog are selling surfaces — off in restricted mode.
  bool _isSellingTab(int i) => i == saleTab || i == productsTab;

  void changeTab(int index) {
    if (PosEntitlementService.isRestricted && _isSellingTab(index)) {
      CustomAppSnackbar.warning('POS plan not active for this store — selling is turned off.');
      return;
    }
    selectedIndex.value = index;
  }

  final List<Widget> screens = [
    PosHomeView(),
    PosOrdersView(),
    PosProductsView(),
    PosSettingsView(),
  ];
}
