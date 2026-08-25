import 'package:solvexo_pos/app/modules/pos_home/views/pos_home_view.dart';
import 'package:solvexo_pos/app/modules/pos_orders/views/pos_orders_view.dart';
import 'package:solvexo_pos/app/modules/pos_products/views/pos_products_view.dart';
import 'package:solvexo_pos/app/modules/pos_settings/views/pos_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosBottomNavController extends GetxController {
  RxInt selectedIndex = 0.obs;

  void changeTab(int index) => selectedIndex.value = index;

  final List<Widget> screens = [
    PosHomeView(),
    PosOrdersView(),
    PosProductsView(),
    PosSettingsView(),
  ];
}
