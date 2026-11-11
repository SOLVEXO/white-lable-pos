import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_hero_header.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_list.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_section_header.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/stores_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SellerStoresView extends StatelessWidget {
  SellerStoresView({super.key});

  final SellerStoresController controller = Get.put(SellerStoresController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.s4,
            Space.s3,
            Space.s4,
            Space.s3 + bottomInset,
          ),
          child: AppButton(
            onPressed: controller.createNewStore,
            label: 'Create New Store',
            icon: Icons.add_rounded,
            size: AppButtonSize.lg,
          ),
        ),
      ),
      backgroundColor: p.background,
      body: Obx(() {
        if (controller.isLoading.value) return const StoresShimmer();
        return CustomRefreshWrapper(
          onRefresh: controller.refreshStores,
          child: SingleChildScrollView(
            child: Column(
              children: [
                StoresHeroHeader(controller: controller),
                Transform.translate(
                  offset: const Offset(0, -Space.s6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(Radii.xl),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: Space.s5),
                        StoresSectionHeader(controller: controller),
                        const SizedBox(height: Space.s3),
                        StoresList(controller: controller),
                        const SizedBox(height: Space.s4),
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
