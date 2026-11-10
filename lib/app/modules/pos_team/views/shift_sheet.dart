import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/shift_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Add or edit a roster shift (managers): person, day, start and end, an optional location and note. The server's refusals are shown in words (an
/// overlap names the clashing time); a warning (a 60-hour week) is shown after saving, never as a block. Closes with the saved [RosterShift].
class ShiftSheet extends StatefulWidget {
  const ShiftSheet({super.key, required this.controller});
  final ShiftController controller;

  static Future<RosterShift?> open({RosterShift? existing, DateTime? day, ShiftController? controller}) => AppBottomSheet.showGet<RosterShift>(
    ShiftSheet(
      controller: controller ?? ShiftController(existing: existing, presetDay: day),
    ),
    title: existing == null ? 'Add shift' : 'Edit shift',
  );

  @override
  State<ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends State<ShiftSheet> {
  final _note = TextEditingController();
  ShiftController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _note.text = c.note.value;
    c.onInit();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = await c.submit();
    if (s != null && mounted) Get.back<RosterShift>(result: s);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    String? time(TimeOfDay? x) => x == null ? null : '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Team member', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            runSpacing: Space.s1,
            children: [for (final e in c.people) ChoiceChip(key: Key('shiftPerson_${e.id}'), label: Text(e.name), selected: c.employeeId.value == e.id, onSelected: (_) => c.employeeId.value = e.id)],
          ),
        ),
        const SizedBox(height: Space.s3),
        Obx(
          () => TeamPickField(
            key: const Key('shiftDay'),
            label: 'Day',
            icon: Icons.event_rounded,
            value: c.date.value == null ? null : teamDay(c.date.value),
            onPick: () async {
              final d = await pickTeamDate(context, initial: c.date.value);
              if (d != null) c.date.value = d;
            },
          ),
        ),
        const SizedBox(height: Space.s2),
        Obx(
          () => Row(
            children: [
              Expanded(
                child: TeamPickField(
                  key: const Key('shiftStart'),
                  label: 'Start',
                  value: time(c.start.value),
                  onPick: () async {
                    final x = await pickTeamTime(context, initial: c.start.value);
                    if (x != null) c.start.value = x;
                  },
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: TeamPickField(
                  key: const Key('shiftEnd'),
                  label: 'End',
                  value: time(c.end.value),
                  onPick: () async {
                    final x = await pickTeamTime(context, initial: c.end.value);
                    if (x != null) c.end.value = x;
                  },
                ),
              ),
            ],
          ),
        ),
        Obx(() {
          final s = c.startAt, e = c.endAt;
          return s == null || e == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s1),
                  child: Text(
                    '${formatHm(e.difference(s).inMinutes)} hours${e.day != s.day ? ' (ends the next day)' : ''}',
                    key: const Key('shiftLength'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                );
        }),
        Obx(
          () => c.locations.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    children: [
                      for (final l in c.locations.entries)
                        ChoiceChip(key: Key('shiftLoc_${l.key}'), label: Text(l.value), selected: c.locationId.value == l.key, onSelected: (v) => c.locationId.value = v ? l.key : null),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('shiftNote'), label: 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('shiftError'))),
        Obx(
          () => teamOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Needs internet. The roster can only be changed while the till is online.',
                    key: const Key('shiftOffline'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('shiftSave'), label: c.isEdit ? 'Save changes' : 'Add shift', loading: c.busy.value, onPressed: c.canSubmit && teamOnlineRx().value ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
