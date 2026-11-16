import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_payment_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_status_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_transaction_buttons.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
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
      final p = context.palette;

      return AppCard(
        onTap: () => controller.openSaleDetail(sale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topRow(context),
            const SizedBox(height: Space.s2),
            _metaRow(context),
            if (sale.items.isNotEmpty) ...[
              const SizedBox(height: Space.s3),
              _itemsPreview(context),
            ],
            const SizedBox(height: Space.s3),
            Divider(height: 1, color: p.border),
            const SizedBox(height: Space.s3),
            isProcessing
                ? Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.accentFg),
                    ),
                  )
                : PosTransactionButtons(
                    onReceipt: () => Get.toNamed(Routes.posSaleDetail, arguments: sale.id),
                    // ONE refund/void path: the Return flow (credit note, approval rules; the server decides who may do what).
                    onReturn: (sale.canRefund || sale.canVoid) ? () => Get.toNamed(Routes.posReturn, arguments: sale.id) : null,
                  ),
          ],
        ),
      );
    });
  }

  Widget _topRow(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            sale.saleNumber.isNotEmpty
                ? sale.saleNumber
                : '#${sale.id.length > 8 ? sale.id.substring(sale.id.length - 8) : sale.id}',
            style: context.type.subtitle.copyWith(color: p.accentFg, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.s3),
        Flexible(
          child: AmountText(
            Money.format(sale.total),
            style: context.type.amountMd,
            color: p.textPrimary,
            animate: false,
            alignment: MainAxisAlignment.end,
          ),
        ),
      ],
    );
  }

  Widget _metaRow(BuildContext context) {
    final p = context.palette;
    final timeStr = DateFormat('h:mm a').format(sale.createdAt.toLocal());
    final name = Text(
      sale.customerName.isEmpty || sale.customerName == 'Walk-in'
          ? 'Walk-in'
          : sale.customerName,
      style: context.type.bodySmall.copyWith(color: p.textSecondary),
    );
    final time = Text(timeStr, style: context.type.bodySmall.copyWith(color: p.textMuted));
    final badges = [
      PosPaymentBadge(method: sale.paymentMethod),
      PosStatusBadge(status: sale.status),
    ];
    // Large text: name + time on one line, the badges on their own line below.
    if (MediaQuery.textScalerOf(context).scale(16) > 19) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: name), const SizedBox(width: Space.s2), time]),
          const SizedBox(height: Space.s1),
          Wrap(spacing: Space.s2, runSpacing: Space.s1, children: badges),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [name, ...badges],
          ),
        ),
        const SizedBox(width: Space.s2),
        time,
      ],
    );
  }

  Widget _itemsPreview(BuildContext context) {
    final p = context.palette;
    final preview = sale.items.take(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(
        color: p.fill,
        borderRadius: Radii.rSm,
      ),
      child: Column(
        children: [
          ...preview.map((item) => Row(children: [
            Expanded(
              child: Text(
                item.name,
                style: context.type.caption.copyWith(color: p.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('×${item.qty}', style: context.type.caption.copyWith(color: p.textMuted)),
          ])),
          if (sale.items.length > 2)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '+${sale.items.length - 2} more',
                style: context.type.caption.copyWith(color: p.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
