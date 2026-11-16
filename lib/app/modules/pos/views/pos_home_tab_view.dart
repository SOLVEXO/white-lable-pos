import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/dashboard_alerts_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_bottom_nav_controller.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/dashboard_pulse.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/pulse_home_card.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/clock_home_card.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The Home tab (G6.3, the blueprint's dashboard). At a glance, per role:
///  1. the register — closed, or open by whom, since when, with what float — and the ONE primary action for that state;
///  2. my own clock-in state;
///  3. today's figures (managers / owners: the store; a cashier: their shift) — server figures only, no cost or profit;
///  4. what needs action (offline sales, digital payments, low stock, expiring lots, fiscal documents, expenses to approve,
///     attendance problems, sales to review), each linking to its screen;
///  5. the quick actions this role may use.
/// Phone: one column. Tablet: figures on the left, attention and actions on the right. Offline: a banner, and what this device last saw.
/// Older backend: release-#2 rows (fiscal) are simply absent.
class PosHomeTabView extends StatelessWidget {
  PosHomeTabView({super.key, PosHomeTabController? controller, DashboardAlertsController? alerts})
    : c = controller ?? Get.find<PosHomeTabController>(),
      _alerts = alerts;

  final PosHomeTabController c;
  final DashboardAlertsController? _alerts;

  DashboardAlertsController? get alerts => _alerts ?? (Get.isRegistered<DashboardAlertsController>() ? Get.find<DashboardAlertsController>() : null);

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  static void goTab(int tab) {
    if (Get.isRegistered<PosBottomNavController>()) Get.find<PosBottomNavController>().changeTab(tab);
  }

  Future<void> _refresh() async {
    await Future.wait([c.load(), if (alerts != null) alerts!.load()]);
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
            onRefresh: _refresh,
            child: Obx(() {
              final online = !Get.isRegistered<NetworkStatusService>() || Get.find<NetworkStatusService>().isOnline.value;
              if (c.loading.value && c.shift.value == null && c.today.value == null) {
                return const SkeletonShimmer(
                  child: Padding(
                    padding: EdgeInsets.all(Space.s4),
                    child: Column(
                      children: [
                        SkeletonBox(height: 56, radius: Radii.md),
                        SizedBox(height: Space.s3),
                        SkeletonBox(height: 120, radius: Radii.lg),
                        SizedBox(height: Space.s3),
                        SkeletonBox(height: 150, radius: Radii.lg),
                        SizedBox(height: Space.s3),
                        SkeletonBox(height: 72, radius: Radii.md),
                      ],
                    ),
                  ),
                );
              }
              if (c.failed.value && online) {
                return ListView(
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Couldn\'t load your numbers',
                      message: 'Check the connection and try again. Selling still works.',
                      actionLabel: 'Try again',
                      onAction: c.load,
                      tone: p.danger,
                    ),
                  ],
                );
              }
              final access = c.access.value;
              final manager = access.canManage;
              final header = _Header(greeting: _greeting(), name: c.employeeName.value, access: access);
              final register = <Widget>[_RegisterCard(c: c, onSell: () => goTab(PosBottomNavController.saleTab)), const ClockHomeCard()];
              final today = <Widget>[
                SectionHeader(manager ? 'Today' : 'This shift'),
                _Hero(c: c, access: access),
                const SizedBox(height: Space.s2),
                _Tiles(c: c, access: access),
                if (manager) const PulseHomeCard(),
              ];
              final attention = <Widget>[const SectionHeader('Needs attention'), _Attention(c: c, access: access, alerts: alerts)];
              final actions = <Widget>[const SectionHeader('Quick actions'), _Actions(access: access)];
              final details = <Widget>[
                if (manager) ...[const SectionHeader('Last 7 days'), _Trend(week: c.week.value, locked: c.pulseLocked.value), const SizedBox(height: Space.s5)],
                if (c.dashboard.value != null) ...[
                  DashboardPulse(d: c.dashboard.value!, summary: false, attention: false, onAttention: () => Get.toNamed(Routes.posNeedsAttention)),
                  const SizedBox(height: Space.s5),
                ],
                if (manager && c.kyb.value != null) ...[const SectionHeader('Digital payments'), _KybCard(status: c.kyb.value!)],
              ];
              const gap = SizedBox(height: Space.s5);
              return LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 680; // a tablet, portrait or landscape (the rail takes ~100)
                  const pad = EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s8);
                  final top = <Widget>[
                    header,
                    const SizedBox(height: Space.s4),
                    if (!online) ...[const AppBanner.offline(), const SizedBox(height: Space.s3)],
                  ];
                  if (!wide) {
                    return ListView(
                      key: const Key('homeTab'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: pad,
                      children: [...top, ...register, gap, ...today, gap, ...attention, gap, ...actions, gap, ...details],
                    );
                  }
                  Widget col(List<Widget> w) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: w);
                  return ListView(
                    key: const Key('homeTab'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: pad,
                    children: [
                      ...top,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: col([...register, gap, ...today, gap, ...details])),
                          const SizedBox(width: Space.s5),
                          Expanded(flex: 5, child: col([...attention, gap, ...actions])),
                        ],
                      ),
                    ],
                  );
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.name, required this.access});
  final String greeting;
  final String name;
  final PosAccess access;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final role = switch (access) { PosAccess.owner => 'Owner', PosAccess.manager => 'Manager', PosAccess.cashier => 'Cashier' };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(name.isEmpty ? greeting : '$greeting, ${name.split(' ').first}', style: context.type.headline.copyWith(color: p.textPrimary)),
              ),
              const SizedBox(height: Space.s1),
              Text(access.canManage ? 'Business pulse' : 'Your shift', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: Space.s2),
        StatusBadge(role, key: const Key('homeRole'), tone: access.canManage ? StatusTone.accent : StatusTone.neutral),
      ],
    );
  }
}

/// The register: closed → "Open register"; open → who opened it, since when, the float, "Continue selling" and "Close shift".
class _RegisterCard extends StatelessWidget {
  const _RegisterCard({required this.c, required this.onSell});
  final PosHomeTabController c;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final report = c.shift.value;
    final s = report?.session;
    final open = s != null || AppPreferences.cachedHasPosSession;
    String? by;
    if (s != null) {
      for (final x in c.dashboard.value?.shifts ?? const <({String? employeeName, DateTime? openedAt, double totalSales, int transactions})>[]) {
        if (x.openedAt != null && x.openedAt!.isAtSameMomentAs(s.openedAt) && (x.employeeName ?? '').isNotEmpty) by = x.employeeName;
      }
      by ??= c.employeeName.value.isEmpty ? null : c.employeeName.value;
    }
    final facts = [
      if (by != null) 'Opened by $by',
      if (s != null) 'since ${DateFormat('HH:mm').format(s.openedAt.toLocal())}',
    ].join(' · ');
    final close = Get.isRegistered<PosSettingsController>();
    return AppCard(
      key: const Key('homeRegister'),
      semanticLabel: open ? 'Register open. $facts' : 'Register closed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: open ? p.successSoft : p.fill, borderRadius: Radii.rMd),
                child: Icon(open ? Icons.point_of_sale_rounded : Icons.lock_clock_outlined, size: IconSizes.md, color: open ? p.successFg : p.textSecondary),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(open ? 'Register open' : 'Register closed', style: t.title.copyWith(color: p.textPrimary)),
                    Text(
                      open ? (facts.isEmpty ? 'This till has an open shift' : facts) : 'Sign in with your PIN and count the opening cash to start selling.',
                      key: const Key('homeRegisterFacts'),
                      style: t.bodySmall.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusBadge(open ? 'Open' : 'Closed', tone: open ? StatusTone.success : StatusTone.neutral, dot: true),
            ],
          ),
          if (s != null) ...[
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(child: _Fact(label: 'Float', value: Money.format(s.openingCash))),
                const SizedBox(width: Space.s2),
                Expanded(child: _Fact(label: 'Expected cash', value: Money.format(report!.cashFlow.expectedCash))),
              ],
            ),
          ],
          const SizedBox(height: Space.s3),
          if (open) ...[
            AppButton(key: const Key('homeRegisterSell'), label: 'Continue selling', icon: Icons.point_of_sale_rounded, onPressed: onSell),
            const SizedBox(height: Space.s2),
            Builder(builder: (context) {
              final summary = AppButton(
                key: const Key('homeRegisterSummary'),
                label: 'Shift summary',
                variant: AppButtonVariant.secondary,
                onPressed: () => Get.toNamed(Routes.posSessionReport),
              );
              final closeBtn = close
                  ? AppButton(
                      key: const Key('homeRegisterClose'),
                      label: 'Close shift',
                      variant: AppButtonVariant.ghost,
                      onPressed: () => Get.find<PosSettingsController>().showCloseShiftDialog(),
                    )
                  : null;
              // large text: the two labels no longer fit side by side, so they stack (never truncated)
              if (MediaQuery.textScalerOf(context).scale(16) > 19) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [summary, if (closeBtn != null) ...[const SizedBox(height: Space.s2), closeBtn]]);
              }
              return Row(children: [Expanded(child: summary), if (closeBtn != null) ...[const SizedBox(width: Space.s2), Expanded(child: closeBtn)]]);
            }),
          ] else
            AppButton(key: const Key('homeRegisterOpen'), label: 'Open register', icon: Icons.lock_open_rounded, onPressed: () => Get.toNamed(Routes.posPinLogin)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
          AmountText(value, style: context.type.amountMd, color: p.textPrimary, animate: false),
        ],
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
    final p = context.palette;
    final today = c.today.value;
    final shift = c.shift.value;
    final manager = access.canManage;
    final label = manager ? 'Net sales · Today' : 'This shift · Sales';
    final value = manager ? today?.netRevenue : shift?.totalSales;
    final online = !Get.isRegistered<NetworkStatusService>() || Get.find<NetworkStatusService>().isOnline.value;
    // offline, the reports simply could not be fetched: that is not a missing manager PIN
    final locked = manager && c.pulseLocked.value && online;
    return KeyedSubtree(
      key: const Key('homeHero'),
      child: AppHero(
        caption: label,
        semanticLabel: '$label ${value == null ? 'not available' : Money.format(value)}',
        figure: value != null
            ? AmountText(Money.format(value), style: context.type.amountXl, color: p.onHero)
            : Text(locked ? 'Manager PIN needed' : '—', style: context.type.headline.copyWith(color: p.onHero)),
        footnote: !online && value == null
            ? 'Today\'s figures need a connection.'
            : locked
            ? 'Sign in with a manager PIN to see business numbers.'
            : (manager ? '${today?.totalTransactions ?? 0} sales today' : '${shift?.completedSales ?? 0} sales · ${shift?.heldSales ?? 0} on hold'),
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
            _Tile(keyName: 'orders', label: 'Orders', value: '${today?.totalTransactions ?? '—'}'),
            _Tile(keyName: 'avg', label: 'Avg. sale', value: today == null ? '—' : Money.format(today.avgTransactionValue), amount: today != null),
            _Tile(keyName: 'refunds', label: 'Refunds', value: today == null ? '—' : Money.format(today.refundsTotal), amount: today != null),
          ]
        : [
            _Tile(keyName: 'cash', label: 'Cash', value: shift == null ? '—' : Money.format(shift.session.cashSales), amount: shift != null),
            _Tile(keyName: 'card', label: 'Card', value: shift == null ? '—' : Money.format(shift.session.cardSales), amount: shift != null),
            _Tile(keyName: 'refunds', label: 'Refunds', value: '${shift?.refundsCount ?? '—'}'),
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
  const _Tile({required this.keyName, required this.label, required this.value, this.amount = false});
  final String keyName;
  final String label;
  final String value;
  final bool amount;

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
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s1),
          if (amount)
            AmountText(value, style: context.type.amountMd, color: p.textPrimary)
          else
            Text(value, style: context.type.amountMd.copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }
}

/// The blueprint's quick-grid: square tiles, four across on a phone (three at large text), the first one filled.
class _Actions extends StatelessWidget {
  const _Actions({required this.access});
  final PosAccess access;

  @override
  Widget build(BuildContext context) {
    final m = access.canManage;
    final items = <_Action>[
      _Action(keyName: 'newSale', icon: Icons.point_of_sale_rounded, label: 'New sale', primary: true, onTap: () => PosHomeTabView.goTab(PosBottomNavController.saleTab)),
      _Action(keyName: 'heldSales', icon: Icons.pause_circle_outline_rounded, label: 'Held sales', onTap: () => Get.toNamed(Routes.posHeldSales)),
      _Action(keyName: 'products', icon: Icons.inventory_2_outlined, label: 'Products', onTap: () => Get.toNamed(Routes.posProducts)),
      _Action(keyName: 'orders', icon: Icons.receipt_long_outlined, label: 'Orders', onTap: () => PosHomeTabView.goTab(PosBottomNavController.ordersTab)),
      _Action(keyName: 'cash', icon: Icons.swap_vert_rounded, label: 'Cash in / out', onTap: () => Get.toNamed(Routes.posCash)),
      if (m) _Action(keyName: 'expense', icon: Icons.remove_circle_outline_rounded, label: 'Expenses', onTap: () => Get.toNamed(Routes.posCashExpenses)),
      if (m) _Action(keyName: 'count', icon: Icons.checklist_rounded, label: 'Stock count', onTap: () => Get.toNamed(Routes.posStockCount)),
      if (m) _Action(keyName: 'reports', icon: Icons.insights_rounded, label: 'Reports', onTap: () => Get.toNamed(Routes.posReports)),
      if (m) _Action(keyName: 'team', icon: Icons.groups_2_outlined, label: 'Team', onTap: () => Get.toNamed(Routes.posTeamAttendance)),
      if (!m) _Action(keyName: 'mySales', icon: Icons.insights_rounded, label: 'My sales', onTap: () => Get.toNamed(Routes.posReport, arguments: {'kind': 'cashiers'})),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final big = MediaQuery.textScalerOf(context).scale(16) > 19;
        final cols = box.maxWidth >= 560 ? 5 : (big ? 3 : 4);
        final w = (box.maxWidth - Space.s2 * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [for (final a in items) SizedBox(width: w, child: a)],
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.keyName, required this.icon, required this.label, required this.onTap, this.primary = false});
  final String keyName;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primary ? p.accentFill : p.surface,
        shape: RoundedRectangleBorder(borderRadius: Radii.rMd, side: primary ? BorderSide.none : BorderSide(color: p.border)),
        child: InkWell(
          key: Key('homeAction-$keyName'),
          borderRadius: Radii.rMd,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s1, vertical: Space.s3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: primary ? p.onAccentFill.withValues(alpha: 0.16) : p.accentSoft, borderRadius: Radii.rSm),
                    child: Icon(icon, size: IconSizes.sm, color: primary ? p.onAccentFill : p.accentFg),
                  ),
                  const SizedBox(height: Space.s2),
                  Text(label, textAlign: TextAlign.center, maxLines: 2, style: context.type.caption.copyWith(color: primary ? p.onAccentFill : p.textPrimary, fontWeight: FontWeight.w600)),
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
                          // the bar takes what the day label leaves (large text never overflows the chart)
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: maxV <= 0 ? 0.05 : (0.08 + 0.92 * (days[i].total / maxV)).clamp(0.05, 1.0),
                                widthFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: i == days.length - 1 ? p.accent : p.accentSoft,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sm)),
                                  ),
                                ),
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
  const _Attention({required this.c, required this.access, required this.alerts});
  final PosHomeTabController c;
  final PosAccess access;
  final DashboardAlertsController? alerts;

  @override
  Widget build(BuildContext context) {
    final m = access.canManage;
    String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';
    final rows = <Widget>[];
    void add(String key, IconData icon, StatusTone tone, String title, String subtitle, VoidCallback onTap) =>
        rows.add(KeyedSubtree(key: Key('homeAttention-$key'), child: AppListRow(icon: icon, tone: tone, title: title, subtitle: subtitle, onTap: onTap)));

    final unresolved = c.unresolvedSales;
    if (unresolved > 0) {
      add('sync', Icons.sync_problem_rounded, StatusTone.danger, '${n(unresolved, 'offline sale needs', 'offline sales need')} attention', 'Not on the server yet', () => Get.toNamed(Routes.posNeedsAttention));
    }
    final digital = c.digitalAttention.value;
    if (m && digital > 0) {
      add('digital', Icons.qr_code_2_rounded, StatusTone.danger, '${n(digital, 'digital payment needs', 'digital payments need')} attention', 'Raast payment to match, refund or resolve', () => Get.toNamed(Routes.posNeedsAttention));
    }
    final fiscal = alerts?.fiscalProblems.value ?? 0;
    if (m && fiscal > 0) {
      add('fiscal', Icons.gpp_maybe_outlined, StatusTone.danger, '${n(fiscal, 'fiscal document', 'fiscal documents')} not accepted', 'Retry or check them in Integrations', () => Get.toNamed(Routes.posIntegrations));
    }
    final review = c.dashboard.value?.salesNeedingReview ?? 0;
    if (m && review > 0) {
      add('review', Icons.rule_rounded, StatusTone.warning, '${n(review, 'sale', 'sales')} to review', 'Sales the server flagged for a manager', () => Get.toNamed(Routes.posNeedsAttention));
    }
    final expenses = alerts?.expensesToReview.value ?? 0;
    if (m && expenses > 0) {
      add('approvals', Icons.fact_check_outlined, StatusTone.warning, '${n(expenses, 'expense', 'expenses')} to approve', 'Recorded expenses waiting for a decision', () => Get.toNamed(Routes.posCashExpenses));
    }
    final attendance = m && Get.isRegistered<TeamClockController>() ? Get.find<TeamClockController>().anomalyCount.value : 0;
    if (attendance > 0) {
      add('attendance', Icons.schedule_rounded, StatusTone.warning, n(attendance, 'attendance problem', 'attendance problems'), 'Missing clock-outs and corrections', () => Get.toNamed(Routes.posTeamAttendance));
    }
    final low = c.lowStockCount.value ?? 0;
    if (m && low > 0) {
      add('lowStock', Icons.inventory_2_outlined, StatusTone.warning, n(low, 'low-stock item', 'low-stock items'), 'Reorder soon', () => PosHomeTabView.goTab(PosBottomNavController.stockTab));
    }
    // G3.2: lots past their date / about to pass it (the server sends this to managers and owners only)
    final ex = c.dashboard.value?.expiring;
    if (m && ex != null && (ex.expiredLots + ex.expiringIn7Days + ex.expiringIn30Days) > 0) {
      add('expiring', Icons.event_busy_outlined, ex.expiredLots > 0 ? StatusTone.danger : StatusTone.warning, 'Expiring soon',
          '${ex.expiredLots} expired · ${ex.expiringIn7Days} in 7 days · ${ex.expiringIn30Days} in 30 days', () => Get.toNamed(Routes.posStockList, arguments: const {'filter': 'expiring'}));
    }
    if (rows.isEmpty) {
      final p = context.palette;
      return AppCard(
        key: const Key('homeAllClear'),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: p.successFg),
            const SizedBox(width: Space.s3),
            Expanded(child: Text('All clear — nothing needs your attention.', style: context.type.body.copyWith(color: p.textPrimary))),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          rows[i],
        ],
      ],
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
