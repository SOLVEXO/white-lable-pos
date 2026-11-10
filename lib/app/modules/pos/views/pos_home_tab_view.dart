import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/clock_home_card.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/views/dashboard_pulse.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The Home tab: business pulse for managers / owners, shift snapshot for cashiers — only figures the server already
/// provides. Anything that still needs a new endpoint (profit, expenses, counts) is a "Soon" placeholder shown to
/// managers / owners ONLY; a cashier never sees an unfinished feature.
class PosHomeTabView extends StatelessWidget {
  PosHomeTabView({super.key, PosHomeTabController? controller})
    : c = controller ?? Get.find<PosHomeTabController>();

  final PosHomeTabController c;

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  void _goSell() {
    if (Get.isRegistered<PosBottomNavController>()) {
      Get.find<PosBottomNavController>().changeTab(PosBottomNavController.saleTab);
    }
  }

  void _goStock() {
    if (Get.isRegistered<PosBottomNavController>()) {
      Get.find<PosBottomNavController>().changeTab(PosBottomNavController.stockTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: c.load,
            child: Obx(() {
              if (c.loading.value &&
                  c.shift.value == null &&
                  c.today.value == null) {
                return const SkeletonShimmer(
                  child: Padding(
                    padding: EdgeInsets.all(Space.s4),
                    child: Column(
                      children: [
                        SkeletonBox(height: 150, radius: Radii.lg),
                        SizedBox(height: Space.s3),
                        SkeletonBox(height: 72, radius: Radii.md),
                        SizedBox(height: Space.s3),
                        SkeletonBox(height: 120, radius: Radii.md),
                      ],
                    ),
                  ),
                );
              }
              if (c.failed.value) {
                return ListView(
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Couldn\'t load your numbers',
                      message:
                          'Check the connection and try again. Selling still works.',
                      actionLabel: 'Try again',
                      onAction: c.load,
                    ),
                  ],
                );
              }
              final access = c.access.value;
              return ListView(
                key: const Key('homeTab'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s4,
                  Space.s4,
                  Space.s8,
                ),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      c.employeeName.value.isEmpty
                          ? _greeting()
                          : '${_greeting()}, ${c.employeeName.value.split(' ').first}',
                      style: context.type.headline.copyWith(
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    access.canManage ? 'Business pulse' : 'Your shift',
                    style: context.type.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  _Hero(c: c, access: access),
                  const ClockHomeCard(),
                  const SizedBox(height: Space.s3),
                  _Tiles(c: c, access: access),
                  if (c.dashboard.value != null) ...[
                    const SizedBox(height: Space.s4),
                    DashboardPulse(d: c.dashboard.value!, onAttention: () => Get.toNamed(Routes.posNeedsAttention)),
                  ],
                  const SizedBox(height: Space.s5),
                  SectionHeader('Quick actions'),
                  _Actions(access: access, onSell: _goSell),
                  if (access.canManage) ...[
                    const SizedBox(height: Space.s5),
                    const SectionHeader('Last 7 days'),
                    _Trend(week: c.week.value, locked: c.pulseLocked.value),
                  ],
                  if (access.canManage && c.kyb.value != null) ...[
                    const SizedBox(height: Space.s5),
                    const SectionHeader('Digital payments'),
                    _KybCard(status: c.kyb.value!),
                  ],
                  const SizedBox(height: Space.s5),
                  const SectionHeader('Needs attention'),
                  _Attention(c: c, access: access, onStock: _goStock),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.access});
  final PosHomeTabController c;
  final PosAccess access;

  @override
  Widget build(BuildContext context) {
    final today = c.today.value;
    final shift = c.shift.value;
    final manager = access.canManage;
    final label = manager ? 'Net sales · Today' : 'This shift · Sales';
    final value = manager ? today?.netRevenue : shift?.totalSales;
    final locked = manager && c.pulseLocked.value;
    return Semantics(
      container: true,
      label: '$label ${value == null ? 'not available' : Money.format(value)}',
      child: Container(
        key: const Key('homeHero'),
        padding: const EdgeInsets.all(Space.s5),
        decoration: BoxDecoration(
          borderRadius: Radii.rLg,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF252A31), Color(0xFF15181D)],
          ),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.type.caption.copyWith(
                  color: const Color(0xFFB9BEC6),
                ),
              ),
              const SizedBox(height: Space.s2),
              if (value != null)
                AmountText(
                  Money.format(value),
                  style: context.type.amountXl,
                  color: Colors.white,
                )
              else
                Text(
                  locked ? 'Manager PIN needed' : '—',
                  style: context.type.headline.copyWith(color: Colors.white),
                ),
              const SizedBox(height: Space.s2),
              Text(
                locked
                    ? 'Sign in with a manager PIN to see business numbers.'
                    : (manager
                          ? '${today?.totalTransactions ?? 0} sales today'
                          : '${shift?.completedSales ?? 0} sales · ${shift?.heldSales ?? 0} on hold'),
                style: context.type.bodySmall.copyWith(
                  color: const Color(0xFFB9BEC6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.c, required this.access});
  final PosHomeTabController c;
  final PosAccess access;

  @override
  Widget build(BuildContext context) {
    final today = c.today.value;
    final shift = c.shift.value;
    final tiles = access.canManage
        ? [
            _Tile(
              keyName: 'orders',
              label: 'Orders',
              value: '${today?.totalTransactions ?? '—'}',
            ),
            _Tile(
              keyName: 'avg',
              label: 'Avg. sale',
              value: today == null
                  ? '—'
                  : Money.format(today.avgTransactionValue),
              amount: today != null,
            ),
            const _Tile(
              keyName: 'profit',
              label: 'Profit',
              value: 'Soon',
              soon: true,
            ),
          ]
        : [
            _Tile(
              keyName: 'cash',
              label: 'Cash',
              value: shift == null
                  ? '—'
                  : Money.format(shift.session.cashSales),
              amount: shift != null,
            ),
            _Tile(
              keyName: 'card',
              label: 'Card',
              value: shift == null
                  ? '—'
                  : Money.format(shift.session.cardSales),
              amount: shift != null,
            ),
            _Tile(
              keyName: 'refunds',
              label: 'Refunds',
              value: '${shift?.refundsCount ?? '—'}',
            ),
          ];
    // Large text: three tiles side by side stop fitting, so they stack (a number must never be clipped or wrapped mid-digit).
    final big = MediaQuery.textScalerOf(context).scale(16) > 22;
    if (big) {
      return Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            SizedBox(width: double.infinity, child: tiles[i]),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.s2),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.keyName,
    required this.label,
    required this.value,
    this.amount = false,
    this.soon = false,
  });
  final String keyName;
  final String label;
  final String value;
  final bool amount;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      key: Key('homeTile-$keyName'),
      padding: const EdgeInsets.all(Space.s3),
      semanticLabel: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.type.caption.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Space.s1),
          if (soon)
            const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: StatusBadge('Coming soon', tone: StatusTone.neutral),
            )
          else if (amount)
            AmountText(
              value,
              style: context.type.amountMd,
              color: p.textPrimary,
            )
          else
            Text(
              value,
              style: context.type.amountMd.copyWith(color: p.textPrimary),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.access, required this.onSell});
  final PosAccess access;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      _Action(
        keyName: 'newSale',
        icon: Icons.point_of_sale_rounded,
        label: 'New sale',
        onTap: onSell,
        primary: true,
      ),
      _Action(
        keyName: 'heldSales',
        icon: Icons.pause_circle_outline_rounded,
        label: 'Held sales',
        onTap: () => Get.toNamed(Routes.posHeldSales),
      ),
      if (access.canManage) ...const [
        _Action(
          keyName: 'expense',
          icon: Icons.remove_circle_outline_rounded,
          label: 'Expense',
          soon: true,
        ),
        _Action(
          keyName: 'count',
          icon: Icons.checklist_rounded,
          label: 'Count',
          soon: true,
        ),
      ],
    ];
    return Wrap(spacing: Space.s2, runSpacing: Space.s2, children: items);
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.keyName,
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
    this.soon = false,
  });
  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = primary ? p.onAccentFill : (soon ? p.textMuted : p.textPrimary);
    return Semantics(
      button: true,
      enabled: !soon,
      label: soon ? '$label, coming soon' : label,
      child: Material(
        color: primary ? p.accentFill : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rMd,
          side: primary ? BorderSide.none : BorderSide(color: p.border),
        ),
        child: InkWell(
          key: Key('homeAction-$keyName'),
          borderRadius: Radii.rMd,
          onTap: soon ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Space.minTouch,
              minWidth: Space.minTouch,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s4,
                vertical: Space.s2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: primary
                        ? p.onAccentFill
                        : (soon ? p.textMuted : p.accentFg),
                  ),
                  const SizedBox(width: Space.s2),
                  Text(label, style: context.type.label.copyWith(color: fg)),
                  if (soon) ...[
                    const SizedBox(width: Space.s2),
                    const StatusBadge('Soon', tone: StatusTone.neutral),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.week, required this.locked});
  final PosRangeReportModel? week;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final days = week?.dailyBreakdown ?? const <PosDailyBucket>[];
    if (days.isEmpty) {
      return AppCard(
        child: Text(
          locked
              ? 'Sign in with a manager PIN to see sales history.'
              : 'No sales in the last 7 days yet.',
          style: context.type.bodySmall.copyWith(color: p.textSecondary),
        ),
      );
    }
    final maxV = days
        .map((d) => d.total)
        .fold<double>(0, (a, b) => a > b ? a : b);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return AppCard(
      key: const Key('homeTrend'),
      semanticLabel: '7-day sales, total ${Money.format(week!.netRevenue)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '7-day sales',
                style: context.type.caption.copyWith(color: p.textSecondary),
              ),
              AmountText(
                Money.format(week!.netRevenue),
                style: context.type.amountMd,
                color: p.textPrimary,
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: maxV <= 0
                                ? 4
                                : (6 + 70 * (days[i].total / maxV)),
                            decoration: BoxDecoration(
                              color: i == days.length - 1
                                  ? p.accent
                                  : p.accentSoft,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(Radii.sm),
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.s1),
                          Text(
                            labels[DateTime.tryParse(days[i].date)?.weekday ==
                                    null
                                ? i % 7
                                : DateTime.parse(days[i].date).weekday - 1],
                            style: context.type.caption.copyWith(
                              color: p.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.c,
    required this.access,
    required this.onStock,
  });
  final PosHomeTabController c;
  final PosAccess access;
  final VoidCallback onStock;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final unresolved = c.unresolvedSales;
    if (unresolved > 0) {
      rows.add(
        _Row(
          keyName: 'sync',
          icon: Icons.sync_problem_rounded,
          tone: StatusTone.warning,
          title:
              '$unresolved offline ${unresolved == 1 ? 'sale needs' : 'sales need'} attention',
          subtitle: 'Not on the server yet',
          onTap: () => Get.toNamed(Routes.posNeedsAttention),
        ),
      );
    }
    final digital = c.digitalAttention.value;
    if (access.canManage && digital > 0) {
      rows.add(
        _Row(
          keyName: 'digital',
          icon: Icons.qr_code_2_rounded,
          tone: StatusTone.danger,
          title: '$digital digital ${digital == 1 ? 'payment needs' : 'payments need'} attention',
          subtitle: 'Raast payment to match, refund or resolve',
          onTap: () => Get.toNamed(Routes.posNeedsAttention),
        ),
      );
    }
    final low = c.lowStockCount.value ?? 0;
    if (access.canManage && low > 0) {
      rows.add(
        _Row(
          keyName: 'lowStock',
          icon: Icons.inventory_2_outlined,
          tone: StatusTone.warning,
          title: '$low low-stock ${low == 1 ? 'item' : 'items'}',
          subtitle: 'Reorder soon',
          onTap: onStock,
        ),
      );
    }
    // G3.2: lots past their date / about to pass it (the server sends this to managers and owners only)
    final ex = c.dashboard.value?.expiring;
    if (access.canManage && ex != null && (ex.expiredLots + ex.expiringIn7Days + ex.expiringIn30Days) > 0) {
      rows.add(
        _Row(
          keyName: 'expiring',
          icon: Icons.event_busy_outlined,
          tone: StatusTone.warning,
          title: 'Expiring soon',
          subtitle: '${ex.expiredLots} expired · ${ex.expiringIn7Days} in 7 days · ${ex.expiringIn30Days} in 30 days',
          onTap: () => Get.toNamed(Routes.posStockList, arguments: const {'filter': 'expiring'}),
        ),
      );
    }
    final s = c.shift.value?.session;
    if (s != null) {
      final t = TimeOfDay.fromDateTime(s.openedAt.toLocal());
      rows.add(
        _Row(
          keyName: 'shift',
          icon: Icons.schedule_rounded,
          tone: StatusTone.info,
          title: 'Shift open since ${t.format(context)}',
          subtitle: 'Opening cash ${Money.format(s.openingCash)}',
          onTap: () => Get.toNamed(Routes.posSessionReport),
        ),
      );
    }
    if (rows.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: context.palette.successFg,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                'All clear — nothing needs your attention.',
                style: context.type.body.copyWith(
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          rows[i],
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.keyName,
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String keyName;
  final IconData icon;
  final StatusTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      key: Key('homeAttention-$keyName'),
      onTap: onTap,
      semanticLabel: '$title. $subtitle',
      child: Row(
        children: [
          Icon(
            icon,
            color: tone == StatusTone.warning ? p.warningFg : p.infoFg,
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.type.subtitle.copyWith(color: p.textPrimary),
                ),
                Text(
                  subtitle,
                  style: context.type.bodySmall.copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}


/// Read-only status of the store's business verification, which decides whether Raast QR can be used. The owner completes it
/// (a later release); here a manager only sees where it stands and, if it was sent back, why.
class _KybCard extends StatelessWidget {
  const _KybCard({required this.status});
  final PosKybStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (tone, icon, line) = switch (status.state) {
      PosKybState.verified => (
        StatusTone.success,
        Icons.verified_rounded,
        status.digitalPaymentsEnabled ? 'Raast QR payments are on for this store.' : 'Verified. Raast QR will switch on once the payment provider finishes setting up the store.',
      ),
      PosKybState.submitted => (StatusTone.info, Icons.hourglass_top_rounded, 'Solvexo is reviewing the business details. Raast QR stays off until this is approved.'),
      PosKybState.rejected => (StatusTone.warning, Icons.edit_note_rounded, status.rejectionReason ?? 'The business details need changes before Raast QR can be used.'),
      PosKybState.draft => (StatusTone.neutral, Icons.pending_outlined, 'The business details are not submitted yet. Raast QR stays off until they are approved.'),
      PosKybState.notStarted => (StatusTone.neutral, Icons.shield_outlined, 'Business verification has not been started. Raast QR needs it.'),
    };
    return AppCard(
      key: const Key('kybCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Business verification', style: context.type.subtitle.copyWith(color: p.textPrimary))),
              StatusBadge(status.state.label, tone: tone, icon: icon),
            ],
          ),
          const SizedBox(height: Space.s2),
          Text(line, key: const Key('kybCardText'), style: context.type.bodySmall.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}
