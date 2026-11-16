import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_team/views/correction_sheet.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class PosNeedsAttentionView extends StatelessWidget {
  PosNeedsAttentionView({super.key, PosNeedsAttentionController? controller}) : c = controller ?? Get.put(PosNeedsAttentionController());

  final PosNeedsAttentionController c;

  static final _fmt = DateFormat('d MMM, HH:mm');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'Needs attention',
      body: Obx(() {
        final unsynced = c.items.where((r) => r.isUnresolved || r.isDiscarding).toList();
        final flagged = c.flaggedSales;
        final digital = c.digital.toList();
        final cash = c.cashItems.where((r) => r.isPending || r.isFailed).toList();
        final team = c.teamItems.where((r) => r.isPending || r.isFailed).toList();
        final anomalies = c.anomalies.toList();
        return RefreshIndicator(
          onRefresh: () async {
            await c.syncNow();
            await c.loadFlagged();
            await c.loadDigital();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              _StatusHeader(c: c),
              const SizedBox(height: Space.s4),
              if (unsynced.isEmpty && flagged.isEmpty && digital.isEmpty && cash.isEmpty && team.isEmpty && anomalies.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s12),
                  child: Column(
                    children: [
                      Icon(Icons.cloud_done_outlined, size: IconSizes.xl, color: p.successFg),
                      const SizedBox(height: Space.s3),
                      Text(
                        'Everything is synced. Nothing needs attention.',
                        textAlign: TextAlign.center,
                        style: context.type.body.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              if (digital.isNotEmpty) ...[
                const SectionHeader('Digital payments (Raast)'),
                for (final d in digital) _DigitalTile(item: d, c: c),
                const SizedBox(height: Space.s4),
              ],
              if (unsynced.isNotEmpty) ...[
                const SectionHeader('Not yet on the server'),
                for (final r in unsynced) _UnsyncedTile(record: r, c: c),
              ],
              if (cash.isNotEmpty) ...[
                const SizedBox(height: Space.s4),
                const SectionHeader('Cash & expenses not yet on the server'),
                for (final r in cash) _CashTile(record: r, c: c),
              ],
              if (anomalies.isNotEmpty) ...[
                const SizedBox(height: Space.s4),
                const SectionHeader('Attendance problems'),
                for (final a in anomalies) _AnomalyTile(anomaly: a, c: c),
              ],
              if (team.isNotEmpty) ...[
                const SizedBox(height: Space.s4),
                const SectionHeader('Clock events not yet on the server'),
                for (final r in team) _ClockQueueTile(record: r, c: c),
              ],
              if (flagged.isNotEmpty) ...[
                const SizedBox(height: Space.s4),
                const SectionHeader('Recorded, but flagged for review'),
                for (final s in flagged) _FlaggedTile(sale: s, c: c),
              ],
            ],
          ),
        );
      }),
    );
  }
}

/// The card every attention item sits in: a surface with a border tinted by how urgent it is.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({super.key, required this.tone, required this.children});
  final Color tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: tone.withValues(alpha: 0.45)),
        boxShadow: context.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Title (with the amount inside it) and the time on the right; the time drops below at a large text scale.
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, this.time});
  final String title;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final titleText = Text(title, style: t.subtitle.copyWith(color: p.textPrimary));
    if (time == null) return titleText;
    final timeText = Text(PosNeedsAttentionView._fmt.format(time!.toLocal()), style: t.caption.copyWith(color: p.textMuted));
    if (MediaQuery.textScalerOf(context).scale(16) > 19) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [titleText, timeText]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleText),
        const SizedBox(width: Space.s2),
        timeText,
      ],
    );
  }
}

Widget _actions(List<Widget> buttons) => Padding(
  padding: const EdgeInsets.only(top: Space.s3),
  child: Wrap(spacing: Space.s2, runSpacing: Space.s2, children: buttons),
);

Widget _status(BuildContext context, String text, Color color) =>
    Text(text, style: context.type.bodySmall.copyWith(color: color, fontWeight: FontWeight.w600));

Widget _detail(BuildContext context, String text, {Color? color}) =>
    Text(text, style: context.type.bodySmall.copyWith(color: color ?? context.palette.textSecondary));

class _StatusHeader extends StatelessWidget {
  final PosNeedsAttentionController c;
  const _StatusHeader({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      final last = c.lastSync.value;
      return AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.items.where((r) => r.isPending).length} waiting · ${c.items.where((r) => r.isFailed).length} rejected',
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    last == null ? 'No successful sync yet' : 'Last successful sync ${PosNeedsAttentionView._fmt.format(last.toLocal())}',
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.s2),
            c.isSyncing.value
                ? const SizedBox(
                    width: Space.minTouch,
                    height: Space.minTouch,
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : AppButton(label: 'Sync now', icon: Icons.sync_rounded, variant: AppButtonVariant.ghost, expand: false, onPressed: c.syncNow),
          ],
        ),
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
    final p = context.palette;
    final r = record;
    final color = r.isFailed ? p.dangerFg : (r.isDiscarding ? p.textMuted : p.warningFg);
    final status = r.isFailed ? 'Rejected — needs a manager' : (r.isDiscarding ? 'Discarded — recording in the audit log' : (r.attempts > 0 ? 'Waiting to retry (attempt ${r.attempts})' : 'Waiting to sync'));
    return _AttentionCard(
      tone: color,
      children: [
        _TitleRow(title: '${r.deviceTotal != null ? Money.format(r.deviceTotal!) : 'Sale'} · ${r.summary}', time: r.madeAt),
        if (r.provisionalNumber != null) ...[
          const SizedBox(height: 2),
          _detail(context, 'Receipt ${r.provisionalNumber} (offline — real number after sync)', color: p.textMuted),
        ],
        const SizedBox(height: Space.s1),
        _status(context, status, color),
        if ((r.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: Space.s1),
          _detail(context, r.errorMessage!),
        ],
        if (r.isDiscarding && (r.discardReason ?? '').isNotEmpty) _detail(context, 'Reason: ${r.discardReason}', color: p.textMuted),
        if (!r.isDiscarding)
          _actions([
            AppButton(label: 'Retry', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.retry(r)),
            Obx(
              () => AppButton(
                label: c.isManager.value ? 'Discard…' : 'Discard (manager)',
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: c.isManager.value ? () => c.discard(r) : null,
              ),
            ),
          ]),
      ],
    );
  }
}

/// A cash in / out, drawer expense or receipt photo made offline: waiting to sync, or refused by the server (shift closed meanwhile, over the limit with
/// nobody to approve …) with the reason, and Retry / Dismiss. A refused entry is never retried by itself.
class _CashTile extends StatelessWidget {
  final PendingCashRecord record;
  final PosNeedsAttentionController c;
  const _CashTile({required this.record, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = record;
    final color = r.isFailed ? p.dangerFg : p.warningFg;
    final status = r.isFailed ? 'Refused by the server — needs a decision' : (r.attempts > 0 ? 'Waiting to retry (attempt ${r.attempts})' : 'Waiting to sync');
    final amount = !r.isReceipt && r.currency != null && r.exponent != null ? Money.format(Money.fromMinor(r.amountMinor, r.exponent!), currency: r.currency!, exponent: r.exponent!) : null;
    return _AttentionCard(
      key: Key('cashAttention_${r.id}'),
      tone: color,
      children: [
        _TitleRow(title: amount == null ? r.title : '${r.title} · $amount', time: r.madeAt),
        const SizedBox(height: Space.s1),
        _status(context, status, color),
        if (r.isFailed && (r.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: Space.s1),
          _detail(context, r.errorMessage!),
        ],
        if (r.isFailed)
          _actions([
            AppButton(key: Key('cashRetry_${r.id}'), label: 'Retry', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.retryCash(r)),
            Obx(
              () => AppButton(
                key: Key('cashDismiss_${r.id}'),
                label: c.isManager.value ? 'Dismiss…' : 'Dismiss (manager)',
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: c.isManager.value ? () => c.dismissCash(r) : null,
              ),
            ),
          ]),
      ],
    );
  }
}

/// An attendance problem a manager should look at (a missing clock-out, a double clock-in, an overlap, a device clock that was ahead, a late sync ...):
/// Fix opens the Correct sheet on the record; Acknowledge says "seen, no action needed".
class _AnomalyTile extends StatelessWidget {
  final AttendanceAnomaly anomaly;
  final PosNeedsAttentionController c;
  const _AnomalyTile({required this.anomaly, required this.c});

  Future<void> _fix() async {
    final rec = await c.findRecord(anomaly);
    if (rec == null) {
      CustomAppSnackbar.warning('That record could not be found. Open the attendance list to fix it.');
      return;
    }
    final fixed = await CorrectionSheet.open(rec);
    if (fixed != null) await c.loadAnomalies();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = anomaly;
    return _AttentionCard(
      key: Key('anomaly_${a.eventId ?? a.kind}'),
      tone: p.warningFg,
      children: [
        _TitleRow(title: '${a.title}${a.employeeName == null ? '' : ' · ${a.employeeName}'}', time: a.at),
        const SizedBox(height: Space.s1),
        _detail(context, a.detail),
        _actions([
          if (a.fixable) AppButton(key: Key('anomalyFix_${a.eventId ?? a.kind}'), label: 'Fix', variant: AppButtonVariant.secondary, expand: false, onPressed: _fix),
          if (a.ackable)
            AppButton(key: Key('anomalyAck_${a.eventId ?? a.kind}'), label: 'Acknowledge', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.ackAnomaly(a)),
        ]),
      ],
    );
  }
}

/// A clock event made offline: waiting to sync, or refused by the server with the reason, and Retry / Dismiss.
class _ClockQueueTile extends StatelessWidget {
  final PendingClockRecord record;
  final PosNeedsAttentionController c;
  const _ClockQueueTile({required this.record, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = record;
    final color = r.isFailed ? p.dangerFg : p.warningFg;
    final status = r.isFailed ? 'Refused by the server — needs a decision' : (r.attempts > 0 ? 'Waiting to retry (attempt ${r.attempts})' : 'Waiting to sync');
    return _AttentionCard(
      key: Key('clockAttention_${r.id}'),
      tone: color,
      children: [
        _TitleRow(title: '${ClockAction.pastLabel(r.action)} · ${teamTime(r.deviceAt)}', time: r.deviceAt),
        const SizedBox(height: Space.s1),
        _status(context, status, color),
        if (r.isFailed && (r.errorMessage ?? '').isNotEmpty) ...[
          const SizedBox(height: Space.s1),
          _detail(context, r.errorMessage!),
        ],
        if (r.isFailed)
          _actions([
            AppButton(key: Key('clockRetry_${r.id}'), label: 'Retry', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.retryClock(r)),
            Obx(
              () => AppButton(
                key: Key('clockDismiss_${r.id}'),
                label: c.isManager.value ? 'Dismiss…' : 'Dismiss (manager)',
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: c.isManager.value ? () => c.dismissClock(r) : null,
              ),
            ),
          ]),
      ],
    );
  }
}

class _FlaggedTile extends StatelessWidget {
  final PosSaleModel sale;
  final PosNeedsAttentionController c;
  const _FlaggedTile({required this.sale, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _AttentionCard(
      tone: p.warningFg,
      children: [
        _TitleRow(title: '${sale.saleNumber} · ${Money.format(sale.total, currency: sale.currency, exponent: sale.currencyExponent)}', time: sale.createdAt),
        const SizedBox(height: Space.s1),
        for (final f in sale.flags) _detail(context, '• ${f.description}', color: p.textPrimary),
        _actions([
          Obx(
            () => AppButton(
              label: c.isManager.value ? 'Mark reviewed…' : 'Mark reviewed (manager)',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: c.isManager.value ? () => c.markReviewed(sale) : null,
            ),
          ),
        ]),
      ],
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
    final p = context.palette;
    final i = item;
    final when = i.confirmedAt ?? i.createdAt;
    final canAttach = i.reason == PosAttentionReason.paidAfterExpiry || i.reason == PosAttentionReason.confirmedUnattached;
    return _AttentionCard(
      key: Key('digital-${i.intentId}'),
      tone: p.dangerFg,
      children: [
        _TitleRow(title: '${c.amountOf(i)} · ${i.reason.title}', time: when),
        const SizedBox(height: Space.s1),
        _detail(context, _explain(), color: p.textPrimary),
        Obx(() {
          if (!c.isManager.value) {
            return Padding(
              padding: const EdgeInsets.only(top: Space.s3),
              child: _detail(context, 'Ask a manager to resolve this.', color: p.textMuted),
            );
          }
          return _actions([
            if (canAttach)
              AppButton(key: const Key('digitalAttach'), label: 'Attach to sale…', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.attachToSale(i)),
            AppButton(
              key: const Key('digitalRefund'),
              label: i.reason == PosAttentionReason.refundFailed ? 'Retry refund' : 'Refund…',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => c.refund(i),
            ),
            AppButton(key: const Key('digitalResolve'), label: 'Resolve with note…', variant: AppButtonVariant.secondary, expand: false, onPressed: () => c.resolveWithNote(i)),
          ]);
        }),
      ],
    );
  }
}
