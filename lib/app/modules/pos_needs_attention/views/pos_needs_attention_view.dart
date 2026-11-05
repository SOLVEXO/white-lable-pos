import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:solvexo_pos/utils/money.dart';

class PosNeedsAttentionView extends StatelessWidget {
  PosNeedsAttentionView({super.key, PosNeedsAttentionController? controller}) : c = controller ?? Get.put(PosNeedsAttentionController());

  final PosNeedsAttentionController c;

  static final _fmt = DateFormat('d MMM, HH:mm');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBarTwo(title: 'Needs attention', color: AppColors.black2),
      body: Obx(() {
        final unsynced = c.items.where((r) => r.isUnresolved || r.isDiscarding).toList();
        final flagged = c.flaggedSales;
        final digital = c.digital.toList();
        return RefreshIndicator(
          onRefresh: () async {
            await c.syncNow();
            await c.loadFlagged();
            await c.loadDigital();
          },
          child: ListView(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            children: [
              _StatusHeader(c: c),
              const SizedBox(height: 12),
              if (unsynced.isEmpty && flagged.isEmpty && digital.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CustomText(text: 'Everything is synced. Nothing needs attention.', fontSize: AppFontSize.small2, color: AppColors.iosGrey)),
                ),
              if (digital.isNotEmpty) ...[
                const CustomText(text: 'Digital payments (Raast)', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
                const SizedBox(height: 8),
                for (final d in digital) _DigitalTile(item: d, c: c),
                const SizedBox(height: 16),
              ],
              if (unsynced.isNotEmpty) ...[
                const CustomText(text: 'Not yet on the server', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
                const SizedBox(height: 8),
                for (final r in unsynced) _UnsyncedTile(record: r, c: c),
              ],
              if (flagged.isNotEmpty) ...[
                const SizedBox(height: 16),
                const CustomText(text: 'Recorded, but flagged for review', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
                const SizedBox(height: 8),
                for (final s in flagged) _FlaggedTile(sale: s, c: c),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final PosNeedsAttentionController c;
  const _StatusHeader({required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final last = c.lastSync.value;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomText(
                text: '${c.items.where((r) => r.isPending).length} waiting · ${c.items.where((r) => r.isFailed).length} rejected',
                fontSize: AppFontSize.small2,
                fontWeight: FontWeight.bold,
                color: AppColors.black2,
              ),
              const SizedBox(height: 2),
              CustomText(
                text: last == null ? 'No successful sync yet' : 'Last successful sync ${PosNeedsAttentionView._fmt.format(last.toLocal())}',
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
              ),
            ]),
          ),
          c.isSyncing.value
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton.icon(onPressed: c.syncNow, icon: const Icon(Icons.sync_rounded, size: 18), label: const Text('Sync now')),
        ]),
      );
    });
  }
}

class _UnsyncedTile extends StatelessWidget {
  final PendingSaleRecord record;
  final PosNeedsAttentionController c;
  const _UnsyncedTile({required this.record, required this.c});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final color = r.isFailed ? AppColors.red : (r.isDiscarding ? AppColors.iosGrey : AppColors.amberDark);
    final status = r.isFailed ? 'Rejected — needs a manager' : (r.isDiscarding ? 'Discarded — recording in the audit log' : (r.attempts > 0 ? 'Waiting to retry (attempt ${r.attempts})' : 'Waiting to sync'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: CustomText(text: '${r.deviceTotal != null ? Money.format(r.deviceTotal!) : 'Sale'} · ${r.summary}', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2)),
          CustomText(text: PosNeedsAttentionView._fmt.format(r.madeAt.toLocal()), fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ]),
        if (r.provisionalNumber != null) ...[
          const SizedBox(height: 2),
          CustomText(text: 'Receipt ${r.provisionalNumber} (offline — real number after sync)', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ],
        const SizedBox(height: 4),
        CustomText(text: status, fontSize: AppFontSize.tiny, fontWeight: FontWeight.w600, color: color),
        if ((r.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          CustomText(text: r.errorMessage!, fontSize: AppFontSize.tiny, color: AppColors.black2),
        ],
        if (r.isDiscarding && (r.discardReason ?? '').isNotEmpty) CustomText(text: 'Reason: ${r.discardReason}', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        if (!r.isDiscarding) ...[
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton(onPressed: () => c.retry(r), child: const Text('Retry')),
            const SizedBox(width: 8),
            Obx(() => OutlinedButton(
                  onPressed: c.isManager.value ? () => c.discard(r) : null,
                  child: Text(c.isManager.value ? 'Discard…' : 'Discard (manager)'),
                )),
          ]),
        ],
      ]),
    );
  }
}

class _FlaggedTile extends StatelessWidget {
  final PosSaleModel sale;
  final PosNeedsAttentionController c;
  const _FlaggedTile({required this.sale, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.amberDark.withOpacity(0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: CustomText(text: '${sale.saleNumber} · ${Money.format(sale.total, currency: sale.currency, exponent: sale.currencyExponent)}', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2)),
          CustomText(text: PosNeedsAttentionView._fmt.format(sale.createdAt.toLocal()), fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ]),
        const SizedBox(height: 6),
        for (final f in sale.flags) CustomText(text: '• ${f.description}', fontSize: AppFontSize.tiny, color: AppColors.black2),
        const SizedBox(height: 8),
        Obx(() => OutlinedButton(
              onPressed: c.isManager.value ? () => c.markReviewed(sale) : null,
              child: Text(c.isManager.value ? 'Mark reviewed…' : 'Mark reviewed (manager)'),
            )),
      ]),
    );
  }
}


/// One Raast payment that needs a manager: what happened, the amount, and the three things a manager can do about it.
/// Each action asks for confirmation (or a required note), runs under the manager's PIN session and is audit-logged by the server.
class _DigitalTile extends StatelessWidget {
  final PosAttentionItem item;
  final PosNeedsAttentionController c;
  const _DigitalTile({required this.item, required this.c});

  String _explain() => switch (item.reason) {
        PosAttentionReason.paidAfterExpiry => 'The customer paid after the QR had expired. The money is received — match it to the sale or refund it.',
        PosAttentionReason.confirmedUnattached => 'The customer paid, but no sale was completed with this payment.',
        PosAttentionReason.anomaly => 'The amount received did not match the amount asked for. Nothing was counted as paid.',
        PosAttentionReason.refundFailed => 'A refund to the customer did not go through.',
      };

  @override
  Widget build(BuildContext context) {
    final i = item;
    final when = i.confirmedAt ?? i.createdAt;
    final canAttach = i.reason == PosAttentionReason.paidAfterExpiry || i.reason == PosAttentionReason.confirmedUnattached;
    return Container(
      key: Key('digital-${i.intentId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.red.withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: CustomText(text: '${c.amountOf(i)} · ${i.reason.title}', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2)),
          if (when != null) CustomText(text: PosNeedsAttentionView._fmt.format(when.toLocal()), fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
        ]),
        const SizedBox(height: 6),
        CustomText(text: _explain(), fontSize: AppFontSize.tiny, color: AppColors.black2),
        const SizedBox(height: 10),
        Obx(() {
          if (!c.isManager.value) return const CustomText(text: 'Ask a manager to resolve this.', fontSize: AppFontSize.tiny, color: AppColors.iosGrey);
          return Wrap(spacing: 8, runSpacing: 8, children: [
            if (canAttach) OutlinedButton(key: const Key('digitalAttach'), onPressed: () => c.attachToSale(i), child: const Text('Attach to sale…')),
            OutlinedButton(key: const Key('digitalRefund'), onPressed: () => c.refund(i), child: Text(i.reason == PosAttentionReason.refundFailed ? 'Retry refund' : 'Refund…')),
            OutlinedButton(key: const Key('digitalResolve'), onPressed: () => c.resolveWithNote(i), child: const Text('Resolve with note…')),
          ]);
        }),
      ]),
    );
  }
}
