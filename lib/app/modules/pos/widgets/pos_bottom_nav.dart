import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosBottomNav extends StatelessWidget {
  const PosBottomNav({super.key});

  static const _items = [
    _NavItem(icon: AppIcons.saleIcon, label: 'Sale'),
    _NavItem(icon: AppIcons.ordersIcon, label: 'Orders'),
    _NavItem(icon: AppIcons.shoppingBag, label: 'Products'),
    _NavItem(icon: AppIcons.settingIcon, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final controller = Get.find<PosBottomNavController>();
    return Obx(() {
      final activeTab = controller.selectedIndex.value;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.gray600.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = activeTab == i;
              final color = isActive
                  ? AppColors.primaryColor
                  : AppColors.inactiveGrey;
              return Expanded(
                child: InkWell(
                  onTap: () => controller.changeTab(i),
                  splashColor: AppColors.primaryColor.withOpacity(0.1),
                  highlightColor: AppColors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgIcon(assetName: item.icon, color: color, size: 22),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        height: 4,
                        width: 20,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: isActive
                              ? AppColors.primaryColor
                              : AppColors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      );
    });
  }
}

class _NavItem {
  final String icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
