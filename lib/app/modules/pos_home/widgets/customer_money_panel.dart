import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G3.3 in the payment sheet: the attached customer's store credit ("Use store credit") and loyalty points ("Redeem points"). Each row
/// appears only when the store offers it and the customer has something to use, and is shown DISABLED with the reason when the till
/// is offline (these need a live balance check). The server decides every rule; the preview of what points are worth is display only.
class CustomerMoneyPanel extends StatelessWidget {
  const CustomerMoneyPanel({super.key, required this.c, required this.busy});
  final PosHomeController c;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final sc = c.saleCustomer;
      final cur = sc.cur.value ?? sc.config.value?.cur;
      final showCredit = sc.attached && sc.sameCurrency && (sc.config.value?.storeCreditTenderEnabled ?? false) && sc.customer.value?.creditBalanceMinor != null;
      // points cannot be combined with a coupon or a manual discount (the server refuses it): the row is not offered then
      final noDiscount = c.appliedCoupon.value == null && !c.isManualDiscountEntered;
      final showPoints = sc.attached && sc.pointsEnabled && noDiscount;
      if ((!showCredit && !showPoints) || cur == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.s3),
        child: AppCard(
          key: const Key('customerMoneyPanel'),
          color: p.fill,
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sc.customer.value!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.label.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: Space.s2),
              if (showCredit) _CreditRow(c: c, busy: busy, cur: cur),
              if (showCredit && showPoints) const SizedBox(height: Space.s3),
              if (showPoints) _PointsRow(c: c, busy: busy, cur: cur),
            ],
          ),
        ),
      );
    });
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.c, required this.busy, required this.cur});
  final PosHomeController c;
  final bool busy;
  final InvCur cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    // its own Obx: this widget is built after the panel's Obx closure ran, so it must watch the balance and the connection itself
    return Obx(() {
      final balance = c.saleCustomer.creditBalanceMinor;
      final reason = !c.tillOnline ? 'Needs internet' : (balance <= 0 ? 'No store credit to use' : null);
      return Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined, color: p.textSecondary),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Store credit', style: t.subtitle.copyWith(color: p.textPrimary)),
                Text(
                  reason == null ? invMoney(balance, cur) : '${invMoney(balance, cur)} · $reason',
                  key: const Key('creditBalanceText'),
                  style: t.caption.copyWith(color: reason == null ? p.textMuted : p.warningFg),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s2),
          AppButton(key: const Key('useStoreCredit'), label: 'Use', expand: false, variant: AppButtonVariant.secondary, onPressed: (busy || reason != null) ? null : c.useStoreCredit),
        ],
      );
    });
  }
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({required this.c, required this.busy, required this.cur});
  final PosHomeController c;
  final bool busy;
  final InvCur cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final sc = c.saleCustomer;
    return Obx(() {
      final online = c.tillOnline;
      final max = c.maxRedeemPoints;
      final chosen = sc.redeemPoints.value;
      final value = chosen * (sc.rules.redeemMinorPerPoint ?? 0);
      final active = online && !busy;
      return Row(
        children: [
          Icon(Icons.stars_rounded, color: p.textSecondary),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Redeem points', style: t.subtitle.copyWith(color: p.textPrimary)),
                Text(
                  online ? '${sc.points} available · 1 point = ${invMoney(sc.rules.redeemMinorPerPoint!, cur)}' : '${sc.points} available · Needs internet',
                  key: const Key('pointsAvailableText'),
                  style: t.caption.copyWith(color: online ? p.textMuted : p.warningFg),
                ),
                if (online && chosen > 0)
                  Text(
                    '−${invMoney(value, cur)} off this sale',
                    key: const Key('redeemPreview'),
                    style: t.caption.copyWith(color: p.successFg),
                  ),
                if (online && max == 0) Text('The sale is too small to use a point.', style: t.caption.copyWith(color: p.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: Space.s2),
          QuantityStepper(
            key: const Key('redeemStepper'),
            value: chosen,
            min: active ? 0 : chosen,
            max: active ? max : chosen,
            compact: true,
            onChanged: c.setRedeemPoints,
          ), // frozen while offline or charging
        ],
      );
    });
  }
}
