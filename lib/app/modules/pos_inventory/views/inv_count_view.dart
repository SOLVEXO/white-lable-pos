import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_count_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/offline_gate.dart';

typedef InvCodeScanner = Future<String?> Function();

Future<String?> _cameraScan() async => await Get.to<String>(() => const PosScanCameraView());

/// Stock count by scan. Count entry needs the server, so offline it only says "Needs internet" (nothing is queued).
class InvCountView extends StatefulWidget {
  InvCountView({super.key, InvCountController? controller, this.scanner = _cameraScan, this.offline})
    : c = controller ?? (Get.isRegistered<InvCountController>() ? Get.find<InvCountController>() : Get.put(InvCountController()));
  final InvCountController c;
  final InvCodeScanner scanner;

  /// Test hook: forces the offline state. Normally read from [OfflineGate].
  final bool? offline;

  @override
  State<InvCountView> createState() => _InvCountViewState();
}

class _InvCountViewState extends State<InvCountView> {
  final _code = TextEditingController();
  InvCountController get c => widget.c;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await widget.scanner();
    if (code == null || code.isEmpty) return;
    _code.text = code;
    await c.find(code);
  }

  Future<void> _find() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    await c.find(code);
  }

  Future<void> _save() async {
    if (await c.saveCurrent()) _code.clear();
  }

  Future<void> _review() async {
    final go = await AppBottomSheet.showGet<bool>(InvVarianceReview(count: c.count.value!), title: 'Review before finishing', scrollable: false);
    if (go == true) await c.finish();
  }

  Future<void> _cancelCount() async {
    if (!mounted) return;
    final yes = await AppDialog.confirm(
      context,
      title: 'Cancel this count?',
      message: 'The counted quantities are thrown away and stock is not changed.',
      confirmLabel: 'Cancel count',
      cancelLabel: 'Keep counting',
      destructive: true,
    );
    if (yes == true) await c.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Stock count',
      body: Obx(() {
        final offline = widget.offline ?? OfflineGate.isOffline;
        if (offline)
          return const EmptyState(key: Key('invCountOffline'), icon: Icons.wifi_off_rounded, title: 'Needs internet', message: 'Counting checks every scan with the server. Reconnect to count.');
        if (c.loading.value && c.count.value == null && c.result.value == null) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
        if (c.error.value != null && c.count.value == null && c.history.isEmpty && c.result.value == null) return InvErrorState(message: c.error.value!, onRetry: c.load);
        final count = c.count.value;
        return count == null ? _noCount(context) : _counting(context, count);
      }),
    );
  }

  Widget _noCount(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final r = c.result.value;
    return ListView(
      key: const Key('invNoCount'),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s8),
      children: [
        if (r != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s4),
            child: AppCard(
              key: const Key('invCountResult'),
              color: p.successSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: p.successFg),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: Text('Count finished', style: t.subtitle.copyWith(color: p.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    r.applied == 0 ? 'No differences: stock was already right.' : '${r.applied} item${r.applied == 1 ? '' : 's'} adjusted to the counted quantity.',
                    style: t.body.copyWith(color: p.textSecondary),
                  ),
                  for (final s in r.skipped)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: Text('Not applied: $s', style: t.bodySmall.copyWith(color: p.warningFg)),
                    ),
                ],
              ),
            ),
          ),
        Icon(Icons.fact_check_outlined, size: 40, color: p.accentFg),
        const SizedBox(height: Space.s3),
        Text('No stock count is open', style: t.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s1),
        Text(c.canManage ? 'Start a count, then scan each item and enter how many you see.' : 'Ask a manager to start a stock count.', style: t.body.copyWith(color: p.textSecondary)),
        if (c.error.value != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s3),
            child: Text(
              c.error.value!,
              key: const Key('invCountError'),
              style: t.body.copyWith(color: p.danger),
            ),
          ),
        if (c.canManage)
          Padding(
            padding: const EdgeInsets.only(top: Space.s4),
            child: AppButton(key: const Key('invStartCount'), label: 'Start a count', icon: Icons.play_arrow_rounded, loading: c.busy.value, onPressed: c.busy.value ? null : c.start),
          ),
        if (c.history.isNotEmpty) ...[
          const InvSectionTitle('Earlier counts'),
          for (final h in c.history)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                radius: Radii.rMd,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${invDate(h.startedAt)}  ·  ${h.countedCount} of ${h.items.length} counted', style: t.body.copyWith(color: p.textPrimary)),
                    ),
                    StatusBadge(h.status == 'completed' ? 'Finished' : (h.status == 'cancelled' ? 'Cancelled' : 'Open'), tone: h.status == 'completed' ? StatusTone.success : StatusTone.neutral),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _counting(BuildContext context, InvCount count) {
    final p = context.palette;
    final t = context.type;
    final total = count.items.length;
    final done = count.countedCount;
    return CustomScrollView(
      key: const Key('invCounting'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                '$done of $total counted',
                key: const Key('invCountProgress'),
                style: t.title.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: Space.s2),
              ClipRRect(
                borderRadius: Radii.rFull,
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8, backgroundColor: p.fill, color: p.accentFg),
              ),
              const SizedBox(height: Space.s4),
              AppButton(key: const Key('invScanButton'), label: 'Scan', icon: Icons.qr_code_scanner_rounded, onPressed: c.busy.value ? null : _scan),
              const SizedBox(height: Space.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(key: const Key('invCodeField'), label: 'Barcode or SKU', controller: _code, mono: true, textInputAction: TextInputAction.search, onSubmitted: (_) => _find()),
                  ),
                  const SizedBox(width: Space.s2),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AppButton(key: const Key('invFindButton'), label: 'Find', variant: AppButtonVariant.secondary, expand: false, onPressed: c.busy.value ? null : _find),
                  ),
                ],
              ),
              if (c.notOnCount.value)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'That item is not on this count.',
                    key: const Key('invNotOnCount'),
                    style: t.body.copyWith(color: p.warningFg),
                  ),
                ),
              if (c.error.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    c.error.value!,
                    key: const Key('invCountError'),
                    style: t.body.copyWith(color: p.danger),
                  ),
                ),
              if (c.lastSaved.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Saved. ${c.lastSaved.value}',
                    key: const Key('invCountSaved'),
                    style: t.body.copyWith(color: p.successFg),
                  ),
                ),
              if (c.current.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: _entry(context, c.current.value!),
                ),
              if (c.canManage)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s4),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(key: const Key('invFinishCount'), label: 'Finish count', loading: c.busy.value, onPressed: c.busy.value ? null : _review),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: AppButton(key: const Key('invCancelCount'), label: 'Cancel count', variant: AppButtonVariant.secondary, onPressed: c.busy.value ? null : _cancelCount),
                      ),
                    ],
                  ),
                ),
              const InvSectionTitle('Items'),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s8),
          sliver: SliverList.builder(
            itemCount: count.items.length,
            itemBuilder: (context, i) => _CountLine(item: count.items[i], onTap: () => c.select(count.items[i])),
          ),
        ),
      ],
    );
  }

  Widget _entry(BuildContext context, InvCountItem it) {
    final p = context.palette;
    final t = context.type;
    return AppCard(
      key: const Key('invCountEntry'),
      color: p.accentSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            it.productName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.subtitle.copyWith(color: p.textPrimary),
          ),
          Text([if (it.sku.isNotEmpty) it.sku, if ((it.barcode ?? '').isNotEmpty) it.barcode!].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
          if (it.countedQty != null) Text('Counted before: ${it.countedQty}', style: t.caption.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s3),
          Row(
            children: [
              Obx(() => QuantityStepper(key: const Key('invCountStepper'), value: c.qty.value, min: 0, max: 1000000, onChanged: c.setQty)),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Obx(() => AppButton(key: const Key('invCountSave'), label: 'Save count', loading: c.busy.value, onPressed: c.busy.value ? null : _save)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountLine extends StatelessWidget {
  const _CountLine({required this.item, required this.onTap});
  final InvCountItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('invCountLine_${item.id}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  if (item.sku.isNotEmpty) Text(item.sku, style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            item.countedQty == null ? const StatusBadge('Not counted', tone: StatusTone.neutral) : StatusBadge('Counted ${item.countedQty}', tone: StatusTone.success),
          ],
        ),
      ),
    );
  }
}

/// Variance review before Finish: the lines whose counted number differs from the system number. Lines nobody counted are left as they are.
class InvVarianceReview extends StatelessWidget {
  const InvVarianceReview({super.key, required this.count});
  final InvCount count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final v = count.variances;
    final uncounted = count.items.length - count.countedCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.isEmpty ? 'No differences found.' : '${v.length} item${v.length == 1 ? '' : 's'} will change:',
          key: const Key('invVarianceSummary'),
          style: t.subtitle.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: Space.s2),
        Flexible(
          child: ListView(
            key: const Key('invVarianceList'),
            shrinkWrap: true,
            children: [
              for (final i in v)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: AppCard(
                    key: Key('invVariance_${i.id}'),
                    radius: Radii.rMd,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.productName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.subtitle.copyWith(color: p.textPrimary),
                              ),
                              Text('System ${i.systemQty}  →  Counted ${i.countedQty}', style: t.caption.copyWith(color: p.textMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.s3),
                        Text(invSigned(i.variance!), style: t.amountMd.copyWith(color: i.variance! < 0 ? p.dangerFg : p.successFg)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        Text(
          'Items you did not count ($uncounted) are left as they are.',
          key: const Key('invUncountedWarning'),
          style: t.bodySmall.copyWith(color: p.warningFg),
        ),
        const SizedBox(height: Space.s4),
        Row(
          children: [
            Expanded(
              child: AppButton(key: const Key('invVarianceBack'), label: 'Keep counting', variant: AppButtonVariant.secondary, onPressed: () => Get.back<bool>(result: false)),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: AppButton(key: const Key('invVarianceConfirm'), label: 'Finish count', onPressed: () => Get.back<bool>(result: true)),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
