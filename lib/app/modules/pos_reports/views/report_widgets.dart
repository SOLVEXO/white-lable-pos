import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Reports, the pulse and the time zone are live from the server: offline they say so (nothing is cached).
class ReportsNeedsInternet extends StatelessWidget {
  const ReportsNeedsInternet({super.key, this.subject = 'This report'});
  final String subject;
  @override
  Widget build(BuildContext context) => EmptyState(
    key: const Key('reportsNeedsInternet'),
    icon: Icons.wifi_off_rounded,
    title: 'Needs internet',
    message: '$subject needs an internet connection. Connect the till and it will load by itself.',
    tone: context.palette.warningFg,
  );
}

/// An axis label in major units, compact (`12k`, `1.5M`): the axis is a guide, the exact amounts are in the bubble and the tables.
String compactMajor(double minor, int exponent) {
  var v = minor;
  for (var i = 0; i < exponent; i++) {
    v /= 10;
  }
  final a = v.abs();
  String trim(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
  if (a >= 1e6) return '${trim(v / 1e6)}M';
  if (a >= 1e3) return '${trim(v / 1e3)}k';
  return trim(v);
}

/// `Mon 9 Nov` from a store-day key.
String storeDayLabel(String key, {bool weekday = true}) {
  final d = parseDayKey(key);
  if (d == null) return key;
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${weekday ? '${wd[d.weekday - 1]} ' : ''}${d.day} ${mo[d.month - 1]}';
}

String periodText(ReportHead h) => h.from == h.to ? storeDayLabel(h.from) : '${storeDayLabel(h.from)} - ${storeDayLabel(h.to)}';

/// The change against a comparison, with an arrow (the arrow and the sign are the cue, the colour only repeats it). [goodWhenUp] false for
/// returns and expenses, where a rise is bad.
class ChangeChip extends StatelessWidget {
  const ChangeChip(this.percent, {super.key, this.goodWhenUp = true});
  final double? percent;
  final bool goodWhenUp;
  @override
  Widget build(BuildContext context) {
    final v = percent;
    if (v == null) return const StatusBadge('No comparison', tone: StatusTone.neutral);
    if (v == 0) return const StatusBadge('No change', icon: Icons.trending_flat_rounded, tone: StatusTone.neutral);
    final up = v > 0;
    final good = up == goodWhenUp;
    return StatusBadge(
      '${up ? '+' : '−'}${v.abs().toStringAsFixed(v.abs() >= 100 ? 0 : 1)}%',
      icon: up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      tone: good ? StatusTone.success : StatusTone.danger,
    );
  }
}

/// A label and a figure (optionally a change chip under it).
class ReportStat extends StatelessWidget {
  const ReportStat({super.key, required this.label, required this.value, this.change, this.goodWhenUp = true, this.valueKey, this.note, this.compared = false});
  final String label, value;
  final double? change;
  final bool goodWhenUp;
  final Key? valueKey;
  final String? note;

  /// a comparison was asked for: a missing change reads "No comparison"
  final bool compared;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final showChange = change != null || compared;
    return AppCard(
      radius: Radii.rMd,
      padding: const EdgeInsets.all(Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              style: t.amountMd.copyWith(color: p.textPrimary),
            ),
          ),
          if (showChange || note != null) const SizedBox(height: Space.s1),
          if (showChange)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ChangeChip(change, goodWhenUp: goodWhenUp),
            ),
          if (note != null) Text(note!, style: t.caption.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}

/// Stats in a responsive grid: 2 per row on a phone, 3–4 on a tablet.
class ReportStatGrid extends StatelessWidget {
  const ReportStatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
      final w = (c.maxWidth - Space.s2 * (cols - 1)) / cols;
      return Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}

/// A row of a report table: a title (+ subtitle), figures on the right; tappable when it drills down.
class ReportRow extends StatelessWidget {
  const ReportRow({super.key, required this.title, this.subtitle, required this.value, this.detail, this.onTap});
  final String title;
  final String? subtitle;
  final String value;
  final String? detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s3),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(title, style: t.subtitle.copyWith(color: p.textPrimary)),
                      ),
                      const SizedBox(width: Space.s2),
                      Text(value, style: t.subtitle.copyWith(color: p.textPrimary)),
                    ],
                  ),
                  if (subtitle != null) Text(subtitle!, style: t.caption.copyWith(color: p.textSecondary)),
                  if (detail != null) Text(detail!, style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            if (onTap != null) ...[const SizedBox(width: Space.s1), Icon(Icons.chevron_right_rounded, color: p.textMuted)],
          ],
        ),
      ),
    );
  }
}

/// A plain info row (the server's own sentence, e.g. the supplier-payments note).
class ReportInfo extends StatelessWidget {
  const ReportInfo(this.text, {super.key, this.icon = Icons.info_outline_rounded, this.warn = false});
  final String text;
  final IconData icon;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(color: warn ? p.warningSoft : p.infoSoft, borderRadius: Radii.rMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: warn ? p.warningFg : p.infoFg),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(text, style: context.type.bodySmall.copyWith(color: warn ? p.warningFg : p.infoFg)),
          ),
        ],
      ),
    );
  }
}

/// The date strip (store days), the "compare" switch where the report offers it, and the register / cashier filters for managers.
class ReportControls extends StatelessWidget {
  const ReportControls({super.key, required this.c});
  final ReportController c;

  Future<void> _pick(BuildContext context) async {
    final today = parseDayKey(c.today.value) ?? DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      initialDateRange: c.customFrom.value == null ? null : DateTimeRange(start: c.customFrom.value!, end: c.customTo.value ?? c.customFrom.value!),
    );
    if (r != null) c.setCustom(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      final (a, b) = c.days;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            key: const Key('reportDateStrip'),
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                for (final r in ReportRange.values)
                  ChoiceChip(
                    key: Key('range_${r.name}'),
                    visualDensity: VisualDensity.compact,
                    label: Text(r == ReportRange.custom && c.range.value == r ? '${storeDayLabel(dayKey(a), weekday: false)} - ${storeDayLabel(dayKey(b), weekday: false)}' : r.label),
                    avatar: r == ReportRange.custom ? const Icon(Icons.date_range_rounded, size: 16) : null,
                    selected: c.range.value == r,
                    onSelected: (_) => r == ReportRange.custom ? _pick(context) : c.setRange(r),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                Text(
                  a == b ? storeDayLabel(dayKey(a)) : '${storeDayLabel(dayKey(a))} - ${storeDayLabel(dayKey(b))}',
                  key: const Key('reportPeriodText'),
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
                if (c.report.value?.head.timeZone != null) Text('· ${c.report.value!.head.timeZone}', style: t.caption.copyWith(color: p.textMuted)),
                if (c.canManage.value && c.registers.isNotEmpty)
                  _FilterButton(
                    key: const Key('filterRegister'),
                    icon: Icons.point_of_sale_rounded,
                    label: c.registers.firstWhereOrNull((r) => r.id == c.registerId.value)?.name ?? 'All registers',
                    items: {null: 'All registers', for (final r in c.registers) r.id: r.name},
                    onSelected: c.setRegister,
                  ),
                if (c.canManage.value && c.people.isNotEmpty && c.kind != ReportKind.cashiers)
                  _FilterButton(
                    key: const Key('filterCashier'),
                    icon: Icons.person_outline_rounded,
                    label: c.people.firstWhereOrNull((e) => e.id == c.employeeId.value)?.name ?? 'All cashiers',
                    items: {null: 'All cashiers', for (final e in c.people) e.id: e.name},
                    onSelected: c.setEmployee,
                  ),
              ],
            ),
          ),
          if (c.supportsCompare)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s2),
              child: SwitchListTile.adaptive(
                key: const Key('reportCompare'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.s2),
                title: Text('Compare with previous period', style: t.body.copyWith(color: p.textPrimary)),
                value: c.compare.value,
                onChanged: c.setCompare,
              ),
            ),
        ],
      );
    });
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({super.key, required this.icon, required this.label, required this.items, required this.onSelected});
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

/// The export menu: CSV and PDF through the share sheet.
class ReportExportButton extends StatelessWidget {
  const ReportExportButton({super.key, required this.c});
  final ReportController c;
  @override
  Widget build(BuildContext context) => Obx(
    () => c.report.value == null
        ? const SizedBox.shrink()
        : PopupMenuButton<String>(
            key: const Key('reportExport'),
            tooltip: 'Export',
            icon: c.busy.value ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded),
            onSelected: (v) => v == 'csv' ? c.shareCsv() : c.sharePdf(),
            itemBuilder: (_) => const [
              PopupMenuItem(key: Key('exportCsv'), value: 'csv', child: Text('Share CSV (spreadsheet)')),
              PopupMenuItem(key: Key('exportPdf'), value: 'pdf', child: Text('Share PDF (A4)')),
            ],
          ),
  );
}
