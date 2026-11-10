import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/attendance_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Attendance history: period and status chips, hours, and every record with its badges (open / closed / voided / corrected / flags). A cashier sees only
/// their own (the server filters); a manager sees everyone and may pick a person. Online only.
class AttendanceView extends StatelessWidget {
  AttendanceView({super.key, AttendanceController? controller}) : c = controller ?? Get.put(AttendanceController());
  final AttendanceController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Attendance',
      maxWidth: 760,
      actions: [
        Obx(
          () => !c.canManageHint.value || c.people.isEmpty
              ? const SizedBox.shrink()
              : PopupMenuButton<String?>(
                  key: const Key('attPerson'),
                  tooltip: 'Person',
                  icon: Icon(c.personId.value == null ? Icons.groups_2_outlined : Icons.person_rounded),
                  onSelected: c.setPerson,
                  itemBuilder: (_) => [
                    const PopupMenuItem<String?>(value: null, child: Text('Everyone')),
                    for (final e in c.people) PopupMenuItem<String?>(key: Key('attPerson_${e.id}'), value: e.id, child: Text(e.name)),
                  ],
                ),
        ),
      ],
      body: Obx(() {
        if (!teamOnlineRx().value) return const TeamNeedsInternet(subject: 'Attendance');
        if (c.loading.value && c.records.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('teamLoading')));
        if (c.error.value != null && c.records.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        final list = c.visible;
        final showName = c.canManageHint.value || c.records.map((r) => r.employeeId).toSet().length > 1;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('attPeriods'),
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    for (final per in AttendancePeriod.values)
                      ChoiceChip(key: Key('attPeriod_${per.name}'), label: Text(per.label), selected: c.period.value == per, onSelected: (_) => c.setPeriod(per)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('attFilters'),
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    for (final (id, label) in attendanceFilters) ChoiceChip(key: Key('attFilter_$id'), label: Text(label), selected: c.filter.value == id, onSelected: (_) => c.setFilter(id)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Worked ${formatHm(c.workedMinutes)} · breaks ${formatHm(c.breakMinutes)}',
                      key: const Key('attTotals'),
                      style: t.subtitle.copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: list.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [EmptyState(icon: Icons.schedule_rounded, title: 'No attendance', message: 'Nobody clocked in during this period.')],
                      )
                    : ListView.builder(
                        key: const Key('attList'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                        itemCount: list.length,
                        itemBuilder: (_, i) => AttendanceTile(
                          record: list[i],
                          showName: showName,
                          onTap: () => Get.toNamed(Routes.posTeamRecord, arguments: {'record': list[i]})?.then((r) {
                            if (r is AttendanceRecord) c.applyCorrected(r);
                          }),
                        ),
                      ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
