import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/record_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/correction_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One attendance record: who, the day, in / out, hours worked, every break, its flags and (when it was corrected) a "Corrected" badge. A manager can
/// open the Correct sheet; a correction returns the new version of the record to the list.
class AttendanceRecordView extends StatefulWidget {
  const AttendanceRecordView({super.key, required this.record, this.canCorrect, this.detailController});
  final AttendanceRecord record;

  /// tests / shots pass one; the screen otherwise makes its own for this record
  final RecordDetailController? detailController;

  /// null = decide from the signed-in role (a manager); tests pass it explicitly
  final bool? canCorrect;

  @override
  State<AttendanceRecordView> createState() => _AttendanceRecordViewState();
}

class _AttendanceRecordViewState extends State<AttendanceRecordView> {
  late AttendanceRecord record = widget.record;
  late final RecordDetailController detail;
  bool manager = false;

  @override
  void initState() {
    super.initState();
    detail =
        widget.detailController ??
        Get.put(
          RecordDetailController(employeeId: widget.record.employeeId, recordId: widget.record.recordId),
          tag: 'rec_${widget.record.recordId}',
        );
    if (widget.canCorrect != null) {
      manager = widget.canCorrect!;
    } else {
      teamGuessCanManage().then((v) {
        if (mounted) setState(() => manager = v);
      });
    }
  }

  Future<void> _correct() async {
    final r = await CorrectionSheet.open(record);
    if (r != null && mounted) {
      setState(() => record = r);
      detail.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: t.caption.copyWith(color: p.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              key: key,
              style: t.body.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(record);
      },
      child: InvScaffold(
        title: 'Attendance record',
        maxWidth: 640,
        body: ListView(
          key: const Key('recordView'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            Text(record.employeeName ?? 'Team member', style: t.title.copyWith(color: p.textPrimary)),
            const SizedBox(height: Space.s2),
            AttendanceBadges(record),
            const SizedBox(height: Space.s3),
            AppCard(
              radius: Radii.rMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row('Day', teamDay(record.clockInAt)),
                  row('Clocked in', teamTime(record.clockInAt), key: const Key('recIn')),
                  row('Clocked out', record.clockOutAt == null ? 'Not yet' : teamTime(record.clockOutAt), key: const Key('recOut')),
                  row('Worked', record.isOpen ? 'Still open' : formatHm(record.workedMinutes), key: const Key('recWorked')),
                  row('Breaks', formatHm(record.breakMinutes), key: const Key('recBreakTotal')),
                ],
              ),
            ),
            const InvSectionTitle('Breaks'),
            if (record.breaks.isEmpty)
              Text(
                'No breaks.',
                key: const Key('recNoBreaks'),
                style: t.body.copyWith(color: p.textMuted),
              )
            else
              for (var i = 0; i < record.breaks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s1),
                  child: Text(
                    '${teamTime(record.breaks[i].startAt)} - ${record.breaks[i].endAt == null ? 'now' : teamTime(record.breaks[i].endAt)} (${formatHm(record.breaks[i].minutes)})',
                    key: Key('recBreak_$i'),
                    style: t.body.copyWith(color: p.textSecondary),
                  ),
                ),
            if (record.flags.isNotEmpty) ...[const InvSectionTitle('Needs a look'), for (final f in record.flags) Text(attFlagLabel(f), style: t.body.copyWith(color: p.warningFg))],
            if (record.corrected) ...[
              const InvSectionTitle('Corrected'),
              Text(
                'A manager corrected this record. The original punches are kept; the figures above are the corrected ones.',
                key: const Key('recCorrectedNote'),
                style: t.body.copyWith(color: p.textSecondary),
              ),
            ],
            _History(c: detail),
            if (manager && !record.isVoided) ...[
              const SizedBox(height: Space.s4),
              AppButton(key: const Key('recCorrect'), label: 'Correct', icon: Icons.edit_note_rounded, variant: AppButtonVariant.secondary, onPressed: _correct),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Punches" (every raw tap with its effective time, and device vs server time when they differ) and "Corrections" (who, when, why, what changed).
class _History extends StatelessWidget {
  const _History({required this.c});
  final RecordDetailController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      if (!teamOnlineRx().value && c.detail.value == null) {
        return Padding(
          padding: const EdgeInsets.only(top: Space.s4),
          child: Text(
            'The punches and corrections need an internet connection.',
            key: const Key('recDetailOffline'),
            style: t.body.copyWith(color: p.textMuted),
          ),
        );
      }
      if (c.loading.value && c.detail.value == null) {
        return const Padding(
          padding: EdgeInsets.only(top: Space.s4),
          child: Center(child: CircularProgressIndicator(key: Key('recDetailLoading'))),
        );
      }
      final d = c.detail.value;
      if (d == null) {
        return Padding(
          padding: const EdgeInsets.only(top: Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.error.value ?? 'Could not load the punches.',
                key: const Key('recDetailError'),
                style: t.body.copyWith(color: p.dangerFg),
              ),
              const SizedBox(height: Space.s2),
              AppButton(key: const Key('recDetailRetry'), label: 'Try again', variant: AppButtonVariant.secondary, onPressed: c.load),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InvSectionTitle('Punches'),
          if (d.punches.isEmpty)
            Text(
              'No punches.',
              key: const Key('recNoPunches'),
              style: t.body.copyWith(color: p.textMuted),
            )
          else
            for (final x in d.punches) _PunchRow(x),
          if (d.corrections.isNotEmpty) ...[const InvSectionTitle('Corrections'), for (final x in d.corrections) _CorrectionRow(x)],
        ],
      );
    });
  }
}

class _PunchRow extends StatelessWidget {
  const _PunchRow(this.x);
  final AttendancePunch x;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      key: Key('punch_${x.id}'),
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${x.label} · ${teamTime(x.at)}', style: t.body.copyWith(color: p.textPrimary)),
          if (x.timesDiffer)
            Text(
              'Device time ${teamTime(x.deviceAt)} · server time ${teamTime(x.serverAt)}',
              key: Key('punchTimes_${x.id}'),
              style: t.caption.copyWith(color: p.textSecondary),
            ),
          for (final f in x.flags) Text(attFlagLabel(f), style: t.caption.copyWith(color: p.warningFg)),
        ],
      ),
    );
  }
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow(this.x);
  final AttendanceCorrection x;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final changes = [
      if (x.voided) 'Voided the record',
      if (!x.voided && x.clockInAt != null) 'Clock-in set to ${teamTime(x.clockInAt)}',
      if (!x.voided && x.clockOutAt != null) 'Clock-out set to ${teamTime(x.clockOutAt)}',
    ];
    return Padding(
      key: Key('corr_${x.id}'),
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: SizedBox(
        width: double.infinity,
        child: AppCard(
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${x.byName ?? 'A manager'}${x.at == null ? '' : ' · ${teamDayTime(x.at)}'}', style: t.body.copyWith(color: p.textPrimary)),
              for (final c in changes) Text(c, style: t.body.copyWith(color: p.textSecondary)),
              if (x.reason != null)
                Text(
                  'Reason: ${x.reason}',
                  key: Key('corrReason_${x.id}'),
                  style: t.caption.copyWith(color: p.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
