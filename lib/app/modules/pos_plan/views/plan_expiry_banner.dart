import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Owner-facing heads-up when an ACTIVE plan has 7 days or fewer left. Informational only: no price, no link, no button
/// to buy anything (store-policy compliance) — it just says when access ends.
class PlanExpiryBanner extends StatelessWidget {
  const PlanExpiryBanner({super.key, required this.status, this.onTap});
  final PosSubscriptionStatusModel? status;
  final VoidCallback? onTap;

  static const int warnDays = 7;

  static bool shouldShow(PosSubscriptionStatusModel? s) =>
      s != null && s.status.isEntitled && s.daysRemaining != null && s.daysRemaining! <= warnDays && s.expiresAt != null;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (!shouldShow(s)) return const SizedBox.shrink();
    final days = s!.daysRemaining!;
    final when = DateFormat('MMM d, y').format(s.expiresAt!.toLocal());
    final text = days <= 1 ? "This store's POS plan ends $when (today or tomorrow)." : "This store's POS plan ends $when ($days days left).";
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: GestureDetector(
        key: const Key('planExpiryBanner'),
        onTap: onTap,
        child: AppBanner(message: text, icon: Icons.schedule_rounded, tone: StatusTone.warning),
      ),
    );
  }
}
