import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_button.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_payment_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_status_badge.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/pos_sale_detail_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSaleDetailView extends StatelessWidget {
  PosSaleDetailView({super.key});

  final PosSaleDetailController c = Get.put(PosSaleDetailController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Sale Detail',
        color: AppColors.black2,
        actions: [
          Obx(() {
            final sale = c.sale.value;
            if (sale == null) return const SizedBox.shrink();
            return GestureDetector(
              onTap: c.shareReceipt,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(Icons.share_outlined, color: AppColors.primaryColor, size: 20),
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSaleDetailShimmer();
        }
        final sale = c.sale.value;
        if (sale == null) {
          return const Center(
            child: CustomText(text: 'Sale not found.', fontSize: AppFontSize.small2, color: AppColors.iosGrey),
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            children: [
              _HeaderCard(sale: sale),
              const SizedBox(height: 16),
              _ItemsCard(sale: sale, c: c),
              const SizedBox(height: 16),
              _TotalsCard(sale: sale),
              const SizedBox(height: 20),
              _ActionsSection(sale: sale, c: c),
            ],
          ),
        );
      }),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final PosSaleModel sale;
  const _HeaderCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          CustomText(
            text: sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
          PosStatusBadge(status: sale.status),
        ]),
        const SizedBox(height: 8),
        CustomText(
          text: DateFormat('MMM d, y  h:mm a').format(sale.createdAt.toLocal()),
          fontSize: AppFontSize.tiny,
          color: AppColors.iosGrey,
        ),
        const SizedBox(height: 10),
        Row(children: [
          PosPaymentBadge(method: sale.paymentMethod),
          const SizedBox(width: 8),
          CustomText(
            text: sale.customerName.isEmpty || sale.customerName == 'Walk-in' ? 'Walk-in' : sale.customerName,
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
          ),
        ]),
        if (sale.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          CustomText(text: sale.notes, fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ],
        if (sale.isVoided) ...[
          const SizedBox(height: 8),
          CustomText(
            text: 'Voided${sale.voidedAt != null ? ' on ${DateFormat('MMM d, h:mm a').format(sale.voidedAt!.toLocal())}' : ''}',
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
        ],
        if (sale.refundedAmount > 0) ...[
          const SizedBox(height: 8),
          CustomText(
            text: 'Refunded: \$${sale.refundedAmount.toStringAsFixed(2)}',
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w600,
            color: AppColors.red,
          ),
        ],
      ]),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  final PosSaleModel sale;
  final PosSaleDetailController c;
  const _ItemsCard({required this.sale, required this.c});

  @override
  Widget build(BuildContext context) {
    final canPartialRefund = sale.canRefund;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CustomText(text: 'Items', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
        const SizedBox(height: 10),
        ...sale.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CustomText(
                  text: item.name,
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black2,
                ),
                CustomText(
                  text: '\$${item.price.toStringAsFixed(2)} × ${item.qty}'
                      '${item.refundedQty > 0 ? ' (${item.refundedQty} refunded)' : ''}',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.iosGrey,
                ),
              ]),
            ),
            CustomText(
              text: '\$${item.lineTotal.toStringAsFixed(2)}',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            if (canPartialRefund && item.saleItemId != null && item.refundableQty > 0) ...[
              const SizedBox(width: 10),
              Obx(() => _RefundStepper(
                max: item.refundableQty,
                value: c.refundSelection[item.saleItemId] ?? 0,
                onChanged: (v) => c.setRefundQty(item.saleItemId!, v),
              )),
            ],
          ]),
        )),
      ]),
    );
  }
}

class _RefundStepper extends StatelessWidget {
  final int max;
  final int value;
  final ValueChanged<int> onChanged;
  const _RefundStepper({required this.max, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: value > 0 ? () => onChanged(value - 1) : null,
        child: Icon(Icons.remove_circle_outline, size: 18, color: value > 0 ? AppColors.red : AppColors.lightGrey2),
      ),
      SizedBox(width: 20, child: Center(child: CustomText(text: '$value', fontSize: AppFontSize.tiny, color: AppColors.black2))),
      GestureDetector(
        onTap: value < max ? () => onChanged(value + 1) : null,
        child: Icon(Icons.add_circle_outline, size: 18, color: value < max ? AppColors.primaryColor : AppColors.lightGrey2),
      ),
    ]);
  }
}

class _TotalsCard extends StatelessWidget {
  final PosSaleModel sale;
  const _TotalsCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        _row('Subtotal', sale.subtotal),
        if (sale.discount > 0) _row('Discount', -sale.discount, color: AppColors.green2),
        if (sale.tax > 0) _row('Tax', sale.tax),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.lightGrey2)),
        _row('Total', sale.total, bold: true),
      ]),
    );
  }

  Widget _row(String label, double amount, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        CustomText(text: label, fontSize: AppFontSize.verySmall, fontWeight: bold ? FontWeight.bold : FontWeight.w400, color: AppColors.black2),
        const Spacer(),
        CustomText(
          text: '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}',
          fontSize: bold ? AppFontSize.small2 : AppFontSize.verySmall,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: color ?? AppColors.black2,
        ),
      ]),
    );
  }
}

class _ActionsSection extends StatelessWidget {
  final PosSaleModel sale;
  final PosSaleDetailController c;
  const _ActionsSection({required this.sale, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isProcessing.value) {
        return Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor));
      }
      final hasSelection = c.refundSelection.isNotEmpty;
      return Column(children: [
        if (sale.canDiscard)
          _ActionButton(
            label: 'Discard Held Sale',
            color: AppColors.red,
            onTap: () => _confirm(context, 'Discard Sale', 'Permanently delete this held sale?', c.discard),
          ),
        if (sale.canRefund) ...[
          if (hasSelection)
            _ActionButton(
              label: 'Refund Selected (\$${c.selectedRefundAmount.toStringAsFixed(2)})',
              color: AppColors.red,
              onTap: () => _confirm(context, 'Partial Refund',
                  'Refund \$${c.selectedRefundAmount.toStringAsFixed(2)} for the selected items?', c.refundPartial),
            ),
          _ActionButton(
            label: 'Refund Full Sale',
            color: AppColors.red,
            outline: hasSelection,
            onTap: () => _confirm(context, 'Full Refund', 'Refund the entire sale (\$${sale.total.toStringAsFixed(2)})?', c.refundFull),
          ),
        ],
        if (sale.canVoid)
          _ActionButton(
            label: 'Void Sale',
            color: AppColors.iosGrey,
            onTap: () => _confirm(context, 'Void Sale', 'This reverses the sale and restores stock. This cannot be undone.',
                () => c.voidSale()),
          ),
      ]);
    });
  }

  void _confirm(BuildContext context, String title, String body, Future<void> Function() onConfirm) {
    CustomConfirmDialog.show(
      context,
      title: title,
      message: body,
      confirmLabel: 'Confirm',
      confirmColor: AppColors.red,
      onConfirm: onConfirm,
    );
  }
}

/// A soft, tinted secondary action button — mirrors the tinted-pill style
/// already used by [PosTransactionButtons] elsewhere in the POS module,
/// built on the shared [CustomButton] component.
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool outline;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.color, required this.onTap, this.outline = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomButton(
        label: label,
        width: double.infinity,
        height: 48,
        borderRadius: 12,
        color: outline ? Colors.transparent : color.withOpacity(0.1),
        textColor: color,
        borderColor: outline ? color.withOpacity(0.4) : Colors.transparent,
        onPressed: onTap,
      ),
    );
  }
}
