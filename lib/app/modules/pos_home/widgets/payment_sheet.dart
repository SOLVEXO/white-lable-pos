import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cash_suggestions.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cash_keypad.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Take payment: method tiles, cash received with a keypad and quick amounts, change due (from the controller's
/// `paymentCheck`), split tender, and the Charge button. It only drives existing controller members —
/// `selectPayment`, `tenderedController`, `paymentReferenceController`, `toggleSplitPayment`, `splitLines`,
/// `fillRemaining`, `canCharge` and finally `completeSale()`.
///
/// `completeSale()` closes the top route with `Get.back()`, so Charge only ever runs from here, with this sheet on top.
/// While a charge is in flight the sheet cannot be dismissed. On success / queued-offline the controller pops it and
/// the [SaleSuccessView] opens; on a failure the sheet stays so the cashier can retry (same sale, same key).
class PaymentSheet extends StatelessWidget {
  const PaymentSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(PaymentSheet(c: c), isDismissible: false, enableDrag: false, scrollable: false, maxWidth: 780);

  static const _icons = {PosPaymentMethod.cash: Icons.payments_outlined, PosPaymentMethod.card: Icons.credit_card_rounded, PosPaymentMethod.other: Icons.account_balance_outlined};

  Future<void> _charge() async {
    CartRemovalUndo.of(c).invalidate();
    await c.completeSale();
    // Only a sale that was accepted (or saved offline) sets lastOutcome — a failure leaves it null and shows nothing.
    if (c.lastOutcome.value != null) {
      Get.to<void>(() => SaleSuccessView(c: c), transition: Transition.fadeIn, duration: const Duration(milliseconds: 280));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final busy = c.isChargingOrHolding.value;
      final split = c.isSplitPayment.value;
      final method = c.selectedPayment.value;
      return PopScope(
        canPop: !busy,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 640;
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DueHeader(c: c, busy: busy),
                const SizedBox(height: Space.s4),
                if (!split) _MethodTiles(c: c, busy: busy, selected: method),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('splitToggle'),
                    onPressed: busy ? null : c.toggleSplitPayment,
                    style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: context.palette.accentFg),
                    icon: Icon(split ? Icons.call_merge_rounded : Icons.call_split_rounded, size: 18),
                    label: Text(split ? 'Single payment' : 'Split payment', style: context.type.label.copyWith(color: context.palette.accentFg)),
                  ),
                ),
              ],
            );
            final right = split
                ? _SplitPanel(c: c, busy: busy)
                : (method == PosPaymentMethod.cash ? _CashEntry(c: c, busy: busy) : _ReferenceField(c: c, method: method));
            final charge = _ChargeButton(c: c, busy: busy, onCharge: _charge);
            // The Charge button is pinned below the scrolling body so it is always reachable, whatever the screen height.
            Widget pinned(Widget body) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(child: SingleChildScrollView(child: body)),
                const SizedBox(height: Space.s3),
                charge,
              ],
            );
            if (wide) {
              return pinned(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: Space.s6), Expanded(child: right)]));
            }
            return pinned(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, right]));
          },
        ),
      );
    });
  }
}

class _DueHeader extends StatelessWidget {
  const _DueHeader({required this.c, required this.busy});
  final PosHomeController c;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount due', style: context.type.label.copyWith(color: p.textSecondary)),
              // its own Obx: this widget's build is not inside the sheet's Obx, so reads here would never refresh
              Obx(() => AmountText(Money.format(c.total), style: context.type.amountXl)),
            ],
          ),
        ),
        IconButton(
          key: const Key('paymentClose'),
          tooltip: 'Close',
          constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
          icon: Icon(Icons.close_rounded, color: busy ? p.textMuted.withValues(alpha: 0.4) : p.textSecondary),
          onPressed: busy ? null : () => Get.back(),
        ),
      ],
    );
  }
}

class _MethodTiles extends StatelessWidget {
  const _MethodTiles({required this.c, required this.busy, required this.selected});
  final PosHomeController c;
  final bool busy;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        for (final m in c.paymentMethods) ...[
          if (m != c.paymentMethods.first) const SizedBox(width: Space.s2),
          Expanded(
            child: AppCard(
              key: Key('method-$m'),
              color: m == selected ? p.accentSoft : p.surface,
              radius: Radii.rMd,
              padding: const EdgeInsets.symmetric(vertical: Space.s3, horizontal: Space.s2),
              semanticLabel: '${PosPaymentMethod.label(m)}${m == selected ? ', selected' : ''}',
              onTap: busy ? null : () => c.selectPayment(m),
              child: Column(
                children: [
                  Icon(PaymentSheet._icons[m] ?? Icons.payments_outlined, color: m == selected ? p.accentFg : p.textSecondary),
                  const SizedBox(height: Space.s1),
                  Text(PosPaymentMethod.label(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.label.copyWith(color: m == selected ? p.accentFg : p.textPrimary)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CashEntry extends StatelessWidget {
  const _CashEntry({required this.c, required this.busy});
  final PosHomeController c;
  final bool busy;

  void _set(String text) {
    c.tenderedController.text = text;
    c.cartItems.refresh(); // the derived payment check depends on the cart's Rx — same nudge the old field gave
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final check = c.paymentCheck;
      final suggestions = CashSuggestions.forTotal(c.total, exponent: Money.exponent);
      final typed = c.tenderedController.text.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cash received', style: context.type.label.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s1),
          Container(
            key: const Key('cashReceivedDisplay'),
            padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
            decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rMd, border: Border.all(color: p.border)),
            child: Row(
              children: [
                Text(c.currencySymbol.value, style: context.type.amountMd.copyWith(color: p.textMuted)),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(typed ? c.tenderedController.text : '0', textAlign: TextAlign.end, maxLines: 1, style: context.type.amountLg.copyWith(color: typed ? p.textPrimary : p.textMuted)),
                ),
              ],
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: Space.s3),
            // One row that scrolls sideways (G1a): a Wrap grew a second line with the wider blueprint body font and pushed the
            // keypad under the Charge button on phones.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < suggestions.length; i++) ...[
                    if (i > 0) const SizedBox(width: Space.s2),
                    _QuickChip(
                      key: Key('quick-${Money.plain(suggestions[i])}'),
                      label: i == 0 ? 'Exact' : Money.format(suggestions[i]),
                      onTap: busy ? null : () => _set(Money.plain(suggestions[i])),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.s3),
          CashKeypad(controller: c.tenderedController, decimals: Money.exponent, enabled: !busy, onChanged: _set),
          const SizedBox(height: Space.s2),
          Semantics(
            liveRegion: true,
            child: !typed
                ? Text('Enter the amount received', textAlign: TextAlign.center, style: context.type.bodySmall.copyWith(color: p.textMuted))
                : (c.isCashUnderTendered
                    ? Row(
                        key: const Key('amountShort'),
                        children: [
                          Expanded(child: Text('Amount short', style: context.type.subtitle.copyWith(color: p.dangerFg))),
                          AmountText(Money.format(check.shortBy), style: context.type.amountLg, color: p.dangerFg),
                        ],
                      )
                    : Row(
                        key: const Key('changeDue'),
                        children: [
                          Expanded(child: Text('Change due', style: context.type.subtitle.copyWith(color: p.successFg))),
                          AmountText(Money.format(c.changeDue), style: context.type.amountXl, color: p.successFg),
                        ],
                      )),
          ),
        ],
      );
    });
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Cash $label',
      excludeSemantics: true,
      child: Material(
        color: p.accentSoft,
        borderRadius: Radii.rFull,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.minTouch, minWidth: Space.minTouch),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.s4), child: Center(child: Text(label, style: context.type.amountMd.copyWith(color: p.accentFg, fontWeight: FontWeight.w600)))),
          ),
        ),
      ),
    );
  }
}

class _ReferenceField extends StatelessWidget {
  const _ReferenceField({required this.c, required this.method});
  final PosHomeController c;
  final String method;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s2),
    child: AppTextField(
      key: const Key('paymentReference'),
      label: method == PosPaymentMethod.card ? 'Card auth code (optional)' : 'Reference / transaction # (optional)',
      controller: c.paymentReferenceController,
      prefixIcon: Icons.tag_rounded,
      textInputAction: TextInputAction.done,
    ),
  );
}

class _SplitPanel extends StatelessWidget {
  const _SplitPanel({required this.c, required this.busy});
  final PosHomeController c;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final check = c.paymentCheck;
      final lines = c.splitLines.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: _SplitLineCard(key: ObjectKey(lines[i]), c: c, index: i, line: lines[i], busy: busy, removable: lines.length > 1),
            ),
          if (lines.length < 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('addSplitLine'),
                onPressed: busy ? null : c.addSplitLine,
                style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Add payment', style: context.type.label.copyWith(color: p.accentFg)),
              ),
            ),
          const ReceiptDivider(),
          ReceiptRow('Paid', Money.format(check.paid)),
          if (check.nonCashExceedsTotal)
            Text('Card or other payments cannot be more than the total.', key: const Key('splitExceeds'), style: context.type.caption.copyWith(color: p.dangerFg))
          else if (!check.covered)
            ReceiptRow('Remaining', Money.format(check.shortBy), strong: true, valueColor: p.dangerFg, key: const Key('splitRemaining'))
          else if (check.change > 0)
            ReceiptRow('Change due', Money.format(check.change), strong: true, valueColor: p.successFg, key: const Key('splitChange')),
        ],
      );
    });
  }
}

class _SplitLineCard extends StatelessWidget {
  const _SplitLineCard({super.key, required this.c, required this.index, required this.line, required this.busy, required this.removable});
  final PosHomeController c;
  final int index;
  final SplitPaymentLine line;
  final bool busy;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      color: p.fill,
      radius: Radii.rMd,
      child: Obx(() {
        final method = line.method.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final m in c.paymentMethods) ...[
                  if (m != c.paymentMethods.first) const SizedBox(width: Space.s2),
                  Expanded(
                    child: _MiniChoice(
                      key: Key('split-$index-$m'),
                      label: PosPaymentMethod.label(m),
                      selected: m == method,
                      onTap: busy
                          ? null
                          : () {
                              line.method.value = m;
                              c.cartItems.refresh();
                            },
                    ),
                  ),
                ],
                if (removable)
                  IconButton(
                    key: Key('removeSplit-$index'),
                    tooltip: 'Remove payment',
                    constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
                    icon: Icon(Icons.close_rounded, color: p.textSecondary),
                    onPressed: busy ? null : () => c.removeSplitLine(index),
                  ),
              ],
            ),
            const SizedBox(height: Space.s2),
            AppTextField(
              key: Key('splitAmount-$index'),
              label: method == PosPaymentMethod.cash ? 'Cash handed over' : 'Amount',
              controller: line.amount,
              mono: true,
              prefixIcon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => c.cartItems.refresh(),
              suffix: TextButton(
                key: Key('fillRemaining-$index'),
                onPressed: busy ? null : () => c.fillRemaining(index),
                style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                child: Text('Fill rest', style: context.type.label.copyWith(color: p.accentFg)),
              ),
            ),
            if (method != PosPaymentMethod.cash) ...[
              const SizedBox(height: Space.s2),
              AppTextField(key: Key('splitRef-$index'), label: 'Reference (optional)', controller: line.reference, prefixIcon: Icons.tag_rounded),
            ],
          ],
        );
      }),
    );
  }
}

class _MiniChoice extends StatelessWidget {
  const _MiniChoice({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.accentSoft : p.surface,
        shape: RoundedRectangleBorder(borderRadius: Radii.rFull, side: BorderSide(color: selected ? p.accent : p.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(height: 40, child: Center(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.caption.copyWith(color: selected ? p.accentFg : p.textSecondary, fontWeight: FontWeight.w700)))),
        ),
      ),
    );
  }
}

class _ChargeButton extends StatelessWidget {
  const _ChargeButton({required this.c, required this.busy, required this.onCharge});
  final PosHomeController c;
  final bool busy;
  final Future<void> Function() onCharge;

  String _label() {
    if (!c.hasItems) return 'Add items';
    if (c.isDiscountInvalid) return 'Discount too large';
    if (c.isCashUnderTendered) return c.isSplitPayment.value ? 'Payments short' : 'Enter full amount';
    return 'Charge ${Money.format(c.total)}';
  }

  @override
  Widget build(BuildContext context) => Obx(
    // reads the controller's live state (cart, tendered cash, split lines): needs its own Obx
    () => AppButton(
      key: const Key('confirmCharge'),
      label: _label(),
      size: AppButtonSize.lg,
      loading: busy,
      onPressed: (c.canCharge && !busy) ? onCharge : null,
    ),
  );
}
