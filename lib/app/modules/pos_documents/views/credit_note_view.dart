import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// One CREDIT NOTE: its number, the invoice it reverses, each line with its tax reversed (and whether it went back on the shelf), the
/// total credited and which tenders it was refunded to. Print / share as PDF or share the public page.
class CreditNoteView extends StatelessWidget {
  const CreditNoteView({super.key, required this.controller, required this.number});
  final PosDocumentsController controller;
  final String number;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Credit note'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Obx(() {
              final n = controller.note(number);
              if (n == null) return Center(child: Text('Credit note not found', key: const Key('noteMissing'), style: t.body.copyWith(color: p.textSecondary)));
              String m(int v) => Money.format(v / (n.exponent <= 0 ? 1 : List.filled(n.exponent, 10).fold<num>(1, (a, b) => a * b)), currency: n.currency, exponent: n.exponent);
              return ListView(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                children: [
                  AppCard(
                    radius: Radii.rMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (n.sellerName != null) Text(n.sellerName!, style: t.title.copyWith(color: p.textPrimary)),
                        if (n.sellerNtn != null) Text('NTN ${n.sellerNtn}', style: t.caption.copyWith(color: p.textSecondary)),
                        const SizedBox(height: Space.s2),
                        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: Space.s3, runSpacing: Space.s1, children: [
                          StatusBadge(n.number, key: const Key('noteNumber'), tone: StatusTone.danger, icon: Icons.assignment_return_outlined),
                          if (n.createdAt != null) Text(DateFormat('d MMM yyyy, HH:mm').format(n.createdAt!.toLocal()), style: t.caption.copyWith(color: p.textMuted)),
                        ]),
                        const SizedBox(height: Space.s2),
                        Text('Against invoice ${n.invoiceNumber ?? '—'}', key: const Key('noteInvoice'), style: t.body.copyWith(color: p.textSecondary)),
                        if ((n.reason ?? '').isNotEmpty) Text('Reason: ${n.reason}', style: t.caption.copyWith(color: p.textMuted)),
                        if (n.approvedBy != null) Text('Approved by a manager', key: const Key('noteApproved'), style: t.caption.copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  AppCard(
                    radius: Radii.rMd,
                    child: Column(
                      children: [
                        for (final l in n.lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.s2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${l.name}  ×${l.qty}', style: t.subtitle.copyWith(color: p.textPrimary)),
                                    Text(l.restock ? 'Back on the shelf' : 'Not restocked${(l.restockReason ?? '').isNotEmpty ? ' — ${l.restockReason}' : ''}', style: t.caption.copyWith(color: l.restock ? p.textMuted : p.warningFg)),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(m(l.netMinor), style: t.amountMd.copyWith(color: p.textPrimary)), Text('+ ${m(l.taxMinor)} tax', style: t.caption.copyWith(color: p.textMuted))]),
                              ],
                            ),
                          ),
                        const Divider(),
                        ReceiptRow('Value excluding tax', m(n.netMinor)),
                        ReceiptRow('Tax reversed', m(n.taxMinor)),
                        const SizedBox(height: Space.s1),
                        Row(children: [Expanded(child: Text('Credited', style: t.subtitle.copyWith(color: p.textPrimary))), AmountText(m(n.totalMinor), key: const Key('noteTotal'), style: t.amountLg)]),
                        const Divider(),
                        for (final tn in n.tenders) ReceiptRow('Refunded to ${tn.method == 'raast_qr' ? 'Raast' : tn.method}', m(tn.amountMinor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  if (controller.printNotice.value != null) Padding(padding: const EdgeInsets.only(bottom: Space.s2), child: Text(controller.printNotice.value!, key: const Key('printNotice'), style: t.body.copyWith(color: controller.printOk.value ? p.successFg : p.danger))),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Row(
                      children: [
                        Expanded(child: AppButton(key: const Key('notePrint'), label: 'Print credit note', icon: Icons.print_outlined, variant: AppButtonVariant.secondary, onPressed: controller.busy.value ? null : () => controller.printCreditNote(n))),
                        const SizedBox(width: Space.s3),
                        Expanded(child: AppButton(key: const Key('noteReturnSlip'), label: 'Return receipt', icon: Icons.receipt_long_outlined, variant: AppButtonVariant.secondary, onPressed: controller.busy.value ? null : () => controller.printReturnReceipt(n))),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: AppButton(key: const Key('notePdf'), label: 'Share PDF', icon: Icons.ios_share_rounded, loading: controller.busy.value, onPressed: controller.busy.value ? null : () => controller.shareCreditNotePdf(n))),
                      const SizedBox(width: Space.s3),
                      Expanded(child: AppButton(key: const Key('noteLink'), label: 'Share link', icon: Icons.link_rounded, variant: AppButtonVariant.secondary, onPressed: controller.busy.value ? null : () => controller.shareLink(creditNoteNumber: n.number))),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
