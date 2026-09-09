import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_stats_row.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transaction_card.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transactions_empty.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transactions_shimmer.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosOrdersView extends StatelessWidget {
  PosOrdersView({super.key});

  final PosOrdersController controller = Get.put(PosOrdersController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const PosAppBar(title: 'Transactions'),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const PosTransactionsShimmer();
              }
              final txns = controller.filteredSales;

              return CustomRefreshWrapper(
                onRefresh: controller.refreshData,
                child: txns.isEmpty
                    ? PosTransactionsEmpty()
                    : SingleChildScrollView(
                        controller: controller.scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FilterHeader(controller: controller),
                            PosStatsRow(controller: controller),
                            const Divider(
                              height: 1,
                              color: AppColors.lightGrey2,
                            ),
                            ListView.separated(
                              padding: const EdgeInsets.all(
                                AppDimen.allPadding,
                              ),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: txns.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => PosTransactionCard(
                                sale: txns[i],
                                controller: controller,
                              ),
                            ),
                            if (controller.isLoadingMore.value)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                          ],
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

class _FilterHeader extends StatelessWidget {
  final PosOrdersController controller;
  const _FilterHeader({required this.controller});

  static const _filters = ['All', 'cash', 'card', 'other'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimen.allPadding,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const CustomText(
                text: 'Transactions',
                fontFamily: AppTextStyles.headingFontFamily,
                fontSize: AppFontSize.medium,
                fontWeight: FontWeight.bold,
                color: AppColors.black2,
              ),
              _buildFilterRow(context),
            ],
          ),
          const SizedBox(height: 8),
          _DateFilterChip(controller: controller),
        ],
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
          Obx(
            () => GestureDetector(
              onTap: () => _showFilterSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(
                    AppDimen.draggableBorderRadius,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomText(
                      text: controller.paymentFilter.value == 'All'
                          ? 'All'
                          : controller.paymentFilter.value.capitalizeFirst ??
                                '',
                      fontSize: AppFontSize.verySmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Obx(
            () => GestureDetector(
              onTap: () => _showStatusFilterSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(
                    AppDimen.draggableBorderRadius,
                  ),
                  border: Border.all(color: AppColors.lightGrey2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomText(
                      text: controller.statusFilter.value == 'All'
                          ? 'Status'
                          : controller.statusFilter.value.capitalizeFirst ?? '',
                      fontSize: AppFontSize.verySmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black2,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.black2,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showStatusFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightGrey2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const CustomText(
              text: 'Filter by Status',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(height: 12),
            ...PosOrdersController.statusFilters.map(
              (s) => Obx(
                () => ListTile(
                  onTap: () {
                    controller.setStatusFilter(s);
                    Navigator.pop(context);
                  },
                  title: CustomText(
                    text: s == 'All'
                        ? 'All Statuses'
                        : (s.capitalizeFirst ?? s).replaceAll('_', ' '),
                    fontSize: AppFontSize.verySmall,
                    color: AppColors.black2,
                  ),
                  trailing: controller.statusFilter.value == s
                      ? Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryColor,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightGrey2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const CustomText(
              text: 'Filter by Payment',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(height: 12),
            ..._filters.map(
              (f) => Obx(
                () => ListTile(
                  onTap: () {
                    controller.setPaymentFilter(f);
                    Navigator.pop(context);
                  },
                  title: CustomText(
                    text: f == 'All' ? 'All Methods' : (f.capitalizeFirst ?? f),
                    fontSize: AppFontSize.verySmall,
                    color: AppColors.black2,
                  ),
                  trailing: controller.paymentFilter.value == f
                      ? Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryColor,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  final PosOrdersController controller;
  const _DateFilterChip({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now,
          initialDateRange: controller.fromDate.value != null && controller.toDate.value != null
              ? DateTimeRange(start: controller.fromDate.value!, end: controller.toDate.value!)
              : null,
        );
        if (picked != null) {
          controller.setDateRange(picked.start, picked.end);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: controller.fromDate.value != null ? AppColors.primaryColor.withOpacity(0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(AppDimen.draggableBorderRadius),
          border: Border.all(
            color: controller.fromDate.value != null ? AppColors.primaryColor : AppColors.lightGrey2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: controller.fromDate.value != null ? AppColors.primaryColor : AppColors.iosGrey,
            ),
            const SizedBox(width: 6),
            CustomText(
              text: controller.dateFilter.value,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: controller.fromDate.value != null ? AppColors.primaryColor : AppColors.black2,
            ),
            if (controller.fromDate.value != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => controller.setDateRange(null, null),
                child: Icon(Icons.close_rounded, size: 14, color: AppColors.primaryColor),
              ),
            ],
          ],
        ),
      ),
    ));
  }
}
