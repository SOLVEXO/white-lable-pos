import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/controllers/pos_held_sales_controller.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/widgets/pos_held_sales_shimmer.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart' show PosPaymentMethod;
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosHeldSalesView extends StatelessWidget {
  PosHeldSalesView({super.key});

  final PosHeldSalesController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Held Sales',
        color: AppColors.black2,
        actions: [
          GestureDetector(
            onTap: c.loadHeldSales,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.refresh_rounded,
                  color: AppColors.primaryColor, size: 22),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosHeldSalesShimmer();
        }
        if (c.heldSales.isEmpty) {
          return _EmptyState();
        }
        return RefreshIndicator(
          onRefresh: c.loadHeldSales,
          color: AppColors.primaryColor,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: c.heldSales.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _HeldSaleTile(
              sale: c.heldSales[i],
              c: c,
            ),
          ),
        );
      }),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.pause_circle_outline_rounded,
              size: 40, color: AppColors.primaryColor),
        ),
        const SizedBox(height: 18),
        const CustomText(
          text: 'No Held Sales',
          fontSize: AppFontSize.medium,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const SizedBox(height: 8),
        const CustomText(
          text: 'Sales you put on hold will appear here.',
          fontSize: AppFontSize.verySmall,
          color: AppColors.iosGrey,
        ),
      ]),
    );
  }
}

// ── Individual held sale tile ────────────────────────────────────────────────
class _HeldSaleTile extends StatelessWidget {
  final PosSaleModel sale;
  final PosHeldSalesController c;
  const _HeldSaleTile({required this.sale, required this.c});

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(sale.createdAt);
    final isProcessing = c.processingId.value == sale.id;

    return Obx(() => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ────────────────────────────────────────────
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.pause_rounded,
                color: AppColors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomText(
                text: sale.customerName.isEmpty ||
                    sale.customerName == 'Walk-in'
                    ? 'Walk-in Customer'
                    : sale.customerName,
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.bold,
                color: AppColors.black2,
              ),
              CustomText(
                text: dateStr,
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomText(
              text: '\$${sale.total.toStringAsFixed(2)}',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.orange,
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // ── Items summary ─────────────────────────────────────────
        if (sale.items.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: sale.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
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
                    text: '×${item.qty}  \$${item.lineTotal.toStringAsFixed(2)}',
                    fontSize: AppFontSize.tiny,
                    color: AppColors.iosGrey,
                  ),
                ]),
              )).toList()
              ..addAll(sale.items.length > 3
                  ? [Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CustomText(
                        text: '+${sale.items.length - 3} more items',
                        fontSize: AppFontSize.tiny,
                        color: AppColors.iosGrey,
                      ),
                    )]
                  : []),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Payment method chip ────────────────────────────────────
        Row(children: [
          const Icon(Icons.payment_rounded, size: 14, color: AppColors.iosGrey),
          const SizedBox(width: 4),
          CustomText(
            text: sale.paymentMethod.capitalizeFirst ?? sale.paymentMethod,
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
          if (sale.notes.isNotEmpty) ...[
            const SizedBox(width: 10),
            const Icon(Icons.note_outlined, size: 14, color: AppColors.iosGrey),
            const SizedBox(width: 4),
            Expanded(
              child: CustomText(
                text: sale.notes,
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.lightGrey2),
        const SizedBox(height: 10),

        // ── Action buttons ─────────────────────────────────────────
        isProcessing
            ? Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primaryColor),
                ),
              )
            : Row(children: [
                // Resume
                Expanded(
                  flex: 2,
                  child: _ActionBtn(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    bgColor: AppColors.primaryColor.withOpacity(0.1),
                    textColor: AppColors.primaryColor,
                    onTap: () => c.resumeSale(sale),
                  ),
                ),
                const SizedBox(width: 8),
                // Complete
                Expanded(
                  flex: 2,
                  child: _ActionBtn(
                    label: 'Complete',
                    icon: Icons.check_circle_outline_rounded,
                    bgColor: AppColors.green2.withOpacity(0.1),
                    textColor: AppColors.green2,
                    onTap: () => _pickPaymentAndComplete(context, sale),
                  ),
                ),
                const SizedBox(width: 8),
                // Discard
                Expanded(
                  flex: 1,
                  child: _ActionBtn(
                    label: 'Discard',
                    icon: Icons.delete_outline_rounded,
                    bgColor: AppColors.red.withOpacity(0.08),
                    textColor: AppColors.red,
                    onTap: () => _confirmAction(
                      context,
                      title: 'Discard Sale',
                      body: 'This will permanently delete the held sale.',
                      confirmLabel: 'Discard',
                      confirmColor: AppColors.red,
                      onConfirm: () => c.discardSale(sale),
                    ),
                  ),
                ),
              ]),
      ]),
    ));
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('MMM d, h:mm a').format(dt.toLocal());
  }

  void _pickPaymentAndComplete(BuildContext context, PosSaleModel sale) {
    final selected = ValueNotifier<String>(sale.paymentMethod);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CustomText(
              text: 'Complete Sale',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(height: 4),
            CustomText(
              text: 'Total: \$${sale.total.toStringAsFixed(2)} — choose the payment method used.',
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<String>(
              valueListenable: selected,
              builder: (_, method, __) => Row(
                children: PosPaymentMethod.all.map((m) {
                  final isSelected = method == m;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => selected.value = m,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primaryColor : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryColor : AppColors.lightGrey2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: CustomText(
                            text: PosPaymentMethod.label(m),
                            fontSize: AppFontSize.verySmall,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.white : AppColors.iosGrey,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Complete Sale',
              backgroundColor: AppColors.green2,
              height: 50,
              onPressed: () {
                Navigator.pop(sheetContext);
                c.completeSale(sale, paymentMethod: selected.value);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) {
    CustomConfirmDialog.show(
      context,
      title: title,
      message: body,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      onConfirm: onConfirm,
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 4),
          CustomText(
            text: label,
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ]),
      ),
    );
  }
}
