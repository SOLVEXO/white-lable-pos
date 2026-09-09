import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/pos_inventory_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosInventoryView extends StatelessWidget {
  PosInventoryView({super.key});

  final PosInventoryController c = Get.put(PosInventoryController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Inventory',
        color: AppColors.black2,
        actions: [
          GestureDetector(
            onTap: () => Get.toNamed(Routes.posStockActivity),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.history_rounded, color: AppColors.primaryColor, size: 22),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Obx(() => _StatsHeader(stats: c.stats.value)),
        _LowStockToggle(c: c),
        Expanded(
          child: Obx(() {
            if (c.isLoading.value) {
              return Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor));
            }
            if (c.showLowStockOnly.value) {
              return _LowStockList(c: c);
            }
            return _InventoryList(c: c);
          }),
        ),
      ]),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final InventoryStats? stats;
  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(AppDimen.allPadding, 8, AppDimen.allPadding, 12),
      child: Row(children: [
        Expanded(child: _StatChip(label: 'Products', value: '${stats!.totalProducts}', color: AppColors.primaryColor)),
        Expanded(child: _StatChip(label: 'In Stock', value: '${stats!.inStock}', color: AppColors.green2)),
        Expanded(child: _StatChip(label: 'Low Stock', value: '${stats!.lowStock}', color: AppColors.orange)),
        Expanded(child: _StatChip(label: 'Out', value: '${stats!.outOfStock}', color: AppColors.red)),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      CustomText(text: value, fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: color),
      CustomText(text: label, fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
    ]);
  }
}

class _LowStockToggle extends StatelessWidget {
  final PosInventoryController c;
  const _LowStockToggle({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(AppDimen.allPadding, 0, AppDimen.allPadding, 10),
      child: Obx(() => GestureDetector(
        onTap: c.toggleLowStockOnly,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: c.showLowStockOnly.value ? AppColors.orange.withOpacity(0.12) : AppColors.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.showLowStockOnly.value ? AppColors.orange : AppColors.lightGrey2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: c.showLowStockOnly.value ? AppColors.orange : AppColors.iosGrey),
            const SizedBox(width: 6),
            CustomText(
              text: 'Low Stock Only',
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: c.showLowStockOnly.value ? AppColors.orange : AppColors.black2,
            ),
          ]),
        ),
      )),
    );
  }
}

class _InventoryList extends StatelessWidget {
  final PosInventoryController c;
  const _InventoryList({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.products.isEmpty) {
        return const Center(
          child: CustomText(text: 'No products found.', fontSize: AppFontSize.small2, color: AppColors.iosGrey),
        );
      }
      return RefreshIndicator(
        onRefresh: c.refreshData,
        color: AppColors.primaryColor,
        child: ListView.separated(
          controller: c.scrollController,
          padding: const EdgeInsets.all(AppDimen.allPadding),
          itemCount: c.products.length + (c.isLoadingMore.value ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i >= c.products.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor)),
              );
            }
            return _InventoryTile(product: c.products[i], c: c);
          },
        ),
      );
    });
  }
}

class _InventoryTile extends StatelessWidget {
  final InventoryProductSummary product;
  final PosInventoryController c;
  const _InventoryTile({required this.product, required this.c});

  Color get _statusColor {
    switch (product.stockStatus) {
      case 'out_of_stock':
        return AppColors.red;
      case 'low_stock':
        return AppColors.orange;
      default:
        return AppColors.green2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => c.openAdjustStock(product.productId, product.name),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomText(
                text: product.name,
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.w600,
                color: AppColors.black2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              CustomText(
                text: product.hasSingleVariant ? product.sku : '${product.sku} · ${product.variantCount} variants',
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: CustomText(
              text: '${product.stock} in stock',
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: _statusColor,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.lightGrey5, size: 20),
        ]),
      ),
    );
  }
}

class _LowStockList extends StatelessWidget {
  final PosInventoryController c;
  const _LowStockList({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.lowStockItems.isEmpty) {
        return const Center(
          child: CustomText(text: 'Nothing is low on stock. 🎉', fontSize: AppFontSize.small2, color: AppColors.iosGrey),
        );
      }
      return RefreshIndicator(
        onRefresh: c.refreshData,
        color: AppColors.primaryColor,
        child: ListView.separated(
          padding: const EdgeInsets.all(AppDimen.allPadding),
          itemCount: c.lowStockItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final item = c.lowStockItems[i];
            return GestureDetector(
              onTap: () => c.openAdjustStock(item.productId, item.name),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(children: [
                  Expanded(
                    child: CustomText(text: item.name, fontSize: AppFontSize.verySmall, fontWeight: FontWeight.w600, color: AppColors.black2),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: CustomText(text: '${item.stock} left', fontSize: AppFontSize.tiny, fontWeight: FontWeight.w600, color: AppColors.orange),
                  ),
                ]),
              ),
            );
          },
        ),
      );
    });
  }
}
