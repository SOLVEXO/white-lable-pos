import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_close_shift_button.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_profile_card.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_section.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_settings_shimmer.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosSettingsView extends StatelessWidget {
  PosSettingsView({super.key});

  final PosSettingsController controller = Get.put(PosSettingsController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: Column(
        children: [
          const PosAppBar(title: 'Settings'),
          Divider(height: 1, color: p.border),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const PosSettingsShimmer();
              }
              return RefreshIndicator(
                onRefresh: controller.refreshData,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Space.s4),
                      children: [
                        PosSettingsProfileCard(controller: controller),
                        const SizedBox(height: Space.s6),
                        ...controller.sections.map((s) => PosSettingsSectionWidget(section: s)),
                        const SizedBox(height: Space.s2),
                        PosCloseShiftButton(onTap: controller.showCloseShiftDialog),
                        const SizedBox(height: Space.s2),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
