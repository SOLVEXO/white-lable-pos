import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The reason dialog of a rejection. Owns its text controller.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject this expense?'),
    content: TextField(
      key: const Key('rejectReason'),
      controller: _c,
      autofocus: true,
      maxLength: 300,
      decoration: const InputDecoration(labelText: 'Reason (required)'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
      TextButton(
        key: const Key('rejectConfirm'),
        onPressed: () {
          final t = _c.text.trim();
          if (t.isNotEmpty) Navigator.of(context).pop(t);
        },
        child: const Text('Reject'),
      ),
    ],
  );
}

/// The receipt, shown from a link fetched a moment ago. The image is loaded straight from that link into memory (no disk cache, nothing written to the
/// device) and evicted when the viewer closes; the link is never printed. A PDF opens in the in-app PDF viewer instead ([onViewPdf]).
class ReceiptViewer extends StatefulWidget {
  const ReceiptViewer({super.key, required this.link, this.onViewPdf});
  final ReceiptLink link;
  final VoidCallback? onViewPdf;
  @override
  State<ReceiptViewer> createState() => _ReceiptViewerState();
}

class _ReceiptViewerState extends State<ReceiptViewer> {
  late final NetworkImage _image = NetworkImage(widget.link.url);

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    if (widget.link.isPdf) {
      return AppButton(
        key: const Key('viewReceiptPdf'),
        label: 'View PDF receipt',
        variant: AppButtonVariant.secondary,
        icon: Icons.picture_as_pdf_outlined,
        onPressed: widget.onViewPdf,
      );
    }
    return ClipRRect(
      borderRadius: Radii.rMd,
      child: Image(
        key: const Key('receiptImage'),
        image: _image,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Text('The receipt could not be shown. Try again.', style: t.body.copyWith(color: p.dangerFg)),
        ),
      ),
    );
  }
}

/// One expense: status and decision note, the receipt (a fresh link each time it is opened), and for a manager Approve / Reject. Online only.
class ExpenseDetailView extends StatelessWidget {
  ExpenseDetailView({super.key, required String expenseId, ExpenseDetailController? controller}) : c = controller ?? Get.put(ExpenseDetailController(expenseId: expenseId), tag: expenseId);
  final ExpenseDetailController c;

  Future<void> _reject(BuildContext context) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _ReasonDialog());
    if (reason != null) await c.decide(approve: false, note: reason);
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Expense',
      maxWidth: 760,
      body: Obx(() {
        if (!cashOnlineRx().value && c.expense.value == null) return const CashNeedsInternet(subject: 'This expense');
        final e = c.expense.value;
        if (c.loading.value && e == null) return const Center(child: CircularProgressIndicator(key: Key('cashLoading')));
        if (e == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, e));
      }),
    );
  }

  Widget _content(BuildContext context, Expense e) {
    final p = context.palette;
    final t = context.type;
    final money = cashMoney(e.amountMinor, e.cur);
    Widget detail(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label, style: t.caption.copyWith(color: p.textSecondary)),
                ),
                Expanded(
                  child: Text(value, style: t.body.copyWith(color: p.textPrimary)),
                ),
              ],
            ),
          );
    return ListView(
      key: const Key('expenseDetail'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(cashCategoryLabel(e.category), style: t.title.copyWith(color: p.textPrimary)),
            ),
            ExpenseStatusBadge(e.status),
          ],
        ),
        if (money != null) AmountText(money, key: const Key('expenseDetailAmount'), style: t.amountLg, animate: false),
        const SizedBox(height: Space.s3),
        AppCard(
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detail('Number', e.number),
              detail('When', invDateTime(e.occurredAt)),
              detail('Paid by', expenseMethodLabel(e.method)),
              detail('Paid to', e.payee),
              detail('Recorded by', e.employeeName),
              detail('Note', e.note),
              if (e.decided) detail(e.status == ExpenseStatus.rejected ? 'Rejected because' : 'Approval note', e.decisionNote ?? 'No note'),
            ],
          ),
        ),
        Obx(
          () => c.notice.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    c.notice.value!,
                    key: const Key('expenseNotice'),
                    style: t.body.copyWith(color: p.successFg),
                  ),
                ),
        ),
        Obx(() => SupplyErrorText(c.actionError.value, errorKey: const Key('expenseActionError'))),
        const InvSectionTitle('Receipt'),
        if (!e.hasReceipt)
          Text(
            'No receipt photo.',
            key: const Key('noReceipt'),
            style: t.body.copyWith(color: p.textMuted),
          )
        else if (e.receiptIsPdf)
          // the expense itself says the receipt is a PDF: no link is fetched until "View PDF receipt" (G5.8: in-app viewer)
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const Key('viewReceiptPdf'),
                  label: 'View PDF receipt',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.picture_as_pdf_outlined,
                  loading: c.receiptLoading.value,
                  onPressed: c.viewReceiptPdf,
                ),
                SupplyErrorText(c.receiptError.value, errorKey: const Key('receiptError')),
              ],
            ),
          )
        else
          Obx(() {
            final link = c.receipt.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (link != null) ReceiptViewer(key: ValueKey(link.url), link: link, onViewPdf: c.viewReceiptPdf),
                if (link != null) const SizedBox(height: Space.s2),
                AppButton(
                  key: Key(link == null ? 'viewReceipt' : 'hideReceipt'),
                  label: link == null ? 'View receipt' : 'Hide receipt',
                  variant: AppButtonVariant.secondary,
                  icon: link == null ? Icons.receipt_long_outlined : Icons.visibility_off_outlined,
                  loading: c.receiptLoading.value,
                  onPressed: link == null ? c.openReceipt : c.closeReceipt,
                ),
                SupplyErrorText(c.receiptError.value, errorKey: const Key('receiptError')),
              ],
            );
          }),
        Obx(
          () => c.canDecide
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.s5),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(key: const Key('expenseApprove'), label: 'Approve', loading: c.busy.value, onPressed: () => c.decide(approve: true)),
                      ),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: AppButton(key: const Key('expenseReject'), label: 'Reject', variant: AppButtonVariant.danger, onPressed: c.busy.value ? null : () => _reject(context)),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
