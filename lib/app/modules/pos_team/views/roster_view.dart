import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/roster_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/shift_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The weekly roster, Monday to Sunday: every day with its shifts (who, when, where). The signed-in person's own shifts are highlighted. A manager adds,
/// edits and cancels shifts (online only). Offline the last week the till saw is shown read only with "Last synced".
class RosterView extends StatelessWidget {
  RosterView({super.key, RosterController? controller}) : c = controller ?? Get.put(RosterController());
  final RosterController c;

  Future<void> _edit(BuildContext context, {RosterShift? shift, DateTime? day}) async {
    final s = await ShiftSheet.open(existing: shift, day: day);
    if (s == null) return;
    c.applySaved(s);
    CustomAppSnackbar.success(shift == null ? 'Shift added.' : 'Shift saved.');
  }

  Future<void> _cancel(BuildContext context, RosterShift s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this shift?'),
        content: Text('${s.employeeName ?? 'Team member'}, ${teamDay(s.startAt)} ${s.range}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
          TextButton(key: const Key('rosterCancelYes'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Cancel shift')),
        ],
      ),
    );
    if (ok == true) await c.cancel(s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Roster',
      maxWidth: 760,
      actions: [Obx(() => c.canEdit ? IconButton(key: const Key('rosterAdd'), tooltip: 'Add shift', icon: const Icon(Icons.add_rounded), onPressed: () => _edit(context)) : const SizedBox.shrink())],
      body: Obx(() {
        if (c.loading.value && c.shifts.isEmpty && !c.needsInternet.value) return const Center(child: CircularProgressIndicator(key: Key('teamLoading')));
        if (c.needsInternet.value) return const TeamNeedsInternet(subject: 'The roster');
        if (c.error.value != null && c.shifts.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        final ws = c.weekStart.value;
        final label = '${DateFormat('d MMM').format(ws)} - ${DateFormat('d MMM yyyy').format(ws.add(const Duration(days: 6)))}';
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s1),
              child: Row(
                children: [
                  IconButton(key: const Key('rosterPrev'), tooltip: 'Previous week', icon: const Icon(Icons.chevron_left_rounded), onPressed: c.previousWeek),
                  Expanded(
                    child: TextButton(
                      key: const Key('rosterWeek'),
                      onPressed: c.thisWeek,
                      child: Text(label, style: t.subtitle.copyWith(color: p.textPrimary)),
                    ),
                  ),
                  IconButton(key: const Key('rosterNext'), tooltip: 'Next week', icon: const Icon(Icons.chevron_right_rounded), onPressed: c.nextWeek),
                ],
              ),
            ),
            if (c.readOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
                child: TeamLastSyncedBanner(asOf: c.asOf.value!),
              ),
            if (c.notice.value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
                child: Text(
                  c.notice.value!,
                  key: const Key('rosterNotice'),
                  style: t.body.copyWith(color: p.warningFg),
                ),
              ),
            if (c.actionError.value != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
                child: SupplyErrorText(c.actionError.value, errorKey: const Key('rosterError')),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  key: const Key('rosterList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s8),
                  children: [
                    for (final day in c.days)
                      _Day(
                        day: day,
                        c: c,
                        onEdit: (s) => _edit(context, shift: s),
                        onCancel: (s) => _cancel(context, s),
                        onAdd: () => _edit(context, day: day),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.c, required this.onEdit, required this.onCancel, required this.onAdd});
  final DateTime day;
  final RosterController c;
  final void Function(RosterShift) onEdit, onCancel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      final list = c.shiftsOn(day);
      final today = DateTime.now();
      final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
      return Padding(
        key: Key('rosterDay_${teamWeekKey(day)}'),
        padding: const EdgeInsets.only(bottom: Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(DateFormat('EEEE d MMM').format(day), style: t.subtitle.copyWith(color: isToday ? p.accentFg : p.textPrimary)),
                ),
                if (c.canEdit)
                  IconButton(key: Key('rosterAddDay_${teamWeekKey(day)}'), tooltip: 'Add shift on this day', icon: const Icon(Icons.add_circle_outline_rounded, size: 20), onPressed: onAdd),
              ],
            ),
            if (list.isEmpty)
              Text('No shifts', style: t.caption.copyWith(color: p.textMuted))
            else
              for (final s in list) ShiftTile(shift: s, mine: c.isMine(s), locationName: s.locationId == null ? null : c.locations[s.locationId!], onTap: c.canEdit ? () => onEdit(s) : null),
            if (c.canEdit)
              ...list.map(
                (s) => Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: Key('rosterCancel_${s.id}'), onPressed: () => onCancel(s), child: Text('Cancel ${teamTime(s.startAt)} shift')),
                ),
              ),
          ],
        ),
      );
    });
  }
}
