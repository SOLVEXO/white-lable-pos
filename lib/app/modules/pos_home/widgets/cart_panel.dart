import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/coupon_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/custom_item_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/discount_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/hold_confirm_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/payment_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The current sale as a receipt: header (count, clear), the lines (swipe to remove, +/− steppers), customer and
/// discount, totals, and the Hold / Charge actions. Used as the right-hand pane on tablets and inside the phone's
/// expandable cart sheet. Charge opens the payment sheet; Hold opens a confirm sheet — so the controller's own
/// `Get.back()` always pops that sheet, never the POS screen underneath.
class CartPanel extends StatelessWidget {
  const CartPanel({super.key, required this.c, this.cartIconKey, this.perforated = true});
  final PosHomeController c;

  /// Target of the fly-to-cart dot (tablet pane); on a phone the total pill carries it instead.
  final GlobalKey? cartIconKey;
  final bool perforated;

  @override
  Widget build(BuildContext context) {
    return ReceiptPanel(
      perforatedTop: perforated,
      perforatedBottom: perforated,
      header: _CartHeader(c: c, iconKey: cartIconKey),
      body: Obx(() {
        if (c.cartItems.isEmpty) {
          return const EmptyState(icon: Icons.shopping_bag_outlined, title: 'Cart is empty', message: 'Tap a product to add it to the sale.');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          itemCount: c.cartItems.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: context.palette.border),
          itemBuilder: (_, i) {
            final item = c.cartItems[i];
            return CartLine(key: ObjectKey(item), c: c, item: item);
          },
        );
      }),
      footer: CartFooter(c: c),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.c, this.iconKey});
  final PosHomeController c;
  final GlobalKey? iconKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s2),
      child: Row(
        children: [
          Container(
            key: iconKey,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.shopping_bag_outlined, size: 20, color: p.accentFg),
          ),
          const SizedBox(width: Space.s3),
          Expanded(child: Text('Current sale', style: context.type.title.copyWith(color: p.textPrimary))),
          Obx(
            () => c.itemCount == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: Space.s1),
                    child: StatusBadge('${c.itemCount} ${c.itemCount == 1 ? 'item' : 'items'}', tone: StatusTone.accent),
                  ),
          ),
          Obx(
            () => IconButton(
              key: const Key('clearCartButton'),
              tooltip: 'Clear cart',
              constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
              icon: Icon(Icons.delete_outline_rounded, color: c.hasItems ? p.textSecondary : p.textMuted.withValues(alpha: 0.4)),
              onPressed: c.hasItems ? () => _confirmClear(context) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await AppDialog.confirm(context, title: 'Clear the cart?', message: 'All items in this sale will be removed.', confirmLabel: 'Clear cart', destructive: true);
    if (ok) {
      CartRemovalUndo.of(c).invalidate();
      c.clearSale();
    }
  }
}

/// One cart line: swipe left to remove (with Undo), or use the stepper. Its `Obx` reads only this line's quantity.
class CartLine extends StatelessWidget {
  const CartLine({super.key, required this.c, required this.item});
  final PosHomeController c;
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final undo = CartRemovalUndo.of(c);
    return Dismissible(
      key: ObjectKey(item),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.s5),
        color: p.dangerSoft,
        child: Icon(Icons.delete_outline_rounded, color: p.dangerFg),
      ),
      onDismissed: (_) => undo.remove(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Obx(() {
          final qty = item.quantity.value;
          final variantLabel = item.product.hasMultipleVariants ? item.variant?.label : null;
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.type.subtitle.copyWith(color: p.textPrimary)),
                    if (variantLabel != null && variantLabel.isNotEmpty) Text(variantLabel, style: context.type.caption.copyWith(color: p.textMuted)),
                    if (item.isCustom)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Custom item${item.taxCategory == 'exempt' ? ' · tax exempt' : ''}', key: const Key('customLineTag'), style: context.type.caption.copyWith(color: p.accentFg)),
                      ),
                    const SizedBox(height: 2),
                    Text('${Money.format(item.unitPrice)} each', style: context.type.amountMd.copyWith(fontSize: 12, color: p.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: Space.s2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Money.format(item.lineTotal), style: context.type.amountMd.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600)),
                  QuantityStepper(
                    key: ValueKey('stepper-${item.cartKey}'),
                    value: qty,
                    min: 0,
                    compact: true,
                    onChanged: (v) {
                      if (v > qty) {
                        c.increment(item);
                      } else if (qty <= 1) {
                        undo.remove(item); // the last unit: same as removing the line, with Undo
                      } else {
                        c.decrement(item);
                      }
                    },
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Customer, discount, totals and the Hold / Charge buttons.
class CartFooter extends StatelessWidget {
  const CartFooter({super.key, required this.c});
  final PosHomeController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s4),
      child: Obx(() {
        final totals = c.totals;
        final blockedDiscount = c.isDiscountBlocked;
        final badDiscount = c.isDiscountInvalid;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _ActionChip(key: const Key('customItemButton'), icon: Icons.edit_note_rounded, label: 'Custom item', onPressed: c.isChargingOrHolding.value ? null : () => CustomItemSheet.open(c))),
                const SizedBox(width: Space.s2),
                Expanded(child: _ActionChip(key: const Key('couponButton'), icon: Icons.sell_rounded, label: c.appliedCoupon.value == null ? 'Coupon' : c.appliedCoupon.value!.code, active: c.appliedCoupon.value != null, onPressed: (!c.hasItems || c.isChargingOrHolding.value) ? null : () => CouponSheet.open(c))),
                const SizedBox(width: Space.s2),
                Expanded(child: _ActionChip(key: const Key('discountSheetButton'), icon: Icons.percent_rounded, label: 'Discount', onPressed: (!c.hasItems || c.isChargingOrHolding.value) ? null : () => DiscountSheet.open(c))),
              ],
            ),
            const SizedBox(height: Space.s2),
            AppTextField(
              key: const Key('customerField'),
              label: 'Customer (optional)',
              hint: 'Walk-in',
              controller: c.customerController,
              prefixIcon: Icons.person_outline_rounded,
              onChanged: c.onCustomerTextChanged,
              suffix: IconButton(
                key: const Key('customerPickerButton'),
                tooltip: 'Choose a customer',
                constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
                icon: Icon(Icons.person_search_rounded, color: p.accentFg),
                onPressed: c.openCustomerPicker,
              ),
            ),
            const SizedBox(height: Space.s2),
            Opacity(
              opacity: (c.isManager.value && c.appliedCoupon.value == null) ? 1 : 0.5,
              child: IgnorePointer(
                ignoring: !c.isManager.value || c.appliedCoupon.value != null, // a coupon and a discount cannot be combined
                child: AppTextField(
                  key: const Key('discountField'),
                  label: c.isManager.value ? (c.isPercentDiscount.value ? 'Discount (%)' : 'Discount (${c.currencySymbol.value})') : 'Discount (managers only)',
                  controller: c.discountController,
                  mono: true,
                  prefixIcon: Icons.sell_outlined,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => c.cartItems.refresh(),
                  suffix: TextButton(
                    key: const Key('discountTypeToggle'),
                    onPressed: c.toggleDiscountType,
                    style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                    child: Text(c.isPercentDiscount.value ? '%' : c.currencySymbol.value, style: t.amountMd.copyWith(color: p.accentFg, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
            if (blockedDiscount || badDiscount)
              Padding(
                padding: const EdgeInsets.only(top: Space.s1),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    blockedDiscount ? 'Only managers can apply a discount.' : 'The discount cannot be more than the subtotal.',
                    style: t.caption.copyWith(color: p.dangerFg),
                  ),
                ),
              ),
            const ReceiptDivider(),
            ReceiptRow('Subtotal', Money.format(totals.subtotal)),
            if (totals.discount > 0) ReceiptRow(c.appliedCoupon.value != null ? 'Coupon ${c.appliedCoupon.value!.code}' : 'Discount', '-${Money.format(totals.discount)}', valueColor: p.successFg),
            if (totals.tax > 0) ReceiptRow('Tax (${c.taxLabel})', '+${Money.format(totals.tax)}'),
            const ReceiptDivider(padding: EdgeInsets.symmetric(vertical: Space.s2)),
            Row(
              children: [
                Expanded(child: Text('Total', style: t.subtitle.copyWith(color: p.textPrimary))),
                AmountText(Money.format(totals.total), style: t.amountLg),
              ],
            ),
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: AppButton(
                    key: const Key('holdButton'),
                    label: 'Hold',
                    icon: Icons.pause_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: (!c.hasItems || c.isChargingOrHolding.value || blockedDiscount) ? null : () => HoldConfirmSheet.open(c),
                  ),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  flex: 3,
                  child: AppButton(
                    key: const Key('chargeButton'),
                    label: _label(),
                    size: AppButtonSize.lg,
                    onPressed: (!c.hasItems || badDiscount || blockedDiscount || PosEntitlementService.isRestricted || c.isChargingOrHolding.value) ? null : () => PaymentSheet.open(c),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }

  String _label() {
    if (!c.hasItems) return 'Add items';
    if (c.isDiscountInvalid) return 'Discount too large';
    return 'Charge ${Money.format(c.total)}';
  }
}


/// A compact tap target for the cart's quick actions (custom item / coupon / discount): the whole label always shows.
class _ActionChip extends StatelessWidget {
  const _ActionChip({super.key, required this.icon, required this.label, required this.onPressed, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null;
    final fg = !enabled ? p.textMuted : (active ? p.accentFg : p.textPrimary);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: active ? p.accentSoft : p.fill,
        borderRadius: Radii.rMd,
        child: InkWell(
          borderRadius: Radii.rMd,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 4),
                    Text(label, maxLines: 1, style: context.type.label.copyWith(color: fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
