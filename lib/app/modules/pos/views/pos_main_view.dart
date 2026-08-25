import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_bottom_nav.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosMainView extends StatelessWidget {
  PosMainView({super.key});

  final controller = Get.find<PosBottomNavController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Obx(() => controller.screens[controller.selectedIndex.value]),
      bottomNavigationBar: const PosBottomNav(),
    );
  }
}
