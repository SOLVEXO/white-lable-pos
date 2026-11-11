import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/on_behalf_clock_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The clock: a big Clock in / Clock out button, Start / End break, who and since when, "Waiting to sync" events (offline), today's punches and my next
/// shifts. It acts for whoever is signed in with their PIN (the person is named at the top). Offline it still works: taps are saved and sent later.
class TeamClockView extends StatefulWidget {
  const TeamClockView({super.key, this.controller});
  final TeamClockController? controller;

  @override
  State<TeamClockView> createState() => _TeamClockViewState();
}

class _TeamClockViewState extends State<TeamClockView> {
  late final TeamClockController c = widget.controller ?? (Get.isRegistered<TeamClockController>() ? Get.find<TeamClockController>() : Get.put(TeamClockController()));

  @override
  void initState() {
    super.initState();
    // the person signed in may have changed since the app started: look again every time the clock is opened
    Future.microtask(() {
      if (!c.loading.value || c.me.value != null) c.load();
    });
  }

  Future<void> _tap(String action) async {
    final o = await c.perform(action);
    if (o == ClockOutcome.queued) CustomAppSnackbar.success('Saved on this device. It will sync when the till is online.');
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Clock in',
      maxWidth: 640,
      body: Obx(() {
        if (c.loading.value && c.me.value == null && !c.needsPin.value) return const Center(child: CircularProgressIndicator(key: Key('teamLoading')));
        if (c.needsPin.value) {
          return const EmptyState(
            key: Key('teamNeedsPin'),
            icon: Icons.pin_outlined,
            title: 'Sign in with your PIN',
            message: 'Attendance belongs to a team member. Sign in with your staff PIN, then clock in.',
          );
        }
        if (c.error.value != null && c.me.value == null) return InvErrorState(message: c.error.value!, onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context));
      }),
    );
  }

  Widget _content(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final s = c.state;
    final waiting = c.waiting;
    final statusText = !s.clockedIn ? 'Not clocked in' : (s.onBreak ? (s.breakAt != null ? 'On a break since ${teamTime(s.breakAt)}' : 'On a break') : 'Clocked in since ${teamTime(s.since)}');
    final primary = !s.clockedIn ? ClockAction.clockIn : (s.onBreak ? ClockAction.breakEnd : ClockAction.clockOut);
    final second = !s.clockedIn ? null : (s.onBreak ? ClockAction.clockOut : ClockAction.breakStart);
    return ListView(
      key: const Key('clockList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Text(
          c.employeeName.value.isEmpty ? 'Clocking in as the signed-in team member' : 'Clocking in as ${c.employeeName.value}',
          key: const Key('clockWho'),
          style: t.caption.copyWith(color: p.textSecondary),
        ),
        Text('Not you? Sign out and sign in with your own PIN.', style: t.caption.copyWith(color: p.textMuted)),
        const SizedBox(height: Space.s3),
        if (c.isOffline)
          Container(
            key: const Key('clockOffline'),
            margin: const EdgeInsets.only(bottom: Space.s3),
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: p.warningFg),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text('Offline. Your taps are saved on this device and sent when the till is online.', style: t.caption.copyWith(color: p.warningFg)),
                ),
              ],
            ),
          ),
        AppCard(
          key: const Key('clockState'),
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Space.s2,
                runSpacing: Space.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    statusText,
                    key: const Key('clockStatus'),
                    style: t.title.copyWith(color: p.textPrimary),
                  ),
                  if (waiting.isNotEmpty) TeamWaitingBadge(count: waiting.length),
                ],
              ),
              if (c.me.value?.asOf != null) Text('As of ${invDateTime(c.me.value!.asOf)}', style: t.caption.copyWith(color: p.textMuted)),
            ],
          ),
        ),
        const SizedBox(height: Space.s4),
        AppButton(key: Key('clock_$primary'), label: ClockAction.label(primary), size: AppButtonSize.lg, loading: c.busy.value, onPressed: c.canDo(primary) ? () => _tap(primary) : null),
        if (second != null) ...[
          const SizedBox(height: Space.s2),
          AppButton(key: Key('clock_$second'), label: ClockAction.label(second), variant: AppButtonVariant.secondary, onPressed: c.canDo(second) ? () => _tap(second) : null),
        ],
        if (c.notice.value != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s3),
            child: Text(
              c.notice.value!,
              key: const Key('clockNotice'),
              style: t.body.copyWith(color: p.successFg),
            ),
          ),
        SupplyErrorText(c.actionError.value, errorKey: const Key('clockError')),
        // G5.4: someone else's clock — their PIN or a manager's, online only
        const SizedBox(height: Space.s2),
        AppButton(key: const Key('clockOnBehalf'), label: 'Clock someone else in / out', icon: Icons.people_outline_rounded, variant: AppButtonVariant.ghost, onPressed: c.busy.value ? null : () => OnBehalfClockSheet.open(c)),
        if (waiting.isNotEmpty) ...[
          const InvSectionTitle('Waiting to sync'),
          for (final w in waiting)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s1),
              child: Text(
                '${ClockAction.pastLabel(w.action)} at ${teamTime(w.deviceAt)}',
                key: Key('waiting_${w.id}'),
                style: t.body.copyWith(color: p.textSecondary),
              ),
            ),
        ],
        const InvSectionTitle('Today'),
        if (c.today.isEmpty)
          Text(
            'No punches yet today.',
            key: const Key('clockNoToday'),
            style: t.body.copyWith(color: p.textMuted),
          )
        else
          for (final r in c.today)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('todayRec_${r.recordId}'),
                radius: Radii.rMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${teamTime(r.clockInAt)} - ${r.clockOutAt == null ? 'now' : teamTime(r.clockOutAt)}', style: t.subtitle.copyWith(color: p.textPrimary)),
                    for (final b in r.breaks)
                      Text('Break ${teamTime(b.startAt)} - ${b.endAt == null ? 'now' : teamTime(b.endAt)} (${formatHm(b.minutes)})', style: t.caption.copyWith(color: p.textSecondary)),
                    if (!r.isOpen) Text('Worked ${formatHm(r.workedMinutes)}', style: t.caption.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
            ),
        const InvSectionTitle('My next shifts'),
        if ((c.me.value?.nextShifts ?? const []).isEmpty)
          Text(
            'No shifts rostered.',
            key: const Key('clockNoShifts'),
            style: t.body.copyWith(color: p.textMuted),
          )
        else
          for (final sh in c.me.value!.nextShifts) ShiftTile(shift: sh, mine: true),
      ],
    );
  }
}
