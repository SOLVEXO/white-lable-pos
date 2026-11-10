import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/correction_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A manager corrects a record: change the clock-in / clock-out time, add a missing clock-out, or void it. The reason is REQUIRED. It is saved as a new
/// entry (the original punches are kept). Closes with the corrected [AttendanceRecord].
class CorrectionSheet extends StatefulWidget {
  const CorrectionSheet({super.key, required this.controller});
  final CorrectionController controller;

  static Future<AttendanceRecord?> open(AttendanceRecord record, {CorrectionController? controller}) => AppBottomSheet.showGet<AttendanceRecord>(
    CorrectionSheet(controller: controller ?? CorrectionController(record: record)),
    title: 'Correct attendance',
  );

  @override
  State<CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<CorrectionSheet> {
  final _reason = TextEditingController();
  CorrectionController get c => widget.controller;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final d = await pickTeamDate(context, initial: initial, last: DateTime.now());
    if (d == null || !mounted) return null;
    final t = await pickTeamTime(
      context,
      initial: initial == null ? null : TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    final r = await c.submit();
    if (r != null && mounted) Get.back<AttendanceRecord>(result: r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final r = c.record;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${r.employeeName ?? 'Team member'} · ${teamDay(r.clockInAt)}', style: t.subtitle.copyWith(color: p.textPrimary)),
        Text('The original punches are kept. A correction is a new entry with your reason.', style: t.caption.copyWith(color: p.textMuted)),
        const SizedBox(height: Space.s3),
        Obx(
          () => IgnorePointer(
            ignoring: c.voided.value,
            child: Opacity(
              opacity: c.voided.value ? 0.4 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TeamPickField(
                    key: const Key('corrIn'),
                    label: 'Clock-in',
                    value: c.clockInAt.value == null ? null : teamDayTime(c.clockInAt.value),
                    onPick: () async {
                      final d = await _pickDateTime(c.clockInAt.value);
                      if (d != null) c.clockInAt.value = d;
                    },
                  ),
                  const SizedBox(height: Space.s2),
                  TeamPickField(
                    key: const Key('corrOut'),
                    label: r.clockOutAt == null ? 'Add clock-out' : 'Clock-out',
                    value: c.clockOutAt.value == null ? null : teamDayTime(c.clockOutAt.value),
                    onPick: () async {
                      final d = await _pickDateTime(c.clockOutAt.value ?? c.clockInAt.value);
                      if (d != null) c.clockOutAt.value = d;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Obx(
          () => SwitchListTile(
            key: const Key('corrVoid'),
            contentPadding: EdgeInsets.zero,
            value: c.voided.value,
            onChanged: c.setVoided,
            title: Text('Void this record', style: t.body.copyWith(color: p.textPrimary)),
            subtitle: Text('It stops counting towards hours.', style: t.caption.copyWith(color: p.textMuted)),
          ),
        ),
        AppTextField(key: const Key('corrReason'), label: 'Reason (required)', controller: _reason, maxLines: 2, onChanged: (s) => c.reason.value = s),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('corrError'))),
        Obx(
          () => teamOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Needs internet. A correction can only be saved while the till is online.',
                    key: const Key('corrOffline'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(
          () => AppButton(
            key: const Key('corrSave'),
            label: c.voided.value ? 'Void record' : 'Save correction',
            variant: c.voided.value ? AppButtonVariant.danger : AppButtonVariant.primary,
            loading: c.busy.value,
            onPressed: c.canSubmit && teamOnlineRx().value ? _save : null,
          ),
        ),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
