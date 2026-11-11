import 'package:solvexo_pos/utils/unsynced_guard.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_profile_section.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_stats_strip.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/custom_alert_dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresHeroHeader extends StatelessWidget {
  final SellerStoresController controller;

  const StoresHeroHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: p.accentFill,
      padding: EdgeInsets.fromLTRB(
        Space.s5,
        topPad + Space.s3,
        Space.s5,
        Space.s12,
      ),
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
                      Get.back();
                      // Sales still on this device are the only copy of that money — never sign out over them.
                      if (await UnsyncedGuard.blockIfUnsynced(action: 'sign out')) return;
                      await AuthRepository().logout();
                      Get.offAllNamed(Routes.posLogin);
                    },
                  );
                },
                color: p.onAccentFill,
                size: 30,
              ),
            ],
          ),
          const SizedBox(height: Space.s5),
          StoresProfileSection(controller: controller),
          const SizedBox(height: Space.s6),
          StoresStatsStrip(controller: controller),
        ],
      ),
    );
  }
}
