import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/pos_customers_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Browse-only view of the store's real past buyers. To attach a customer
/// to the current sale, use the picker sheet from the checkout cart footer
/// instead (PosCustomerPickerSheet) — this screen is for looking someone up
/// / reviewing order history, not for driving into an active sale.
class PosCustomersView extends StatelessWidget {
  PosCustomersView({super.key});

  final PosCustomersController c = Get.put(PosCustomersController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBarTwo(
        title: 'Customers',
        color: AppColors.black2,
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryColor,
            ),
          );
        }
        if (c.customers.isEmpty) {
          return const Center(
            child: CustomText(
              text:
                  'No customers yet — they show up here after their first order.',
              fontSize: AppFontSize.small2,
              color: AppColors.iosGrey,
              textAlign: TextAlign.center,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView.separated(
            controller: c.scrollController,
            padding: const EdgeInsets.all(AppDimen.allPadding),
            itemCount: c.customers.length + (c.isLoadingMore.value ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i >= c.customers.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryColor,
                    ),
                  ),
                );
              }
              return _CustomerTile(
                customer: c.customers[i],
                currencySymbol: c.currencySymbol.value,
              );
            },
          ),
        );
      }),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerModel customer;
  final String currencySymbol;
  const _CustomerTile({required this.customer, required this.currencySymbol});

  static final _segmentColors = {
    'vip': AppColors.orange,
    'returning': AppColors.primaryColor,
    'at_risk': AppColors.red,
    'new': AppColors.green2,
  };

  @override
  Widget build(BuildContext context) {
    final segColor = _segmentColors[customer.segment] ?? AppColors.iosGrey;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: CustomText(
              text: customer.name.trim().isNotEmpty
                  ? customer.name.trim()[0].toUpperCase()
                  : '?',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: CustomText(
                        text: customer.name,
                        fontSize: AppFontSize.verySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.black2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (customer.segment != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: segColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: CustomText(
                          text: customer.segment!,
                          fontSize: AppFontSize.tiny,
                          color: segColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                CustomText(
                  text: customer.phone ?? customer.email ?? '',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.iosGrey,
                ),
              ],
            ),
          ),
          if (customer.orderCount != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CustomText(
                  text:
                      '$currencySymbol${(customer.totalSpent ?? 0).toStringAsFixed(2)}',
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black2,
                ),
                CustomText(
                  text:
                      '${customer.orderCount} order${customer.orderCount == 1 ? '' : 's'}',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.iosGrey,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
