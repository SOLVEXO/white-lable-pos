import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_status_style.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class StoreCard extends StatelessWidget {
  final SellerStore store;
  final VoidCallback onOpen;

  const StoreCard({super.key, required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.s3 + 2),
            child: Row(
              children: [
                _StoreAvatar(
                  store: store,
                  isActive: store.isActive,
                  isprofile: store.logo.isNotEmpty,
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        style: t.subtitle.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        store.category,
                        style: t.caption.copyWith(color: p.textSecondary),
                      ),
                      if (store.posSubscriptionStatus != null) ...[
                        const SizedBox(height: Space.s1),
                        _PosSubscriptionBadge(status: store.posSubscriptionStatus!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Space.s2 + 2),
                AppButton(
                  label: 'Open',
                  onPressed: onOpen,
                  expand: false,
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: p.border,
            margin: const EdgeInsets.symmetric(horizontal: Space.s3 + 2),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3 + 2,
              vertical: Space.s2 + 2,
            ),
            child: Row(
              children: [
                _StatItem(
                  icon: Icons.inventory_2_outlined,
                  value: '${store.productCount}',
                  label: 'Products',
                ),
                const SizedBox(width: Space.s5),
                _StatItem(
                  icon: Icons.trending_up_rounded,
                  value: Money.format(store.totalSales),
                  label: 'Sales',
                ),
                const Spacer(),
                _StatusBadge(status: store.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _StoreAvatar extends StatelessWidget {
  final SellerStore store;
  final bool isActive;
  final bool isprofile;

  const _StoreAvatar({
    required this.isActive,
    required this.isprofile,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return isprofile
        ? CommonImageView(
            url: store.logo,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            radius: BorderRadius.circular(Radii.sm),
          )
        : Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: isActive ? p.accentFill : p.fill,
              borderRadius: Radii.rSm,
            ),
            alignment: Alignment.center,
            child: Text(
              store.name[0],
              style: context.type.subtitle.copyWith(
                color: isActive ? p.onAccentFill : p.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
  }
}

// ── Stat item ─────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.textMuted),
        const SizedBox(width: Space.s1),
        Text(value, style: t.label.copyWith(color: p.textPrimary)),
        const SizedBox(width: 3),
        Text(label, style: t.caption.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Label comes from the shared mapping; the colour is the token equivalent
    // of that mapping's legacy colour so it reads in light and dark.
    final label = storeStatusStyle(status).shortLabel;
    final color = switch (status) {
      'active' => p.successFg,
      'pending' => p.warningFg,
      'rejected' || 'suspended' => p.dangerFg,
      _ => p.textMuted,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: context.type.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── POS subscription badge ──────────────────────────────────────────────────
// Distinct from the business-status badge above ([_StatusBadge]) — this
// reflects the store's Stripe-backed POS subscription (see
// SellerStoresController._loadSubscriptionStatuses), which is what actually
// gates entry to that store's POS terminal.
class _PosSubscriptionBadge extends StatelessWidget {
  final PosSubscriptionStatusValue status;
  const _PosSubscriptionBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg, label) = switch (status) {
      PosSubscriptionStatusValue.active => (
        p.successSoft,
        p.successFg,
        'POS Active',
      ),
      PosSubscriptionStatusValue.expired => (
        p.dangerSoft,
        p.dangerFg,
        'POS Expired',
      ),
      PosSubscriptionStatusValue.none => (p.fill, p.textMuted, 'No POS Plan'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: context.type.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
