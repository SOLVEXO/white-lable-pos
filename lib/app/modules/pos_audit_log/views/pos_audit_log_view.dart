import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart' show dayKey;
import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.3 activity log: filters (store days, type, person), CSV export and the Integrity panel.
class PosAuditLogView extends StatelessWidget {
  PosAuditLogView({super.key, PosAuditLogController? controller})
    : c = controller ?? (Get.isRegistered<PosAuditLogController>() ? Get.find<PosAuditLogController>() : Get.put(PosAuditLogController()));

  final PosAuditLogController c;

  Future<void> _pick(BuildContext context) async {
    final (a, b) = c.days;
    final today = DateTime.tryParse(c.today.value) ?? DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: DateTime(today.year - 2), lastDate: today, initialDateRange: DateTimeRange(start: a, end: b));
    if (r != null) c.setCustom(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Activity log',
      maxWidth: 900,
      actions: [
        Obx(
          () => IconButton(
            key: const Key('auditExport'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: c.logs.isEmpty || c.exporting.value ? null : c.exportCsv,
          ),
        ),
      ],
      body: Obx(() {
        final online = reportsOnlineRx().value;
        if (!online && c.logs.isEmpty) return const ReportsNeedsInternet(subject: 'The activity log');
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) c.loadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: c.refreshData,
            child: ListView(
              key: const Key('auditList'),
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
              children: [
                _Filters(c: c, onCustom: () => _pick(context)),
                _IntegrityPanel(c: c),
                InvSectionTitle(c.isLoading.value ? 'Activity' : 'Activity · ${c.total.value}'),
                if (c.isLoading.value && c.logs.isEmpty)
                  const Padding(padding: EdgeInsets.all(Space.s6), child: Center(child: CircularProgressIndicator(key: Key('auditLoading'))))
                else if (c.error.value != null && c.logs.isEmpty)
                  InvErrorState(message: c.error.value!, onRetry: c.loadLogs)
                else if (c.logs.isEmpty)
                  const EmptyState(key: Key('auditEmpty'), icon: Icons.history_rounded, title: 'Nothing recorded', message: 'No activity matches these filters.')
                else ...[
                  for (final l in c.logs) _LogRow(log: l, who: c.nameOf(l.employeeId)),
                  if (c.isLoadingMore.value) const Padding(padding: EdgeInsets.all(Space.s3), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.c, required this.onCustom});
  final PosAuditLogController c;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final (a, b) = c.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: const Key('auditDateStrip'),
          spacing: Space.s2,
          runSpacing: Space.s1,
          children: [
            for (final r in const [ReportRange.today, ReportRange.yesterday, ReportRange.last7, ReportRange.last30, ReportRange.custom])
              ChoiceChip(
                key: Key('auditRange_${r.name}'),
                visualDensity: VisualDensity.compact,
                label: Text(r.label),
                avatar: r == ReportRange.custom ? const Icon(Icons.date_range_rounded, size: 16) : null,
                selected: c.range.value == r,
                onSelected: (_) => r == ReportRange.custom ? onCustom() : c.setRange(r),
              ),
          ],
        ),
        const SizedBox(height: Space.s1),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s2,
          runSpacing: Space.s1,
          children: [
            Text(a == b ? storeDayLabel(dayKey(a)) : '${storeDayLabel(dayKey(a))} - ${storeDayLabel(dayKey(b))}', key: const Key('auditPeriod'), style: t.caption.copyWith(color: p.textSecondary)),
            _Menu(
              key: const Key('auditTypeFilter'),
              icon: Icons.filter_list_rounded,
              label: c.type.value == null ? 'All types' : (auditTypes[c.type.value] ?? c.type.value!),
              items: {null: 'All types', ...auditTypes},
              onSelected: c.setType,
            ),
            if (c.people.isNotEmpty)
              _Menu(
                key: const Key('auditPersonFilter'),
                icon: Icons.person_outline_rounded,
                label: c.employeeId.value == null ? 'Everyone' : c.nameOf(c.employeeId.value),
                items: {null: 'Everyone', ...c.people},
                onSelected: c.setEmployee,
              ),
          ],
        ),
      ],
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({super.key, required this.icon, required this.label, required this.items, required this.onSelected});
  final IconData icon;
  final String label;
  final Map<String?, String> items;
  final ValueChanged<String?> onSelected;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
    tooltip: label,
    onSelected: onSelected,
    itemBuilder: (_) => [for (final e in items.entries) PopupMenuItem<String?>(value: e.key, child: Text(e.value))],
    child: Chip(avatar: Icon(icon, size: 16), label: Text(label), visualDensity: VisualDensity.compact),
  );
}

/// The nightly seals of the shown period, recomputed by the server on demand.
class _IntegrityPanel extends StatelessWidget {
  const _IntegrityPanel({required this.c});
  final PosAuditLogController c;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final v = c.integrity.value;
    final bad = v?.results.where((d) => !d.ok).toList() ?? const <SealDay>[];
    return Container(
      key: const Key('auditIntegrity'),
      margin: const EdgeInsets.only(top: Space.s3),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(color: p.surface, borderRadius: Radii.rMd, border: Border.all(color: p.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                v == null ? Icons.verified_outlined : (v.ok ? Icons.verified_rounded : Icons.gpp_bad_outlined),
                color: v == null ? p.textSecondary : (v.ok ? p.success : p.danger),
              ),
              const SizedBox(width: Space.s2),
              Expanded(child: Text('Integrity', style: t.title.copyWith(color: p.textPrimary))),
              TextButton(
                key: const Key('auditCheck'),
                onPressed: c.checking.value ? null : c.checkIntegrity,
                child: Text(c.checking.value ? 'Checking…' : (v == null ? 'Check this period' : 'Check again')),
              ),
            ],
          ),
          const SizedBox(height: Space.s1),
          if (c.integrityError.value != null)
            Text(c.integrityError.value!, key: const Key('auditIntegrityError'), style: t.bodySmall.copyWith(color: p.dangerFg))
          else if (v == null)
            Text('Each night the day\'s records are sealed. Check that nothing was changed since.', style: t.bodySmall.copyWith(color: p.textSecondary))
          else if (v.days == 0)
            Text('No sealed days in this period yet (a day is sealed the night after).', key: const Key('auditNoSeals'), style: t.bodySmall.copyWith(color: p.textSecondary))
          else if (v.ok)
            Text('All ${v.days} sealed day${v.days == 1 ? '' : 's'} still match. Nothing was changed.', key: const Key('auditIntegrityOk'), style: t.bodySmall.copyWith(color: p.textSecondary))
          else ...[
            Text(
              '${bad.length} of ${v.days} sealed day${v.days == 1 ? '' : 's'} no longer match.',
              key: const Key('auditIntegrityBad'),
              style: t.bodySmall.copyWith(color: p.dangerFg, fontWeight: FontWeight.w600),
            ),
            for (final d in bad)
              Padding(
                key: Key('sealDay_${d.day}'),
                padding: const EdgeInsets.only(top: Space.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(storeDayLabel(d.day), style: t.body.copyWith(color: p.textPrimary, fontWeight: FontWeight.w600)),
                    if (d.status == 'broken_chain')
                      Text('The seal itself was altered or removed (broken chain).', style: t.bodySmall.copyWith(color: p.dangerFg))
                    else
                      for (final part in d.changedParts)
                        Text('${part.label}: ${part.sealedCount} sealed, ${part.nowCount} now', style: t.bodySmall.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.who});
  final PosAuditLogModel log;
  final String who;

  @override
  Widget build(BuildContext context) => ReportRow(
    key: Key('audit_${log.id}'),
    title: log.actionLabel,
    subtitle: [who, if (auditTypes[log.targetType] != null) auditTypes[log.targetType]!].join(' · '),
    value: DateFormat('d MMM, HH:mm').format(log.createdAt.toLocal()),
  );
}
