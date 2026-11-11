import 'package:solvexo_pos/app/modules/pos_cash/views/expense_detail_view.dart' show ReceiptViewer;
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/daybook_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

IconData _lineIcon(String type) => switch (type) {
  'opening' => Icons.lock_open_rounded,
  'cash_sale' => Icons.point_of_sale_rounded,
  'cash_refund' => Icons.assignment_return_outlined,
  'cash_in' => Icons.south_west_rounded,
  'cash_out' => Icons.north_east_rounded,
  'expense' => Icons.receipt_long_outlined,
  'supplier_payment' => Icons.local_shipping_outlined,
  _ => Icons.circle_outlined,
};

/// One line of the drawer with its signed amount and the running balance. A sale or a void opens the existing sale detail; a refund's id is not a sale id,
/// so it is not tappable.
class DaybookLineTile extends StatelessWidget {
  const DaybookLineTile({super.key, required this.line, required this.cur, this.keyId});
  final DaybookLine line;
  final InvCur? cur;
  final String? keyId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final amount = line.type == 'opening' ? cashMoney(line.amountMinor, cur) : cashMoney(line.amountMinor.abs(), cur);
    final plus = line.amountMinor > 0 && line.type != 'opening';
    final minus = line.amountMinor < 0;
    final bal = cashMoney(line.runningMinor, cur);
    final tappable = line.opensSale;
    final inner = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s2),
      child: Row(
        children: [
          Icon(_lineIcon(line.type), size: 20, color: p.textMuted),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: p.textPrimary),
                ),
                if (line.at != null || line.employeeName != null)
                  Text(
                    [if (line.at != null) DateFormat('HH:mm').format(line.at!.toLocal()), if (line.employeeName != null) line.employeeName!].join(' · '),
                    style: t.caption.copyWith(color: p.textMuted),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (amount != null)
                Text(
                  '${plus
                      ? '+'
                      : minus
                      ? '−'
                      : ''}$amount',
                  style: t.amountMd.copyWith(color: minus ? p.dangerFg : (plus ? p.successFg : p.textPrimary)),
                ),
              if (bal != null)
                Text(
                  'Balance $bal',
                  key: Key('daybookBalance_${keyId ?? line.label}_${line.runningMinor}'),
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
            ],
          ),
          if (tappable) Icon(Icons.chevron_right_rounded, color: p.textMuted),
          // G5.1: the slip photo of a cash in / out
          if (line.hasReceipt && line.requestId != null)
            IconButton(key: Key('daybookPhoto_${line.requestId}'), tooltip: 'Slip photo', icon: Icon(Icons.photo_outlined, color: p.accentFg), onPressed: () => _openPhoto(context, line.requestId!)),
        ],
      ),
    );
    return tappable
        ? InkWell(
            key: Key('daybookLine_${line.refId}'),
            onTap: () => Get.toNamed(Routes.posSaleDetail, arguments: line.saleTarget),
            child: inner,
          )
        : inner;
  }
}

Future<void> _openPhoto(BuildContext context, String requestId) async {
  if (!cashOnline()) {
    CustomAppSnackbar.warning('Needs internet.');
    return;
  }
  final repo = PosRepository();
  final link = await repo.getCashMovementReceiptLink(await cashStoreId(null), requestId);
  if (link == null || link.url.isEmpty) {
    CustomAppSnackbar.error(cashErrorMessage(repo.lastErrorCode, fallback: 'Could not open the photo. Try again.'));
    return;
  }
  await AppBottomSheet.showGet<void>(ReceiptViewer(key: ValueKey(link.url), link: link), title: 'Slip photo');
}

/// One shift: header (register, employee, status), every line with its running balance, the summary and, when the server says the lines and the shift's own
/// figure disagree, the "Does not reconcile" warning with the difference.
class DaybookShiftSection extends StatelessWidget {
  const DaybookShiftSection({super.key, required this.shift, required this.cur});
  final DaybookShift shift;
  final InvCur? cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget row(String label, int minor, {bool bold = false, bool signed = false}) {
      final m = cashMoney(minor.abs(), cur);
      if (m == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: (bold ? t.subtitle : t.body).copyWith(color: bold ? p.textPrimary : p.textSecondary)),
            ),
            Text(
              '${signed && minor > 0
                  ? '+'
                  : minor < 0
                  ? '−'
                  : ''}$m',
              style: (bold ? t.amountMd : t.body).copyWith(color: p.textPrimary),
            ),
          ],
        ),
      );
    }

    final when =
        '${shift.openedAt == null ? '' : DateFormat('HH:mm').format(shift.openedAt!.toLocal())} - ${shift.closed && shift.closedAt != null ? DateFormat('HH:mm').format(shift.closedAt!.toLocal()) : 'open'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s4),
      child: AppCard(
        key: Key('shift_${shift.sessionId}'),
        radius: Radii.rMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(shift.registerName ?? 'Register', style: t.subtitle.copyWith(color: p.textPrimary)),
                StatusBadge(shift.closed ? 'Closed' : 'Open', tone: shift.closed ? StatusTone.neutral : StatusTone.success),
              ],
            ),
            Text([if (shift.employeeName != null) shift.employeeName!, when].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
            if (!shift.reconciled)
              Container(
                key: Key('daybookUnreconciled_${shift.sessionId}'),
                margin: const EdgeInsets.only(top: Space.s3),
                padding: const EdgeInsets.all(Space.s3),
                decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: p.warningFg),
                    const SizedBox(width: Space.s2),
                    Expanded(
                      child: Text(
                        'Does not reconcile${cashMoney(shift.unreconciledMinor.abs(), cur) == null ? '' : ': the shift\'s own figure differs by ${shift.unreconciledMinor < 0 ? '−' : '+'}${cashMoney(shift.unreconciledMinor.abs(), cur)}'}.',
                        style: t.body.copyWith(color: p.warningFg),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.s2),
            for (final l in shift.lines) DaybookLineTile(line: l, cur: cur, keyId: shift.sessionId),
            Divider(color: p.border),
            row('Cash sales', shift.cashSalesMinor),
            row('Refunds / voids', -shift.cashRefundsMinor),
            row('Cash in', shift.cashInMinor),
            row('Cash out', -shift.cashOutMinor),
            row('Expenses', -shift.expensesMinor),
            row('Supplier payments', -shift.supplierPaymentsMinor),
            row('Expected cash', shift.expectedCashMinor, bold: true),
            if (shift.countedMinor != null) row('Counted at close', shift.countedMinor!),
            if (shift.varianceMinor != null) row('Variance', shift.varianceMinor!, bold: true, signed: true),
          ],
        ),
      ),
    );
  }
}

/// The daybook of one day. A cashier only gets their own shifts. Online only (the server builds the ledger).
class DaybookView extends StatelessWidget {
  DaybookView({super.key, DaybookController? controller}) : c = controller ?? Get.put(DaybookController());
  final DaybookController c;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: c.day.value, firstDate: DateTime(now.year - 2), lastDate: now);
    if (d != null) c.setDay(d);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Daybook',
      maxWidth: 760,
      body: Obx(() {
        final dayText = DateFormat('EEE d MMM yyyy').format(c.day.value);
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s1),
          child: Row(
            children: [
              IconButton(key: const Key('daybookPrev'), tooltip: 'Previous day', icon: const Icon(Icons.chevron_left_rounded), onPressed: c.previousDay),
              Expanded(
                child: TextButton(
                  key: const Key('daybookDay'),
                  onPressed: () => _pick(context),
                  child: Text(c.isToday ? 'Today · $dayText' : dayText, style: t.subtitle.copyWith(color: p.textPrimary)),
                ),
              ),
              IconButton(key: const Key('daybookNext'), tooltip: 'Next day', icon: const Icon(Icons.chevron_right_rounded), onPressed: c.isToday ? null : c.nextDay),
            ],
          ),
        );
        Widget body;
        final d = c.daybook.value;
        if (!cashOnlineRx().value && d == null) {
          body = const CashNeedsInternet(subject: 'The daybook');
        } else if (c.loading.value && d == null) {
          body = const Center(child: CircularProgressIndicator(key: Key('cashLoading')));
        } else if (d == null) {
          body = InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        } else {
          body = RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              key: const Key('daybookList'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
              children: [
                if (d.ownShiftsOnly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Text(
                      'Showing your own shifts only.',
                      key: const Key('daybookOwnOnly'),
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                if (!d.reconciled)
                  Container(
                    key: const Key('daybookUnreconciledTop'),
                    margin: const EdgeInsets.only(bottom: Space.s3),
                    padding: const EdgeInsets.all(Space.s3),
                    decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: p.warningFg),
                        const SizedBox(width: Space.s2),
                        Expanded(
                          child: Text(
                            'Does not reconcile${cashMoney(d.unreconciledMinor.abs(), d.cur) == null ? '' : ' (${d.unreconciledMinor < 0 ? '−' : '+'}${cashMoney(d.unreconciledMinor.abs(), d.cur)})'}. See the shifts below.',
                            style: t.body.copyWith(color: p.warningFg),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (d.shifts.isEmpty)
                  const EmptyState(icon: Icons.menu_book_outlined, title: 'No shifts', message: 'No shift was opened on this day.')
                else ...[
                  for (final s in d.shifts) DaybookShiftSection(shift: s, cur: d.cur),
                  _totals(context, d),
                  const SizedBox(height: Space.s4),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(key: const Key('daybookPrint'), label: 'Print', icon: Icons.print_outlined, variant: AppButtonVariant.secondary, onPressed: c.busy.value ? null : c.printIt),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: AppButton(key: const Key('daybookShare'), label: 'Share PDF', icon: Icons.ios_share_rounded, onPressed: c.busy.value ? null : c.sharePdf),
                      ),
                    ],
                  ),
                  if (c.printNotice.value != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s2),
                      child: Text(
                        c.printNotice.value!,
                        key: const Key('daybookPrintNotice'),
                        style: t.caption.copyWith(color: c.printOk.value ? p.successFg : p.textSecondary),
                      ),
                    ),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            header,
            Expanded(child: body),
          ],
        );
      }),
    );
  }

  Widget _totals(BuildContext context, Daybook d) {
    final p = context.palette;
    final t = context.type;
    final tot = d.totals;
    Widget row(String label, int minor, {bool bold = false, bool signed = false}) {
      final m = cashMoney(minor.abs(), d.cur);
      if (m == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Space.s1),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: (bold ? t.subtitle : t.body).copyWith(color: bold ? p.textPrimary : p.textSecondary)),
            ),
            Text(
              '${signed && minor > 0
                  ? '+'
                  : minor < 0
                  ? '−'
                  : ''}$m',
              style: (bold ? t.amountMd : t.body).copyWith(color: p.textPrimary),
            ),
          ],
        ),
      );
    }

    return AppCard(
      key: const Key('daybookTotals'),
      radius: Radii.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Totals', style: t.subtitle.copyWith(color: p.textPrimary)),
          row('Cash sales', tot.cashSalesMinor),
          row('Refunds / voids', -tot.cashRefundsMinor),
          row('Cash in', tot.cashInMinor),
          row('Cash out', -tot.cashOutMinor),
          row('Expenses', -tot.expensesMinor),
          row('Supplier payments', -tot.supplierPaymentsMinor),
          row('Variance', tot.varianceMinor, bold: true, signed: true),
        ],
      ),
    );
  }
}
