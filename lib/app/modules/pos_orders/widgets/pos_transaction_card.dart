import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_payment_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_status_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transaction_buttons.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosTransactionCard extends StatelessWidget {
  final PosSaleModel sale;
  final PosOrdersController controller;

  const PosTransactionCard({
    super.key,
    required this.sale,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isProcessing = controller.processingId.value == sale.id;

      return GestureDetector(
        onTap: () => controller.openSaleDetail(sale),
        child: Container(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius:
              BorderRadius.circular(AppDimen.serviceCountTileRadius),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topRow(),
            const SizedBox(height: 8),
            _metaRow(),
            if (sale.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              _itemsPreview(),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.lightGrey2),
            const SizedBox(height: 12),
            isProcessing
                ? Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryColor),
                    ),
                  )
                : PosTransactionButtons(
                    onReceipt: () => Get.toNamed(Routes.posSaleDetail, arguments: sale.id),
                    onRefund: sale.canRefund ? () => _confirmRefund(context) : null,
                    onVoid: sale.canVoid ? () => _confirmVoid(context) : null,
                  ),
          ],
        ),
        ),
      );
    });
  }

  Widget _topRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CustomText(
          text: sale.saleNumber.isNotEmpty
              ? sale.saleNumber
              : '#${sale.id.length > 8 ? sale.id.substring(sale.id.length - 8) : sale.id}',
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryColor,
        ),
        CustomText(
          text: '\$${sale.total.toStringAsFixed(2)}',
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
      ],
    );
  }

  Widget _metaRow() {
    final timeStr = DateFormat('h:mm a').format(sale.createdAt.toLocal());
    return Row(
      children: [
        CustomText(
          text: sale.customerName.isEmpty || sale.customerName == 'Walk-in'
              ? 'Walk-in'
              : sale.customerName,
          fontSize: AppFontSize.verySmall,
          color: AppColors.grey,
        ),
        const SizedBox(width: 8),
        PosPaymentBadge(method: sale.paymentMethod),
        const SizedBox(width: 8),
        PosStatusBadge(status: sale.status),
        const Spacer(),
        CustomText(
          text: timeStr,
          fontSize: AppFontSize.verySmall,
          color: AppColors.lightGrey5,
        ),
      ],
    );
  }

  Widget _itemsPreview() {
    final preview = sale.items.take(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ...preview.map((item) => Row(children: [
            Expanded(
              child: CustomText(
                text: item.name,
                fontSize: AppFontSize.tiny,
                color: AppColors.black2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CustomText(
              text: '×${item.qty}',
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
          ])),
          if (sale.items.length > 2)
            Align(
              alignment: Alignment.centerLeft,
              child: CustomText(
                text: '+${sale.items.length - 2} more',
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
              ),
            ),
        ],
      ),
    );
  }

  void _confirmRefund(BuildContext context) {
    CustomConfirmDialog.show(
      context,
      title: 'Confirm Refund',
      message: 'Refund \$${sale.total.toStringAsFixed(2)} for this sale?',
      confirmLabel: 'Refund',
      confirmColor: AppColors.red,
      onConfirm: () => controller.refundSale(sale),
    );
  }

  void _confirmVoid(BuildContext context) {
    CustomConfirmDialog.show(
      context,
      title: 'Void Sale',
      message: 'This reverses the sale entirely and restores stock. It cannot be undone.',
      confirmLabel: 'Void Sale',
      confirmColor: AppColors.iosGrey,
      onConfirm: () => controller.voidSale(sale),
    );
  }
}
