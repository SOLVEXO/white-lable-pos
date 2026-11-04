import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_held_sales/controllers/pos_held_sales_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart' show PosPaymentMethod;
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/offline_gate.dart';

/// Sales that were put on hold: resume one into the cart, complete it (choosing the payment method), or discard it.
class PosHeldSalesView extends StatelessWidget {
  PosHeldSalesView({super.key});

  final PosHeldSalesController c = Get.find();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Held Sales'),
        actions: [
          IconButton(
            key: const Key('refreshHeld'),
            tooltip: 'Refresh',
            constraints: const BoxConstraints(minWidth: Space.minTouch, minHeight: Space.minTouch),
            icon: Icon(Icons.refresh_rounded, color: p.accentFg),
            onPressed: c.loadHeldSales,
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) return const SkeletonList(itemCount: 5);
        if (c.heldSales.isEmpty) {
          return EmptyState(
            icon: Icons.pause_circle_outline_rounded,
            title: 'No Held Sales',
            message: 'Sales you put on hold will appear here.',
            actionLabel: 'Refresh',
            onAction: c.loadHeldSales,
          );
        }
        return RefreshIndicator(
          onRefresh: c.loadHeldSales,
          color: p.accent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.separated(
                padding: const EdgeInsets.all(Space.s4),
                itemCount: c.heldSales.length,
                separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
                itemBuilder: (_, i) => _HeldSaleTile(key: ValueKey(c.heldSales[i].id), sale: c.heldSales[i], c: c),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _HeldSaleTile extends StatelessWidget {
  const _HeldSaleTile({super.key, required this.sale, required this.c});
  final PosSaleModel sale;
  final PosHeldSalesController c;

  String _formatDate(DateTime? dt) => dt == null ? '' : DateFormat('MMM d, h:mm a').format(dt.toLocal());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final walkIn = sale.customerName.isEmpty || sale.customerName == 'Walk-in';
    return AppCard(
      semanticLabel: 'Held sale for ${walkIn ? 'walk-in customer' : sale.customerName}, ${Money.format(sale.total)}',
      child: Obx(() {
        final processing = c.processingId.value == sale.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: p.infoSoft, borderRadius: Radii.rSm),
                  child: Icon(Icons.pause_rounded, color: p.infoFg, size: 18),
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(walkIn ? 'Walk-in customer' : sale.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle.copyWith(color: p.textPrimary)),
                      Text(_formatDate(sale.createdAt), style: t.caption.copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(Money.format(sale.total), style: t.amountMd.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    const StatusBadge('Held', tone: StatusTone.info, dot: true),
                  ],
                ),
              ],
            ),
            if (sale.items.isNotEmpty) ...[
              const SizedBox(height: Space.s3),
              Divider(height: 1, color: p.border),
              const SizedBox(height: Space.s2),
              for (final item in sale.items.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall.copyWith(color: p.textSecondary))),
                      Text('×${item.qty}  ${Money.format(item.lineTotal)}', style: t.amountMd.copyWith(fontSize: 12, color: p.textSecondary)),
                    ],
                  ),
                ),
              if (sale.items.length > 3) Text('+${sale.items.length - 3} more items', style: t.caption.copyWith(color: p.textMuted)),
            ],
            const SizedBox(height: Space.s2),
            Row(
              children: [
                Icon(Icons.payments_outlined, size: 14, color: p.textMuted),
                const SizedBox(width: Space.s1),
                Text(sale.paymentMethod.capitalizeFirst ?? sale.paymentMethod, style: t.caption.copyWith(color: p.textMuted)),
                if (sale.notes.isNotEmpty) ...[
                  const SizedBox(width: Space.s3),
                  Icon(Icons.notes_rounded, size: 14, color: p.textMuted),
                  const SizedBox(width: Space.s1),
                  Expanded(child: Text(sale.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: p.textMuted))),
                ],
              ],
            ),
            const SizedBox(height: Space.s3),
            if (processing)
              Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent)))
            else
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AppButton(key: Key('resume-${sale.id}'), label: 'Resume', icon: Icons.play_arrow_rounded, variant: AppButtonVariant.secondary, onPressed: () => c.resumeSale(sale)),
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    flex: 2,
                    child: _CompleteButton(sale: sale, onTap: () => _pickPaymentAndComplete(context)),
                  ),
                  const SizedBox(width: Space.s2),
                  SizedBox(
                    width: Space.minTouch + 8,
                    child: AppButton(
                      key: Key('discard-${sale.id}'),
                      label: '',
                      semanticLabel: 'Discard sale',
                      icon: Icons.delete_outline_rounded,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => _confirmDiscard(context),
                    ),
                  ),
                ],
              ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final ok = await AppDialog.confirm(context, title: 'Discard Sale', message: 'This will permanently delete the held sale.', confirmLabel: 'Discard', destructive: true);
    if (ok) await c.discardSale(sale);
  }

  void _pickPaymentAndComplete(BuildContext context) {
    final selected = ValueNotifier<String>(sale.paymentMethod);
    AppBottomSheet.show<void>(
      context,
      title: 'Complete Sale',
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Total: ${Money.format(sale.total)} — choose the payment method used.', style: ctx.type.body.copyWith(color: p.textSecondary)),
            const SizedBox(height: Space.s4),
            ValueListenableBuilder<String>(
              valueListenable: selected,
              builder: (_, method, __) => Row(
                children: [
                  for (final m in PosPaymentMethod.all) ...[
                    if (m != PosPaymentMethod.all.first) const SizedBox(width: Space.s2),
                    Expanded(
                      child: AppCard(
                        key: Key('completeMethod-$m'),
                        color: m == method ? p.accentSoft : p.surface,
                        radius: Radii.rMd,
                        padding: const EdgeInsets.symmetric(vertical: Space.s3),
                        semanticLabel: '${PosPaymentMethod.label(m)}${m == method ? ', selected' : ''}',
                        onTap: () => selected.value = m,
                        child: Center(child: Text(PosPaymentMethod.label(m), style: ctx.type.label.copyWith(color: m == method ? p.accentFg : p.textPrimary))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.s5),
            AppButton(
              key: const Key('completeSaleConfirm'),
              label: 'Complete Sale',
              size: AppButtonSize.lg,
              onPressed: () {
                Navigator.of(ctx).pop();
                c.completeSale(sale, paymentMethod: selected.value);
              },
            ),
          ],
        );
      },
    );
  }
}

/// "Complete" needs the server: offline it only explains why (see [OfflineGate]). The reactive read is wrapped in an
/// `Obx` only when the network service exists (it always does in the app; without it there is nothing to observe).
class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.sale, required this.onTap});
  final PosSaleModel sale;
  final VoidCallback onTap;

  Widget _button({required bool offline}) => AppButton(
    key: Key('complete-${sale.id}'),
    label: 'Complete',
    icon: Icons.check_circle_outline_rounded,
    variant: offline ? AppButtonVariant.ghost : AppButtonVariant.primary,
    onPressed: offline ? () => CustomAppSnackbar.error(OfflineGate.message) : onTap,
  );

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NetworkStatusService>()) return _button(offline: false);
    return Obx(() => _button(offline: OfflineGate.isOffline));
  }
}
