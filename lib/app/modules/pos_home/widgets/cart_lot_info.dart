import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G3.2: the lot a cart line would be taken from ("Lot LOT-SOON · expires in 3 d", "+ 1 from LOT-LATER"), an amber badge when the nearest
/// lot expires within a week, and — when the sellable units do not cover the quantity but expired ones exist — the manager-approved
/// "Sell expired stock" action. Offline it shows the last remembered suggestion ("as of …") and no override: it never blocks a sale.
class CartLotInfo extends StatelessWidget {
  const CartLotInfo({super.key, required this.c, required this.item});
  final PosHomeController c;
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      final preview = item.lotPreview.value;
      final approved = item.sellExpired.value;
      if (preview == null && !approved) return const SizedBox.shrink();
      final live = item.lotPreviewLive.value;
      final spill = preview != null && preview.qty == item.quantity.value ? preview.spill : null;
      final soon = preview?.expiresWithin(7) ?? false;
      final canAsk = live && c.tillOnline && !approved && (preview?.needsExpiredOverride ?? false);
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview?.headline != null)
              Text(
                [preview!.headline!, ?spill].join(' '),
                key: Key('lotLine_${item.cartKey}'),
                style: t.caption.copyWith(color: soon ? p.warningFg : p.textSecondary),
              ),
            if (preview != null && !live && preview.asOf != null)
              Text(
                'Suggested lot as of ${invDateTime(preview.asOf)}',
                key: Key('lotAsOf_${item.cartKey}'),
                style: t.caption.copyWith(color: p.textMuted),
              ),
            if (soon)
              const Padding(
                padding: EdgeInsets.only(top: Space.s1),
                child: StatusBadge('Expiring soon', tone: StatusTone.warning, icon: Icons.hourglass_bottom_rounded),
              ),
            if (canAsk) ...[
              const SizedBox(height: Space.s1),
              Text('Only ${preview!.qty - preview.shortBy} sellable; ${preview.expiredUnits} expired.', style: t.caption.copyWith(color: p.dangerFg)),
              const SizedBox(height: Space.s1),
              AppButton(
                key: Key('sellExpired_${item.cartKey}'),
                label: 'Sell expired stock (manager)',
                icon: Icons.lock_person_outlined,
                variant: AppButtonVariant.secondary,
                expand: false,
                loading: c.isApprovingExpired.value,
                onPressed: () => c.approveSellExpired(item),
              ),
            ],
            if (approved)
              Row(
                children: [
                  const Flexible(
                    child: StatusBadge('Expired stock approved', tone: StatusTone.danger, icon: Icons.verified_user_outlined),
                  ),
                  TextButton(
                    key: Key('withdrawExpired_${item.cartKey}'),
                    onPressed: () => c.withdrawSellExpired(item),
                    style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                    child: Text('Undo', style: t.label.copyWith(color: p.accentFg)),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }
}
