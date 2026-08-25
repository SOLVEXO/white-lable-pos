import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_profile_section.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_stats_strip.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/utils/custom_alert_dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresHeroHeader extends StatelessWidget {
  final SellerStoresController controller;

  const StoresHeroHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      decoration: BoxDecoration(gradient: AppColors.appbarGradient),
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 48),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SvgIcon(
                assetName: AppIcons.logoutIcon,
                onTap: () {
                  showCustomDialog(
                    title: 'Logout',
                    content: 'Are you sure you want to logout?',
                    leftButtonName: 'Cancel',
                    rightButtonName: 'Logout',
                    onLeftButtonTap: () => Get.back(),
                    onRightButtonTap: () async {
                      await AuthRepository().logout();
                      Get.offAllNamed(Routes.posLogin);
                    },
                  );
                },
                color: AppColors.white,
                size: 30,
              ),
            ],
          ),
          const SizedBox(height: 20),
          StoresProfileSection(controller: controller),
          const SizedBox(height: 28),
          StoresStatsStrip(controller: controller),
        ],
      ),
    );
  }
}
