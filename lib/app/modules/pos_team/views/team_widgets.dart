import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "Needs internet": attendance history, corrections, anomalies, the report and roster edits need the server (clocking in / out does not, and the
/// roster is readable from the last copy).
class TeamNeedsInternet extends StatelessWidget {
  const TeamNeedsInternet({super.key, this.subject = 'This screen'});
  final String subject;
  @override
  Widget build(BuildContext context) => EmptyState(
    key: const Key('teamNeedsInternet'),
    icon: Icons.wifi_off_rounded,
    title: 'Needs internet',
    message: '$subject needs an internet connection. Connect the till and it will load by itself.',
    tone: context.palette.warningFg,
  );
}

/// "Last synced 9 Nov, 14:32 - read only" above a remembered roster.
class TeamLastSyncedBanner extends StatelessWidget {
  const TeamLastSyncedBanner({super.key, required this.asOf, this.subject = 'roster'});
  final DateTime asOf;
  final String subject;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('teamLastSynced'),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: p.warningFg),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text('Last synced ${invDateTime(asOf)} - the $subject is read only offline', style: context.type.caption.copyWith(color: p.warningFg)),
          ),
        ],
      ),
    );
  }
}

StatusTone attStatusTone(String s) => switch (s) {
  AttStatus.open => StatusTone.info,
  AttStatus.closed => StatusTone.neutral,
  AttStatus.voided => StatusTone.danger,
  _ => StatusTone.neutral,
};

/// Open / Closed / Voided, plus "Corrected" and one badge per flag.
class AttendanceBadges extends StatelessWidget {
  const AttendanceBadges(this.record, {super.key});
  final AttendanceRecord record;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s2,
    runSpacing: Space.s1,
    children: [
      StatusBadge(AttStatus.label(record.status), tone: attStatusTone(record.status)),
      if (record.corrected) const StatusBadge('Corrected', tone: StatusTone.accent, icon: Icons.edit_note_rounded),
      for (final f in record.flags) StatusBadge(attFlagLabel(f), tone: StatusTone.warning),
    ],
  );
}

/// One attendance record row: who (managers), the day, in - out, hours worked and breaks, and its badges.
class AttendanceTile extends StatelessWidget {
  const AttendanceTile({super.key, required this.record, required this.showName, required this.onTap});
  final AttendanceRecord record;
  final bool showName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('att_${record.recordId}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showName)
                    Text(
                      record.employeeName ?? 'Team member',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.subtitle.copyWith(color: p.textPrimary),
                    ),
                  Text(
                    '${teamDay(record.clockInAt)} · ${teamTime(record.clockInAt)} - ${record.clockOutAt == null ? 'now' : teamTime(record.clockOutAt)}',
                    style: (showName ? t.body : t.subtitle).copyWith(color: showName ? p.textSecondary : p.textPrimary),
                  ),
                  Text(
                    record.isOpen ? 'Still open' : 'Worked ${formatHm(record.workedMinutes)}${record.breakMinutes > 0 ? ' · breaks ${formatHm(record.breakMinutes)}' : ''}',
                    key: Key('attHours_${record.recordId}'),
                    style: t.caption.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(height: Space.s1),
                  AttendanceBadges(record),
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

/// One roster shift: who, when, where, note. The signed-in person's own shifts are highlighted.
class ShiftTile extends StatelessWidget {
  const ShiftTile({super.key, required this.shift, required this.mine, this.locationName, this.onTap});
  final RosterShift shift;
  final bool mine;
  final String? locationName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('shift_${shift.id}'),
        radius: Radii.rMd,
        color: mine ? p.accentSoft : null,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(shift.range, style: t.subtitle.copyWith(color: p.textPrimary)),
                      if (mine) const StatusBadge('You', tone: StatusTone.accent),
                    ],
                  ),
                  if (!mine) Text(shift.employeeName ?? 'Team member', style: t.body.copyWith(color: p.textSecondary)),
                  Text(['${formatHm(shift.minutes)} h', if (locationName != null) locationName!, if (shift.note != null) shift.note!].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

Future<DateTime?> pickTeamDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(context: context, initialDate: initial ?? now, firstDate: first ?? DateTime(now.year - 2), lastDate: last ?? DateTime(now.year + 2));
}

Future<TimeOfDay?> pickTeamTime(BuildContext context, {TimeOfDay? initial}) => showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now());

/// A tappable field showing a value ("Pick a time" when none).
class TeamPickField extends StatelessWidget {
  const TeamPickField({super.key, required this.label, required this.value, required this.onPick, this.icon = Icons.schedule_rounded, this.onClear});
  final String label;
  final String? value;
  final VoidCallback onPick;
  final IconData icon;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      onTap: onPick,
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s3),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.textMuted),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(value == null ? label : '$label: $value', style: context.type.body.copyWith(color: value == null ? p.textMuted : p.textPrimary)),
          ),
          if (value != null && onClear != null) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClear),
        ],
      ),
    );
  }
}

/// re-exported so the team screens use the same "Waiting to sync" badge as the cash screens
class TeamWaitingBadge extends StatelessWidget {
  const TeamWaitingBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => WaitingToSyncBadge(count: count);
}
