import 'package:solvexo_pos/app/components/fiscal_status_card.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_payment_badge.dart';
import 'package:solvexo_pos/app/modules/pos_orders/widgets/pos_status_badge.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/pos_sale_detail_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSaleDetailView extends StatelessWidget {
  PosSaleDetailView({super.key});

  final PosSaleDetailController c = Get.put(PosSaleDetailController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget busy() => SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: p.accentFg),
        );
    return AppPage(
      title: 'Sale Detail',
      actions: [
        Obx(() {
          final sale = c.sale.value;
          if (sale == null) return const SizedBox.shrink();
          return Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Print receipt',
              onPressed: c.isPrinting.value ? null : c.printReceipt,
              icon: c.isPrinting.value
                  ? busy()
                  : Icon(Icons.print_outlined, color: p.accentFg, size: IconSizes.sm),
            ),
            // G5.8: view the receipt PDF in the app (print / share from the viewer)
            IconButton(
              key: const Key('saleViewPdf'),
              tooltip: 'View receipt PDF',
              onPressed: () => c.viewReceiptPdf(),
              icon: Icon(Icons.preview_outlined, color: p.accentFg, size: IconSizes.sm),
            ),
            IconButton(
              tooltip: 'Share receipt PDF',
              onPressed: c.isExportingPdf.value ? null : c.shareReceiptPdf,
              icon: c.isExportingPdf.value
                  ? busy()
                  : Icon(Icons.picture_as_pdf_outlined, color: p.accentFg, size: IconSizes.sm),
            ),
            // G5.1: share the public receipt link (share sheet)
            IconButton(
              key: const Key('saleShareLink'),
              tooltip: 'Send receipt link',
              onPressed: () => c.openSendReceipt(), // G5.3: share / WhatsApp / e-mail / SMS
              icon: Icon(Icons.link_rounded, color: p.accentFg, size: IconSizes.sm),
            ),
            IconButton(
              tooltip: 'Share receipt',
              onPressed: c.shareReceipt,
              icon: Icon(Icons.share_outlined, color: p.accentFg, size: IconSizes.sm),
            ),
            const SizedBox(width: Space.s1),
          ]);
        }),
      ],
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSaleDetailShimmer();
        }
        final sale = c.sale.value;
        if (sale == null) {
          return const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sale not found.');
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: p.accent,
          child: ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              _HeaderCard(sale: sale, currencySymbol: c.currencySymbol.value, offlineRef: c.offlineRef.value),
              const SizedBox(height: Space.s4),
              _ItemsCard(sale: sale, c: c),
              const SizedBox(height: Space.s4),
              _TotalsCard(sale: sale, currencySymbol: c.currencySymbol.value),
              const SizedBox(height: Space.s5),
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
    final p = context.palette;
    final meta = context.type.caption.copyWith(color: p.textMuted);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
              style: context.type.title.copyWith(color: p.accentFg),
            ),
          ),
          const SizedBox(width: Space.s2),
          PosStatusBadge(status: sale.status),
        ]),
        const SizedBox(height: Space.s2),
        Text(DateFormat('MMM d, y  h:mm a').format(sale.createdAt.toLocal()), style: meta),
        if (offlineRef != null) ...[
          const SizedBox(height: Space.s1),
          Text('Offline receipt ref $offlineRef', style: meta),
        ],
        const SizedBox(height: Space.s3),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PosPaymentBadge(method: sale.paymentMethod),
            Text(
              sale.customerName.isEmpty || sale.customerName == 'Walk-in' ? 'Walk-in' : sale.customerName,
              style: context.type.bodySmall.copyWith(color: p.textSecondary),
            ),
          ],
        ),
        if (sale.notes.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          Text(sale.notes, style: meta),
        ],
        if (sale.isVoided) ...[
          const SizedBox(height: Space.s2),
          Text(
            'Voided${sale.voidedAt != null ? ' on ${DateFormat('MMM d, h:mm a').format(sale.voidedAt!.toLocal())}' : ''}',
            style: meta,
          ),
        ],
        if (sale.refundedAmount > 0) ...[
          const SizedBox(height: Space.s2),
          Text(
            'Refunded: ${Money.format(sale.refundedAmount)}',
            style: context.type.caption.copyWith(color: p.dangerFg, fontWeight: FontWeight.w600),
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
    final p = context.palette;
    final meta = context.type.caption.copyWith(color: p.textMuted);
    // Refund is only offered to managers, matching the backend's real,
    // signed-token-verified enforcement — see PosRole's doc comment.
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader('Items', padding: EdgeInsets.zero),
        if (sale.priceBookName != null) Text(key: const Key('salePriceBook'), 'Priced with: ${sale.priceBookName}', style: meta),
        const SizedBox(height: Space.s3),
        ...sale.items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: Space.s3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  item.name,
                  style: context.type.body.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${Money.format(item.price)} × ${item.qty}'
                      '${item.refundedQty > 0 ? ' (${item.refundedQty} refunded)' : ''}',
                  style: meta,
                ),
                // G4.5: the base price (list or price book) and each option's price, when the server priced the line with them
                if (item.basePriceMinor != null)
                  Text(
                    key: Key('saleBase_${item.saleItemId ?? item.productId}'),
                    [
                      'Base ${Money.format(Money.fromMinor(item.basePriceMinor!, sale.currencyExponent), currency: sale.currency, exponent: sale.currencyExponent)}',
                      for (final m in item.modifiers) '${m.name} ${m.priceDeltaMinor < 0 ? '−' : '+'}${Money.format(Money.fromMinor(m.priceDeltaMinor.abs(), sale.currencyExponent), currency: sale.currency, exponent: sale.currencyExponent)}',
                    ].join(' · '),
                    style: meta,
                  ),
                // G3.2: which lot(s) this line was taken from, and a plain mark when any of it was expired stock
                if (item.lots.isNotEmpty)
                  Text(key: Key('saleLots_${item.saleItemId ?? item.productId}'), item.lots.map((l) => l.label).join(' · '), style: meta),
                if (item.soldExpired)
                  Text(key: Key('saleExpired_${item.saleItemId ?? item.productId}'), 'Sold from an expired lot', style: context.type.caption.copyWith(color: p.dangerFg, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: Space.s3),
            AmountText(
              Money.format(item.lineTotal),
              style: context.type.amountMd,
              color: p.textPrimary,
              animate: false,
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
    final pal = context.palette;
    Widget divider() => Padding(padding: const EdgeInsets.symmetric(vertical: Space.s2), child: Divider(height: 1, color: pal.border));
    return AppCard(
      child: Column(children: [
        _row(context, 'Subtotal', sale.subtotal),
        if (sale.discount > 0) _row(context, 'Discount', -sale.discount, color: pal.successFg),
        if (sale.tax > 0)
          _row(context, sale.taxRate != null ? 'Tax (${(sale.taxRate! * 100).toStringAsFixed((sale.taxRate! * 100) % 1 == 0 ? 0 : 2)}%)' : 'Tax', sale.tax),
        divider(),
        _row(context, 'Total', sale.total, bold: true),
        if (!sale.isHeld) ...[
          divider(),
          // one row per tender (split payments show each); cash also shows what was handed over
          for (final p in sale.paymentLines) ...[
            _row(context, PosPaymentMethodLabel.of(p.method), p.amount),
            if (p.tendered != null && p.tendered! > p.amount) _note(context, 'Tendered ${_m(p.tendered!)}'),
            if ((p.reference ?? '').isNotEmpty) _note(context, 'Ref ${p.reference}'),
          ],
          if (sale.changeGiven > 0) _row(context, 'Change given', sale.changeGiven),
        ],
        // G3.3: points spent / earned on this sale (the discount above already includes the redemption)
        if ((sale.loyalty?.redeemedPoints ?? 0) > 0) _note(context, 'Includes ${sale.loyalty!.redeemedPoints} ${sale.loyalty!.redeemedPoints == 1 ? 'point' : 'points'} redeemed'),
        if ((sale.loyalty?.earnedPoints ?? 0) > 0) _note(context, 'Earned ${sale.loyalty!.earnedPoints} ${sale.loyalty!.earnedPoints == 1 ? 'point' : 'points'}'),
        if (sale.refunds.isNotEmpty || sale.refundedAmount > 0) ...[
          divider(),
          for (final r in sale.refunds)
            _row(context, r.kind == 'full' ? 'Refund' : 'Partial refund', -r.amount, color: pal.dangerFg),
          if (sale.refunds.isEmpty) _row(context, 'Refunded', -sale.refundedAmount, color: pal.dangerFg),
          for (final r in sale.refunds)
            if (r.tenders.isNotEmpty) _note(context, 'Returned to ${r.tenders.map((t) => PosPaymentMethodLabel.of(t.method)).join(' + ')}'),
        ],
      ]),
    );
  }

  /// Always in the SALE's own currency and decimals (a sale made in another currency/exponent keeps its own).
  String _m(double v) => Money.format(v, currency: sale.currency, exponent: sale.currencyExponent);

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Align(alignment: Alignment.centerRight, child: Text(text, style: context.type.caption.copyWith(color: context.palette.textMuted))),
      );

  Widget _row(BuildContext context, String label, double amount, {Color? color, bool bold = false}) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(children: [
        Expanded(
          child: Text(
            label,
            style: (bold ? context.type.subtitle : context.type.body).copyWith(
              color: p.textPrimary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: Space.s3),
        AmountText(
          _m(amount),
          style: bold ? context.type.amountLg : context.type.amountMd,
          color: color ?? p.textPrimary,
          animate: false,
          alignment: MainAxisAlignment.end,
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
    final p = context.palette;
    return Obx(() {
      if (c.isProcessing.value) {
        return Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
      }
      return Column(children: [
        if (sale.canDiscard)
          _ActionButton(
            label: 'Discard Held Sale',
            variant: AppButtonVariant.danger,
            icon: Icons.delete_outline_rounded,
            onTap: () => _confirm(context, 'Discard Sale', 'Permanently delete this held sale?', c.discard),
          ),
        // G6.1: the invoice's fiscal state (failed / refused visible to the cashier and the owner; never blocks the sale)
        if (sale.invoice?.fiscal?.required == true) Padding(padding: const EdgeInsets.only(bottom: Space.s3), child: FiscalStatusCard(fiscal: sale.invoice!.fiscal)),
        if (sale.status != 'held' && sale.status != 'discarded')
          _ActionButton(
            key: const Key('openTaxInvoice'),
            label: sale.invoice != null ? 'Tax invoice ${sale.invoice!.number}' : 'Tax invoice',
            variant: AppButtonVariant.secondary,
            icon: Icons.description_outlined,
            onTap: () => Get.toNamed(Routes.posTaxInvoice, arguments: sale.id),
          ),
        // ONE path for every refund AND void: the Return flow (credit note, approval rules, restock, void for managers).
        if (sale.canRefund || sale.canVoid)
          _ActionButton(
            key: const Key('openReturn'),
            label: 'Return or void',
            variant: AppButtonVariant.danger,
            icon: Icons.undo_rounded,
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
      destructive: true,
      onConfirm: onConfirm,
    );
  }
}

/// A full-width action on the design-system [AppButton].
class _ActionButton extends StatelessWidget {
  final String label;
  final AppButtonVariant variant;
  final IconData? icon;
  final VoidCallback onTap;
  const _ActionButton({super.key, required this.label, required this.variant, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: AppButton(label: label, icon: icon, variant: variant, onPressed: onTap),
    );
  }
}

/// Display label for a tender method (cash / card / other).
class PosPaymentMethodLabel {
  static String of(String method) => switch (method) { 'cash' => 'Cash', 'card' => 'Card', 'raast_qr' => 'Raast', 'store_credit' => 'Store credit', _ => 'Bank / Other' };
}
