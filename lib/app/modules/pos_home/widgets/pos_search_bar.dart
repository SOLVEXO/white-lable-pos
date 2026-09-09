import 'package:solvexo_pos/app/components/app_search_field.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_barcode_sheet.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosSearchBar extends StatelessWidget {
  final PosHomeController c;
  const PosSearchBar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Obx(
        () => AppSearchField(
          controller: c.searchController,
          onChanged: c.onSearchChanged,
          staticHint: 'Search products or SKU...',
          suffixIcon: c.searchText.value.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    c.searchController.clear();
                    c.onSearchChanged('');
                  },
                  child: const SvgIcon(
                    assetName: AppIcons.cross,
                    color: AppColors.textPrimary,
                  ),
                )
              : null,
          trailing: GestureDetector(
            onTap: () => Get.bottomSheet(
              PosBarcodeSheet(c: c),
              isScrollControlled: true,
              backgroundColor: AppColors.transparent,
            ),
            child: SvgIcon(
              assetName: AppIcons.barcodeIcon,
              color: AppColors.primaryColor,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
