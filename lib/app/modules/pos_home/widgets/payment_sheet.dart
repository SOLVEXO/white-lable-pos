import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart' show ConnectorUiStore, TerminalField;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cart_removal_undo.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cash_suggestions.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/qr_availability.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cash_keypad.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/customer_money_panel.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart' show invMoney;
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

  static const _icons = {
    PosPaymentMethod.cash: Icons.payments_outlined,
    PosPaymentMethod.card: Icons.credit_card_rounded,
    PosPaymentMethod.other: Icons.account_balance_outlined,
    PosPaymentMethod.raastQr: Icons.qr_code_2_rounded,
    PosPaymentMethod.storeCredit: Icons.account_balance_wallet_outlined,
  };

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
                CustomerMoneyPanel(c: c, busy: busy),
              ],
            );
            final right = split
                ? _SplitPanel(c: c, busy: busy)
                : (method == PosPaymentMethod.cash ? _CashEntry(c: c, busy: busy) : (method == PosPaymentMethod.raastQr ? _QrHint(c: c) : _ReferenceField(c: c, method: method)));
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
    return Obx(() {
      final qr = c.qrAvailability; // reads the store flag, the network and the role: all observable
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final m in PosPaymentMethod.tiles) ...[
                if (m != PosPaymentMethod.tiles.first) const SizedBox(width: Space.s2),
                Expanded(child: _tile(context, p, m, enabled: m != PosPaymentMethod.raastQr || qr.isAvailable)),
              ],
            ],
          ),
          if (!qr.isAvailable)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Row(
                key: const Key('qrUnavailableNote'),
                children: [
                  Icon(qr.availability == QrAvailability.needsInternet ? Icons.cloud_off_rounded : Icons.lock_outline_rounded, size: 16, color: p.textMuted),
                  const SizedBox(width: Space.s2),
                  Expanded(child: Text('Raast QR: ${qr.message}', style: context.type.caption.copyWith(color: p.textSecondary))),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _tile(BuildContext context, AppPalette p, String m, {required bool enabled}) {
    final on = m == selected;
    final off = busy || !enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AppCard(
        key: Key('method-$m'),
        color: on ? p.accentSoft : p.surface,
        radius: Radii.rMd,
        padding: const EdgeInsets.symmetric(vertical: Space.s3, horizontal: Space.s1),
        semanticLabel: '${PosPaymentMethod.label(m)}${on ? ', selected' : ''}${enabled ? '' : ', unavailable'}',
        onTap: off ? null : () => c.selectPayment(m),
        child: Column(
          children: [
            Icon(PaymentSheet._icons[m] ?? Icons.payments_outlined, color: on ? p.accentFg : p.textSecondary),
            const SizedBox(height: Space.s1),
            FittedBox(fit: BoxFit.scaleDown, child: Text(PosPaymentMethod.label(m), maxLines: 1, style: context.type.label.copyWith(color: on ? p.accentFg : p.textPrimary))), // four tiles: shrink a long label rather than cut it
          ],
        ),
      ),
    );
  }
}

/// What the cashier sees instead of the reference field when Raast QR is the method.
class _QrHint extends StatelessWidget {
  const _QrHint({required this.c});
  final PosHomeController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: AppCard(
        key: const Key('qrHint'),
        color: p.infoSoft,
        radius: Radii.rMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.qr_code_2_rounded, color: p.infoFg),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'A QR code is shown for the customer to scan with their bank app. The sale is completed only after the payment is confirmed.',
                style: context.type.bodySmall.copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => Obx(() {
    // G5.4: the store takes cards on a separate bank terminal → the slip's approval code (required), last 4 digits and terminal name
    if (method == PosPaymentMethod.card && c.cardExternalTerminal.value) return _CardTerminalFields(c: c);
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: AppTextField(
        key: const Key('paymentReference'),
        label: method == PosPaymentMethod.card ? 'Card auth code (optional)' : 'Reference / transaction # (optional)',
        controller: c.paymentReferenceController,
        prefixIcon: Icons.tag_rounded,
        textInputAction: TextInputAction.done,
      ),
    );
  });
}

/// G5.4 / G6.1: card on an external terminal — what the slip says. Which fields, their labels, whether required and their rules come from the
/// server (`connectors.ui.cardExternalTerminal.fields`); without it the G5.4 three (approval code required, last 4, terminal).
class _CardTerminalFields extends StatelessWidget {
  const _CardTerminalFields({required this.c});
  final PosHomeController c;

  static String _label(TerminalField f) => '${f.label} (${f.required ? 'required' : 'optional'})';
  static List<TextInputFormatter> _fmt(TerminalField f) => [if (f.numeric) FilteringTextInputFormatter.digitsOnly, if (f.maxLength != null) LengthLimitingTextInputFormatter(f.maxLength)];

  @override
  Widget build(BuildContext context) {
    final ui = ConnectorUiStore.current;
    final code = ui.field('approvalCode');
    final last4 = ui.field('last4');
    final term = ui.field('terminalLabel');
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (code != null)
            AppTextField(key: const Key('cardApprovalCode'), label: _label(code), controller: c.cardApprovalController, prefixIcon: Icons.verified_rounded, textInputAction: TextInputAction.next, keyboardType: code.numeric ? TextInputType.number : null, inputFormatters: _fmt(code)),
          if (code != null) const SizedBox(height: Space.s2),
          Row(children: [
            if (last4 != null)
              Expanded(child: AppTextField(key: const Key('cardLast4'), label: _label(last4), controller: c.cardLast4Controller, prefixIcon: Icons.credit_card_rounded, keyboardType: last4.numeric ? TextInputType.number : null, inputFormatters: _fmt(last4))),
            if (last4 != null && term != null) const SizedBox(width: Space.s2),
            if (term != null)
              Expanded(child: AppTextField(key: const Key('cardTerminal'), label: term.label, controller: c.cardTerminalController, prefixIcon: Icons.point_of_sale_rounded, textInputAction: TextInputAction.done, inputFormatters: _fmt(term))),
          ]),
        ],
      ),
    );
  }
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
          if (c.storeCreditIssue != null) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(c.storeCreditIssue!, key: const Key('storeCreditIssue'), style: context.type.caption.copyWith(color: p.dangerFg))),
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
                for (final m in c.splitChoicesFor(index)) ...[
                  if (m != c.splitChoicesFor(index).first) const SizedBox(width: Space.s2),
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
              helperText: method == PosPaymentMethod.storeCredit && c.saleCustomer.cur.value != null ? 'Balance ${invMoney(c.saleCustomer.creditBalanceMinor, c.saleCustomer.cur.value!)}' : null,
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
            if (method != PosPaymentMethod.cash && method != PosPaymentMethod.raastQr && method != PosPaymentMethod.storeCredit) ...[
              const SizedBox(height: Space.s2),
              Obx(() => AppTextField(key: Key('splitRef-$index'), label: c.cardExternalTerminal.value && line.method.value == PosPaymentMethod.card ? 'Approval code (required)' : 'Reference (optional)', controller: line.reference, prefixIcon: Icons.tag_rounded)),
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
    if (c.hasQrLine) return 'Show QR · ${Money.format(c.total)}';
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
