import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// G4.6 batch expiry: lots that are expired, expire within 7 days, or within 30 days (store time zone), with value at cost for roles that see cost,
/// and a write-off (all or part of a lot; expired or damaged) behind the matrix. Online only.
class ExpiryController extends GetxController {
  ExpiryController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<ExpiryBuckets> buckets = Rxn<ExpiryBuckets>();
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString actionError = RxnString();
  final RxnString notice = RxnString();
  Worker? _online;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && buckets.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final r = await _repo.getExpiry(await reportsStoreId(_storeIdOverride));
    if (r == null) {
      error.value = stockOpsErrorMessage(_repo.lastErrorCode, message: 'Could not load the expiring lots. Try again.');
    } else {
      buckets.value = r;
    }
    loading.value = false;
  }

  /// [quantity] null = everything left in the lot.
  Future<bool> writeOff(ExpiringLot lot, {int? quantity, required String reason, String? note}) async {
    actionError.value = null;
    notice.value = null;
    if (quantity != null && (quantity <= 0 || quantity > lot.remaining)) {
      actionError.value = 'Write off between 1 and ${lot.remaining}.';
      return false;
    }
    if (!reportsOnline()) {
      actionError.value = 'Writing off stock needs an internet connection.';
      return false;
    }
    if (busy.value) return false;
    busy.value = true;
    try {
      final r = await _repo.writeOffLot(await reportsStoreId(_storeIdOverride), lot.lotId, quantity: quantity, reason: reason, note: note);
      if (!r.success) {
        actionError.value = stockOpsErrorMessage(r.code, message: r.message);
        return false;
      }
      final written = r.data?['written'] is num ? (r.data!['written'] as num).toInt() : (quantity ?? lot.remaining);
      notice.value = 'Wrote off $written of lot ${lot.lotNumber}. Stock and the ledger are updated.';
      await load();
      return true;
    } finally {
      busy.value = false;
    }
  }
}

class ExpiryView extends StatefulWidget {
  const ExpiryView({super.key, this.controller});
  final ExpiryController? controller;
  @override
  State<ExpiryView> createState() => _ExpiryViewState();
}

class _ExpiryViewState extends State<ExpiryView> {
  late final String _tag = 'expiry_${identityHashCode(this)}';
  late final ExpiryController c = widget.controller ?? Get.put(ExpiryController(), tag: _tag);

  @override
  void dispose() {
    if (widget.controller == null) Get.delete<ExpiryController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Expiring lots',
      body: Obx(() {
        final b = c.buckets.value;
        if (!reportsOnlineRx().value && b == null) return const ReportsNeedsInternet(subject: 'Expiring lots');
        if (b == null && c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('expiryLoading')));
        if (b == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        final p = context.palette;
        String money(int m) => Money.format(Money.fromMinor(m, b.exponent), currency: b.currency, exponent: b.exponent);
        Widget bucket(String key, String title, List<ExpiringLot> lots, StatusTone tone) => Column(
          key: Key('expiryBucket_$key'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InvSectionTitle('$title · ${lots.length}${b.showsValue && lots.isNotEmpty ? ' · ${money(b.value(lots))} at cost' : ''}'),
            if (lots.isEmpty) Text('None.', style: context.type.caption.copyWith(color: p.textMuted)),
            for (final l in lots) _LotRow(c: c, lot: l, tone: tone, money: b.showsValue ? money : null),
          ],
        );
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            key: const Key('expiryList'),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              if (c.notice.value != null) ReportInfo(key: const Key('expiryNotice'), c.notice.value!, icon: Icons.check_circle_outline_rounded),
              if (b.empty)
                const EmptyState(key: Key('expiryEmpty'), icon: Icons.event_available_outlined, title: 'Nothing expiring', message: 'No lot expires in the next 30 days.')
              else ...[
                bucket('expired', 'Expired', b.expired, StatusTone.danger),
                bucket('7', 'Within 7 days', b.within7, StatusTone.warning),
                bucket('30', 'Within 30 days', b.within30, StatusTone.neutral),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _LotRow extends StatelessWidget {
  const _LotRow({required this.c, required this.lot, required this.tone, this.money});
  final ExpiryController c;
  final ExpiringLot lot;
  final StatusTone tone;
  final String Function(int)? money;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('lot_${lot.lotId}'),
        radius: Radii.rMd,
        padding: const EdgeInsets.all(Space.s3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lot.productName, style: t.subtitle.copyWith(color: p.textPrimary)),
                  Text(
                    ['Lot ${lot.lotNumber}', if (lot.sku != null) lot.sku!, '${lot.remaining} left', if (lot.expiryDate != null) DateFormat('d MMM y').format(lot.expiryDate!)].join(' · '),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                  if (money != null && lot.valueMinor != null) Text('${money!(lot.valueMinor!)} at cost', style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(lot.when, tone: tone),
                TextButton(key: Key('writeOff_${lot.lotId}'), onPressed: () => WriteOffSheet.open(c, lot), child: const Text('Write off')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of the lot (all by default), why (expired / damaged), an optional note.
class WriteOffSheet extends StatefulWidget {
  const WriteOffSheet({super.key, required this.c, required this.lot});
  final ExpiryController c;
  final ExpiringLot lot;
  static Future<void> open(ExpiryController c, ExpiringLot lot) {
    c.actionError.value = null;
    return Get.bottomSheet(WriteOffSheet(c: c, lot: lot), isScrollControlled: true, backgroundColor: Colors.transparent);
  }

  @override
  State<WriteOffSheet> createState() => _WriteOffSheetState();
}

class _WriteOffSheetState extends State<WriteOffSheet> {
  late final TextEditingController _qty = TextEditingController(text: '${widget.lot.remaining}');
  final _note = TextEditingController();
  late String _reason = widget.lot.daysLeft <= 0 ? 'expired' : 'damaged';

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppSheetSurface(
      key: const Key('writeOffSheet'),
      title: 'Write off · lot ${widget.lot.lotNumber}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.lot.productName} · ${widget.lot.remaining} left. The stock and its value leave the books; this is recorded.', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s2),
          SegmentedButton<String>(
            key: const Key('writeOffReason'),
            segments: const [ButtonSegment(value: 'expired', label: Text('Expired')), ButtonSegment(value: 'damaged', label: Text('Damaged'))],
            selected: {_reason},
            onSelectionChanged: (v) => setState(() => _reason = v.first),
          ),
          TextField(
            key: const Key('writeOffQty'),
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'How many'),
          ),
          TextField(key: const Key('writeOffNote'), controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Note (optional)')),
          Obx(() => widget.c.actionError.value == null ? const SizedBox.shrink() : Text(widget.c.actionError.value!, key: const Key('writeOffError'), style: context.type.caption.copyWith(color: p.dangerFg))),
          const SizedBox(height: Space.s2),
          Obx(
            () => AppButton(
              key: const Key('writeOffConfirm'),
              label: 'Write off',
              variant: AppButtonVariant.danger,
              loading: widget.c.busy.value,
              onPressed: widget.c.busy.value
                  ? null
                  : () async {
                      final n = int.tryParse(_qty.text) ?? 0;
                      final ok = await widget.c.writeOff(widget.lot, quantity: n == widget.lot.remaining ? null : n, reason: _reason, note: _note.text);
                      if (ok) Get.back();
                    },
            ),
          ),
        ],
      ),
    );
  }
}
