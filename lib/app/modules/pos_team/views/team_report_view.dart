import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/team_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.p, required this.grace});
  final ReportPerson p;
  final int grace;
  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = context.type;
    Widget stat(String label, String value, {Key? key, Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption.copyWith(color: pal.textSecondary)),
          Text(
            value,
            key: key,
            style: t.amountMd.copyWith(color: color ?? pal.textPrimary),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('reportPerson_${p.employeeId}'),
        radius: Radii.rMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.employeeName ?? 'Team member', style: t.subtitle.copyWith(color: pal.textPrimary)),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                stat('Worked', formatHm(p.workedMinutes), key: Key('repWorked_${p.employeeId}')),
                stat('Days', '${p.daysWorked}'),
                stat('Breaks', formatHm(p.breakMinutes)),
              ],
            ),
            const SizedBox(height: Space.s2),
            Row(
              children: [
                stat('Late (>${grace}m)', p.lateCount == 0 ? '0' : '${p.lateCount} · ${p.lateMinutes}m', key: Key('repLate_${p.employeeId}'), color: p.lateCount > 0 ? pal.warningFg : null),
                stat('No clock-out', '${p.missingClockOuts}', color: p.missingClockOuts > 0 ? pal.warningFg : null),
                stat('Corrected', '${p.corrections}'),
              ],
            ),
            const SizedBox(height: Space.s2),
            Text(
              'Rostered ${formatHm(p.rosteredMinutes)} · worked ${formatHm(p.workedMinutes)}',
              key: Key('repRostered_${p.employeeId}'),
              style: t.caption.copyWith(color: pal.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The attendance report: a period picker, per person hours worked / days / breaks / late arrivals / missing clock-outs / corrections / rostered vs worked,
/// the totals and a shareable PDF. A cashier sees only themself. Online only.
class TeamReportView extends StatelessWidget {
  TeamReportView({super.key, TeamReportController? controller}) : c = controller ?? Get.put(TeamReportController());
  final TeamReportController c;

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 2), lastDate: now);
    if (r != null) c.setCustom(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Attendance report',
      maxWidth: 760,
      actions: [
        Obx(
          () => !c.canManageHint.value || c.people.isEmpty
              ? const SizedBox.shrink()
              : PopupMenuButton<String?>(
                  key: const Key('repPerson'),
                  tooltip: 'Person',
                  icon: Icon(c.personId.value == null ? Icons.groups_2_outlined : Icons.person_rounded),
                  onSelected: c.setPerson,
                  itemBuilder: (_) => [
                    const PopupMenuItem<String?>(value: null, child: Text('Everyone')),
                    for (final e in c.people) PopupMenuItem<String?>(key: Key('repPerson_${e.id}'), value: e.id, child: Text(e.name)),
                  ],
                ),
        ),
      ],
      body: Obx(() {
        if (!teamOnlineRx().value && c.report.value == null) return const TeamNeedsInternet(subject: 'The report');
        final r = c.report.value;
        if (c.loading.value && r == null) return const Center(child: CircularProgressIndicator(key: Key('teamLoading')));
        if (r == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const Key('repPeriods'),
                  spacing: Space.s2,
                  runSpacing: Space.s1,
                  children: [
                    for (final per in ReportPeriod.values)
                      ChoiceChip(
                        key: Key('repPeriod_${per.name}'),
                        label: Text(per.label),
                        selected: c.period.value == per,
                        onSelected: (_) => per == ReportPeriod.custom ? _pickRange(context) : c.setPeriod(per),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  key: const Key('reportList'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
                  children: [
                    AppCard(
                      key: const Key('reportTotals'),
                      radius: Radii.rMd,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total hours worked', style: t.caption.copyWith(color: p.textSecondary)),
                          Text(
                            formatHm(r.totalWorkedMinutes),
                            key: const Key('reportTotalHours'),
                            style: t.amountLg.copyWith(color: p.textPrimary),
                          ),
                          const SizedBox(height: Space.s1),
                          Text(
                            '${r.totalLateCount} late · ${r.totalMissingClockOuts} missing clock-out${r.totalMissingClockOuts == 1 ? '' : 's'} (late = more than ${r.lateGraceMinutes} min after the rostered start)',
                            style: t.caption.copyWith(color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.s3),
                    if (r.people.isEmpty)
                      const EmptyState(icon: Icons.insights_outlined, title: 'No attendance', message: 'Nobody clocked in during this period.')
                    else
                      for (final person in r.people) _PersonCard(p: person, grace: r.lateGraceMinutes),
                    if (r.people.isNotEmpty) ...[
                      const SizedBox(height: Space.s3),
                      AppButton(key: const Key('reportShare'), label: 'Share PDF', icon: Icons.ios_share_rounded, loading: c.busy.value, onPressed: c.sharePdf),
                    ],
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
