import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/controllers/seller_pos_locations_controller.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/location_card.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/location_form_sheet.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/locations_overview_header.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SellerPosLocationsView extends StatelessWidget {
  SellerPosLocationsView({super.key});

  final SellerPosLocationsController controller = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBarTwo(title: 'POS Locations'),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_location_fab',
        onPressed: () => LocationFormSheet.show(context, controller),
        backgroundColor: AppColors.primaryColor,
        icon: const Icon(Icons.add_rounded, color: AppColors.white),
        label: const CustomText(
          text: 'Add Location',
          color: AppColors.white,
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w700,
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.primaryColor),
          );
        }

        if (controller.locations.isEmpty) {
          return const _EmptyState();
        }

        return CustomRefreshWrapper(
          onRefresh: controller.refreshData,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                BaseSpacing.md, BaseSpacing.md, BaseSpacing.md, BaseSpacing.xxl * 2),
            children: [
              LocationsOverviewHeader(overview: controller.overview.value),
              SizedBox(height: BaseSpacing.md),
              ...controller.locations.map(
                (location) => Padding(
                  padding: EdgeInsets.only(bottom: BaseSpacing.sm),
                  child: LocationCard(
                    location: location,
                    stat: controller.statFor(location.id),
                    onEdit: () => LocationFormSheet.show(context, controller, existing: location),
                    onArchive: () => _confirmArchive(context, location),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _confirmArchive(BuildContext context, StoreLocationModel location) {
    CustomConfirmDialog.show(
      context,
      title: 'Archive "${location.name}"?',
      message: 'The branch will no longer be available for new registers or employees. Existing sales data is kept.',
      confirmLabel: 'Archive',
      confirmColor: AppColors.red,
      onConfirm: () async {
        final ok = await controller.archiveLocation(location);
        if (!ok && context.mounted) _confirmForceArchive(context, location);
      },
    );
  }

  void _confirmForceArchive(BuildContext context, StoreLocationModel location) {
    CustomConfirmDialog.show(
      context,
      title: 'Registers or Employees Assigned',
      message: 'This location still has registers or employees assigned. Archive anyway? They will be left unassigned, not deleted.',
      confirmLabel: 'Force Archive',
      confirmColor: AppColors.red,
      onConfirm: () => controller.archiveLocation(location, force: true),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(BaseSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 48, color: AppColors.lightGrey),
            SizedBox(height: BaseSpacing.sm),
            const CustomText(
              text: 'No locations yet',
              color: AppColors.black2,
              fontSize: AppFontSize.extraSmall,
              fontWeight: FontWeight.w600,
            ),
            SizedBox(height: BaseSpacing.xxs),
            const CustomText(
              text: 'Add your first branch to manage registers, employees and sales per location.',
              color: AppColors.gray600,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
