import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "Offline: showing what this till remembers, as of 9 Nov, 14:32" — shown above remembered customer data.
class CustomerAsOfBanner extends StatelessWidget {
  const CustomerAsOfBanner({super.key, required this.asOf, this.subject = 'customers'});
  final DateTime asOf;
  final String subject;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('customerAsOf'),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: p.warningFg),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text('Offline. Showing $subject as of ${invDateTime(asOf)}.', style: context.type.caption.copyWith(color: p.warningFg)),
          ),
        ],
      ),
    );
  }
}

/// Initial in a soft circle.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar(this.customer, {super.key, this.radius = 20});
  final PosCustomer customer;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CircleAvatar(
      radius: radius,
      backgroundColor: p.accentSoft,
      child: Text(customer.initial, style: context.type.subtitle.copyWith(color: p.accentFg)),
    );
  }
}

/// Store-credit balance and points of a customer as small badges. Money is shown only when the response stated its currency.
class CustomerBalanceBadges extends StatelessWidget {
  const CustomerBalanceBadges({super.key, required this.customer, required this.cur});
  final PosCustomer customer;
  final InvCur? cur;

  @override
  Widget build(BuildContext context) {
    final credit = customer.creditBalanceMinor;
    return Wrap(
      spacing: Space.s2,
      runSpacing: Space.s1,
      children: [
        if (credit != null && cur != null) StatusBadge('Credit ${invMoney(credit, cur!)}', tone: credit > 0 ? StatusTone.success : StatusTone.neutral, icon: Icons.account_balance_wallet_outlined),
        if (customer.loyaltyPoints > 0 || customer.loyaltyTier != null)
          StatusBadge([if (customer.loyaltyTier != null) loyaltyTierLabel(customer.loyaltyTier), '${customer.loyaltyPoints} pts'].join(' · '), tone: StatusTone.accent, icon: Icons.stars_rounded),
      ],
    );
  }
}

/// One customer row of the directory and of the picker.
class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.customer, required this.cur, required this.onTap});
  final PosCustomer customer;
  final InvCur? cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('customer_${customer.id}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            CustomerAvatar(customer),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  if (customer.subtitle.isNotEmpty)
                    Text(
                      customer.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textMuted),
                    ),
                  if (customer.creditBalanceMinor != null || customer.loyaltyPoints > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: CustomerBalanceBadges(customer: customer, cur: cur),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A short instruction row with an icon ("Needs internet"), used where a write is not possible offline.
class CustomerNote extends StatelessWidget {
  const CustomerNote({super.key, required this.icon, required this.text, this.noteKey});
  final IconData icon;
  final String text;
  final Key? noteKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      key: noteKey,
      children: [
        Icon(icon, size: 16, color: p.textMuted),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Text(text, style: context.type.caption.copyWith(color: p.textSecondary)),
        ),
      ],
    );
  }
}
