import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_hero_header.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_list.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_section_header.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SellerStoresView extends StatelessWidget {
  SellerStoresView({super.key});

  final SellerStoresController controller = Get.put(SellerStoresController());

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimen.allPadding,
          12,
          AppDimen.allPadding,
          12 + bottomInset,
        ),
        child: AppButton(
          onPressed: controller.createNewStore,
          label: 'Create New Store',
          iconWidget: SvgIcon(
            assetName: AppIcons.addIcon,
            color: AppColors.white,
          ),
        ),
      ),
      backgroundColor: AppColors.textfldFillColor,
      body: Obx(() {
        if (controller.isLoading.value) return const StoresShimmer();
        return CustomRefreshWrapper(
          onRefresh: controller.refreshStores,
          child: SingleChildScrollView(
            child: Column(
              children: [
                StoresHeroHeader(controller: controller),
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.textfldFillColor,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        StoresSectionHeader(controller: controller),
                        const SizedBox(height: 12),
                        StoresList(controller: controller),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
