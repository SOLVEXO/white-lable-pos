import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_restricted_banner.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The POS shell: bottom bar on phones, a collapsible rail on tablets (one [AppShell]). The blueprint's five tabs — Home, Sell,
/// Orders, Stock, More — driven by [PosBottomNavController]. The More tab carries a badge with the number of offline sales
/// that still need attention (the service already counts them).
class PosMainView extends StatelessWidget {
  PosMainView({super.key});

  final controller = Get.find<PosBottomNavController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unresolved = Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>().unresolvedCount.value : 0;
      return AppShell(
        destinations: [
          const AppDestination(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
          const AppDestination(icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale_rounded, label: 'Sell'),
          const AppDestination(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Orders'),
          const AppDestination(icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded, label: 'Stock'),
          AppDestination(icon: Icons.menu_rounded, selectedIcon: Icons.menu_open_rounded, label: 'More', badge: unresolved),
        ],
        currentIndex: controller.selectedIndex.value,
        onDestinationSelected: controller.changeTab,
        topBanner: const PosRestrictedBanner(),
        railHeader: (extended) => Row(
          children: [
            const BrandLogo(size: 40),
            if (extended) ...[
              const SizedBox(width: Space.s3),
              Expanded(child: Text('Solvexo POS', maxLines: 1, overflow: TextOverflow.clip, style: context.type.title.copyWith(color: context.palette.textPrimary))),
            ],
          ],
        ),
        body: controller.screens[controller.selectedIndex.value],
      );
    });
  }
}
