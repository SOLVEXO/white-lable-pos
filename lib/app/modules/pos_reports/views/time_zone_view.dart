import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/time_zone_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.0 store time zone: where the store's day starts and ends for every report, the daybook and the attendance report. The owner picks it from
/// a searchable list (Asia/Karachi first); everyone else sees it read only. Online only.
class TimeZoneView extends StatefulWidget {
  const TimeZoneView({super.key, this.controller});
  final TimeZoneController? controller;
  @override
  State<TimeZoneView> createState() => _TimeZoneViewState();
}

class _TimeZoneViewState extends State<TimeZoneView> {
  late final TimeZoneController c = widget.controller ?? Get.put(TimeZoneController(), tag: 'tz_${identityHashCode(this)}');
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    if (widget.controller == null) Get.delete<TimeZoneController>(tag: 'tz_${identityHashCode(this)}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Store time zone',
      maxWidth: 720,
      body: Obx(() {
        final z = c.zone.value;
        if (!reportsOnlineRx().value && z == null) return const ReportsNeedsInternet(subject: 'The store time zone');
        if (z == null && c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('tzLoading')));
        if (z == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        final zones = c.zones;
        return ListView(
          key: const Key('tzList'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            AppCard(
              key: const Key('tzCurrent'),
              radius: Radii.rMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('The store runs on', style: t.caption.copyWith(color: p.textSecondary)),
                  Text(
                    z.timeZone,
                    key: const Key('tzName'),
                    style: t.title.copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    'Today in the store: ${storeDayLabel(z.today)}',
                    key: const Key('tzToday'),
                    style: t.body.copyWith(color: p.textSecondary),
                  ),
                  if (!z.explicit) Text('Not set yet: this is the default for the store\'s country${z.country == null ? '' : ' (${z.country})'}.', style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: Space.s3),
            Text('Every report, the daybook and the attendance report count days from midnight to midnight in this zone.', style: t.bodySmall.copyWith(color: p.textSecondary)),
            const SizedBox(height: Space.s3),
            if (!c.canEdit.value)
              const ReportInfo(key: Key('tzReadOnly'), 'Only the owner can change the store\'s time zone.', icon: Icons.lock_outline_rounded)
            else ...[
              if (c.saved.value != null) ReportInfo(key: const Key('tzSaved'), c.saved.value!, icon: Icons.check_circle_outline_rounded),
              if (c.saveError.value != null) ReportInfo(key: const Key('tzError'), c.saveError.value!, warn: true),
              AppTextField(
                key: const Key('tzSearch'),
                label: 'Search',
                controller: _search,
                hint: 'Search, e.g. Karachi or London',
                prefixIcon: Icons.search_rounded,
                onChanged: (v) => c.search.value = v,
              ),
              const SizedBox(height: Space.s2),
              if (zones.isEmpty) Text('No zone matches "${c.search.value}".', style: t.body.copyWith(color: p.textMuted)),
              for (final name in zones)
                RadioListTile<String>(
                  key: Key('tz_$name'),
                  value: name,
                  groupValue: z.timeZone,
                  title: Text(name.replaceAll('_', ' ')),
                  dense: true,
                  onChanged: c.saving.value ? null : (v) => v == null ? null : c.choose(v),
                ),
            ],
          ],
        );
      }),
    );
  }
}
