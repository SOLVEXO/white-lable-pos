import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/controllers/seller_pos_locations_controller.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/location_card.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/location_form_sheet.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/widgets/locations_overview_header.dart';
import 'package:solvexo_pos/core/design/design.dart';

class SellerPosLocationsView extends StatelessWidget {
  SellerPosLocationsView({super.key});

  final SellerPosLocationsController controller = Get.find();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'POS Locations',
      floatingAction: FloatingActionButton.extended(
        heroTag: 'add_location_fab',
        onPressed: () => LocationFormSheet.show(context, controller),
        backgroundColor: p.accentFill,
        foregroundColor: p.onAccentFill,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add Location', style: context.type.label.copyWith(color: p.onAccentFill)),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const SkeletonShimmer(child: SkeletonList(itemCount: 5));
        }

        if (controller.locations.isEmpty) {
          return const EmptyState(
            icon: Icons.store_mall_directory_outlined,
            title: 'No locations yet',
            message: 'Add your first branch to manage registers, employees and sales per location.',
          );
        }

        return RefreshIndicator(
          onRefresh: controller.refreshData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom room so the floating button never covers the last card.
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s16 + Space.s6),
            children: [
              LocationsOverviewHeader(overview: controller.overview.value),
              const SizedBox(height: Space.s5),
              ...controller.locations.map(
                (location) => Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
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
      destructive: true,
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
      destructive: true,
      onConfirm: () => controller.archiveLocation(location, force: true),
    );
  }
}
