import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// "Hold this sale?" — always shown before `holdSale()`, because that method closes the top route with `Get.back()`:
/// with this sheet on top it is the sheet that closes, never the POS screen. While the hold is in flight the sheet
/// cannot be dismissed (the controller pops it when it finishes).
class HoldConfirmSheet extends StatelessWidget {
  const HoldConfirmSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(HoldConfirmSheet(c: c), title: 'Hold this sale?', isDismissible: false, enableDrag: false);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final busy = c.isChargingOrHolding.value;
      return PopScope(
        canPop: !busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'It is saved so you can resume it later from Held sales. The cart will be cleared.',
              style: context.type.body.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: Space.s4),
            AppCard(
              color: p.fill,
              radius: Radii.rMd,
              child: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, color: p.textSecondary),
                  const SizedBox(width: Space.s3),
                  Expanded(child: Text('${c.itemCount} ${c.itemCount == 1 ? 'item' : 'items'}', style: context.type.subtitle.copyWith(color: p.textPrimary))),
                  AmountText(Money.format(c.total), style: context.type.amountMd.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: Space.s5),
            Row(
              children: [
                Expanded(child: AppButton(key: const Key('holdCancel'), label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: busy ? null : () => Get.back())),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: AppButton(
                    key: const Key('holdConfirm'),
                    label: 'Hold sale',
                    icon: Icons.pause_rounded,
                    loading: busy,
                    onPressed: () async {
                      CartRemovalUndo.of(c).invalidate();
                      await c.holdSale(); // success / queued: clears the cart and pops THIS sheet; failure: toast, sheet stays
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}
