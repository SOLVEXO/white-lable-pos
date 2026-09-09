import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_stock_activity/controllers/pos_stock_activity_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Store-wide feed of stock adjustments (newest first). Not filterable to a
/// single product — the seller-facing activity-log route has no
/// targetId/targetType filter (only the admin route does), so this is a
/// store-wide history, not a per-product ledger; see
/// InventoryRepository.getStockActivity's doc comment.
class PosStockActivityView extends StatelessWidget {
  PosStockActivityView({super.key});

  final PosStockActivityController c = Get.put(PosStockActivityController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBarTwo(title: 'Stock Activity', color: AppColors.black2),
      body: Obx(() {
        if (c.isLoading.value) {
          return Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor));
        }
        if (c.entries.isEmpty) {
          return const Center(
            child: CustomText(text: 'No stock adjustments yet.', fontSize: AppFontSize.small2, color: AppColors.iosGrey),
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView.separated(
            controller: c.scrollController,
            padding: const EdgeInsets.all(AppDimen.allPadding),
            itemCount: c.entries.length + (c.isLoadingMore.value ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i >= c.entries.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor)),
                );
              }
              return _ActivityTile(entry: c.entries[i]);
            },
          ),
        );
      }),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final ActivityLogEntry entry;
  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.inventory_2_outlined, color: AppColors.orange, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CustomText(
              text: entry.description.isNotEmpty ? entry.description : entry.action,
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.black2,
            ),
            const SizedBox(height: 2),
            CustomText(
              text: '${entry.actorName.isNotEmpty ? '${entry.actorName} · ' : ''}${DateFormat('MMM d, h:mm a').format(entry.createdAt.toLocal())}',
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
          ]),
        ),
      ]),
    );
  }
}
