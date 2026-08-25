import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_close_shift_button.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_profile_card.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_section.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_shimmer.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosSettingsView extends StatelessWidget {
  PosSettingsView({super.key});

  final PosSettingsController controller = Get.put(PosSettingsController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const PosAppBar(title: 'Settings'),
          const Divider(height: 1, color: AppColors.lightGrey2),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const PosSettingsShimmer();
              }
              return CustomRefreshWrapper(
                onRefresh: controller.refreshData,
                child: ListView(
                  padding: const EdgeInsets.only(
                    top: AppDimen.allPadding,
                    bottom: AppDimen.allPadding,
                  ),
                  children: [
                    PosSettingsProfileCard(controller: controller),
                    const SizedBox(height: 24),
                    ...controller.sections.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: PosSettingsSectionWidget(section: s),
                      ),
                    ),
                    PosCloseShiftButton(
                      onTap: controller.showCloseShiftDialog,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
