import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// "+3" / "−2" (a real minus sign, never a hyphen that wraps away from its digit).
String invSigned(int v) => v > 0 ? '+$v' : (v < 0 ? '−${v.abs()}' : '0');

String invDate(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d);
String invDateTime(DateTime? d) => d == null ? '' : DateFormat('d MMM, HH:mm').format(d);

/// Page frame shared by the inventory screens: app bar, safe area and a width cap so a tablet is not a stretched phone.
class InvScaffold extends StatelessWidget {
  const InvScaffold({super.key, required this.title, required this.body, this.maxWidth = 720, this.actions});
  final String title;
  final Widget body;
  final double maxWidth;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: Text(title), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0, actions: actions),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: body,
          ),
        ),
      ),
    );
  }
}

class InvErrorState extends StatelessWidget {
  const InvErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(icon: Icons.cloud_off_rounded, title: 'Could not load', message: message, actionLabel: 'Try again', onAction: onRetry, tone: context.palette.danger);
}

/// Stock status pill: nothing for a healthy item.
class InvStockBadge extends StatelessWidget {
  const InvStockBadge(this.row, {super.key});
  final InvRow row;

  @override
  Widget build(BuildContext context) {
    if (row.unlimited) return const StatusBadge('Unlimited', tone: StatusTone.info);
    if (row.out) return const StatusBadge('Out', tone: StatusTone.danger);
    if (row.low) return const StatusBadge('Low', tone: StatusTone.warning);
    return const SizedBox.shrink();
  }
}

class InvSectionTitle extends StatelessWidget {
  const InvSectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s5, bottom: Space.s2),
    child: Semantics(
      header: true,
      child: Text(text, style: context.type.title.copyWith(color: context.palette.textPrimary)),
    ),
  );
}

/// One movement line: type, signed quantity, product, time, reason / note, and cost only when the server sent it.
class InvMovementTile extends StatelessWidget {
  const InvMovementTile(this.m, {super.key, this.exponent, this.showProduct = true});
  final InvMovement m;
  final int? exponent;
  final bool showProduct;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final qtyText = m.isMarkedDamaged ? '${m.damagedDelta} damaged' : invSigned(m.qtyDelta);
    final qtyColor = m.isMarkedDamaged ? p.warningFg : (m.qtyDelta < 0 ? p.dangerFg : p.successFg);
    final why = [if ((m.reason ?? '').isNotEmpty) invReasonLabel(m.reason), if ((m.note ?? '').isNotEmpty) m.note!].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('movement_${m.id}'),
        radius: Radii.rMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.typeLabel, style: t.subtitle.copyWith(color: p.textPrimary)),
                  if (showProduct && (m.productName ?? '').isNotEmpty)
                    Text(
                      m.productName!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: p.textSecondary),
                    ),
                  Text([invDateTime(m.at), if (showProduct && (m.sku ?? '').isNotEmpty) m.sku!].where((e) => e.isNotEmpty).join(' · '), style: t.caption.copyWith(color: p.textMuted)),
                  if (why.isNotEmpty)
                    Text(
                      why,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall.copyWith(color: p.textSecondary),
                    ),
                  if (m.unitCostMinor != null) Text('Unit cost ${invMoney(m.unitCostMinor!, exponent ?? Money.exponent)}', style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            Text(
              qtyText,
              key: Key('movementQty_${m.id}'),
              style: t.amountMd.copyWith(color: qtyColor),
            ),
          ],
        ),
      ),
    );
  }
}
