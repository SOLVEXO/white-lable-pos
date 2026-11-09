import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/utils/money.dart';
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
            return Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: c.isPrinting.value ? null : c.printReceipt,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: c.isPrinting.value
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor),
                        )
                      : Icon(Icons.print_outlined, color: AppColors.primaryColor, size: 20),
                ),
              ),
              GestureDetector(
                onTap: c.isExportingPdf.value ? null : c.shareReceiptPdf,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: c.isExportingPdf.value
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor),
                        )
                      : Icon(Icons.picture_as_pdf_outlined, color: AppColors.primaryColor, size: 20),
                ),
              ),
              GestureDetector(
                onTap: c.shareReceipt,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(Icons.share_outlined, color: AppColors.primaryColor, size: 20),
                ),
              ),
            ]);
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
              _HeaderCard(sale: sale, currencySymbol: c.currencySymbol.value, offlineRef: c.offlineRef.value),
              const SizedBox(height: 16),
              _ItemsCard(sale: sale, c: c),
              const SizedBox(height: 16),
              _TotalsCard(sale: sale, currencySymbol: c.currencySymbol.value),
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
  final String currencySymbol;
  final String? offlineRef;
  const _HeaderCard({required this.sale, required this.currencySymbol, this.offlineRef});

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
        if (offlineRef != null) ...[
          const SizedBox(height: 4),
          CustomText(text: 'Offline receipt ref $offlineRef', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ],
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
            text: 'Refunded: ${Money.format(sale.refundedAmount)}',
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
    // Refund is only offered to managers, matching the backend's real,
    // signed-token-verified enforcement — see PosRole's doc comment.
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
                  text: '${Money.format(item.price)} × ${item.qty}'
                      '${item.refundedQty > 0 ? ' (${item.refundedQty} refunded)' : ''}',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.iosGrey,
                ),
              ]),
            ),
            CustomText(
              text: Money.format(item.lineTotal),
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
          ]),
        )),
      ]),
    );
  }
}


class _TotalsCard extends StatelessWidget {
  final PosSaleModel sale;
  final String currencySymbol;
  const _TotalsCard({required this.sale, required this.currencySymbol});

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
        if (sale.tax > 0)
          _row(sale.taxRate != null ? 'Tax (${(sale.taxRate! * 100).toStringAsFixed((sale.taxRate! * 100) % 1 == 0 ? 0 : 2)}%)' : 'Tax', sale.tax),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.lightGrey2)),
        _row('Total', sale.total, bold: true),
        if (!sale.isHeld) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.lightGrey2)),
          // one row per tender (split payments show each); cash also shows what was handed over
          for (final p in sale.paymentLines) ...[
            _row(PosPaymentMethodLabel.of(p.method), p.amount),
            if (p.tendered != null && p.tendered! > p.amount) _note('Tendered ${_m(p.tendered!)}'),
            if ((p.reference ?? '').isNotEmpty) _note('Ref ${p.reference}'),
          ],
          if (sale.changeGiven > 0) _row('Change given', sale.changeGiven),
        ],
        if (sale.refunds.isNotEmpty || sale.refundedAmount > 0) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: AppColors.lightGrey2)),
          for (final r in sale.refunds)
            _row(r.kind == 'full' ? 'Refund' : 'Partial refund', -r.amount, color: AppColors.red),
          if (sale.refunds.isEmpty) _row('Refunded', -sale.refundedAmount, color: AppColors.red),
          for (final r in sale.refunds)
            if (r.tenders.isNotEmpty) _note('Returned to ${r.tenders.map((t) => PosPaymentMethodLabel.of(t.method)).join(' + ')}'),
        ],
      ]),
    );
  }

  /// Always in the SALE's own currency and decimals (a sale made in another currency/exponent keeps its own).
  String _m(double v) => Money.format(v, currency: sale.currency, exponent: sale.currencyExponent);

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Align(alignment: Alignment.centerRight, child: CustomText(text: text, fontSize: AppFontSize.tiny, color: AppColors.iosGrey)),
      );

  Widget _row(String label, double amount, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        CustomText(text: label, fontSize: AppFontSize.verySmall, fontWeight: bold ? FontWeight.bold : FontWeight.w400, color: AppColors.black2),
        const Spacer(),
        CustomText(
          text: _m(amount),
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
      return Column(children: [
        if (sale.canDiscard)
          _ActionButton(
            label: 'Discard Held Sale',
            color: AppColors.red,
            onTap: () => _confirm(context, 'Discard Sale', 'Permanently delete this held sale?', c.discard),
          ),
        if (sale.status != 'held' && sale.status != 'discarded')
          _ActionButton(
            key: const Key('openTaxInvoice'),
            label: sale.invoice != null ? 'Tax invoice ${sale.invoice!.number}' : 'Tax invoice',
            color: AppColors.black2,
            outline: true,
            onTap: () => Get.toNamed(Routes.posTaxInvoice, arguments: sale.id),
          ),
        // ONE path for every refund AND void: the Return flow (credit note, approval rules, restock, void for managers).
        if (sale.canRefund || sale.canVoid)
          _ActionButton(
            key: const Key('openReturn'),
            label: 'Return or void',
            color: AppColors.red,
            outline: true,
            onTap: () => Get.toNamed(Routes.posReturn, arguments: sale.id),
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
  const _ActionButton({super.key, required this.label, required this.color, required this.onTap, this.outline = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomButton(
        label: label,
        width: double.infinity,
        height: 48,
        borderRadius: 12,
        color: outline ? AppColors.transparent : color.withOpacity(0.1),
        textColor: color,
        borderColor: outline ? color.withOpacity(0.4) : AppColors.transparent,
        onPressed: onTap,
      ),
    );
  }
}

/// Display label for a tender method (cash / card / other).
class PosPaymentMethodLabel {
  static String of(String method) => switch (method) { 'cash' => 'Cash', 'card' => 'Card', 'raast_qr' => 'Raast', _ => 'Bank / Other' };
}
