import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The TAX INVOICE of a sale: its number, the seller as registered, every line with its tax, totals, how it was paid, and the credit notes
/// issued against it. Print / share as PDF, or share the public link. (A band is reserved under the totals for the fiscal invoice number.)
class TaxInvoiceView extends StatelessWidget {
  TaxInvoiceView({super.key, PosDocumentsController? controller}) : c = controller ?? Get.put(PosDocumentsController());
  final PosDocumentsController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Tax invoice'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Obx(() {
              if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('invoiceLoading')));
              final s = c.sale.value;
              if (s == null) return Center(child: Text(c.error.value ?? 'Not found', key: const Key('invoiceError')));
              final inv = s.invoice;
              String m(num v) => Money.format(v, currency: s.currency, exponent: s.currencyExponent);
              String mm(int? minor) => Money.format((minor ?? 0) / _p10(s.currencyExponent), currency: s.currency, exponent: s.currencyExponent);
              final t = context.type;
              return ListView(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                children: [
                  AppCard(
                    radius: Radii.rMd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inv?.sellerName != null) Text(inv!.sellerName!, key: const Key('invoiceSeller'), style: t.title.copyWith(color: p.textPrimary)),
                        if (inv?.sellerAddress != null) Text(inv!.sellerAddress!, style: t.caption.copyWith(color: p.textSecondary)),
                        if (inv?.sellerNtn != null) Text('NTN ${inv!.sellerNtn}', key: const Key('invoiceNtn'), style: t.caption.copyWith(color: p.textSecondary)),
                        if (inv?.sellerStrn != null) Text('STRN ${inv!.sellerStrn}', key: const Key('invoiceStrn'), style: t.caption.copyWith(color: p.textSecondary)),
                        const SizedBox(height: Space.s3),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: Space.s3,
                          runSpacing: Space.s1,
                          children: [
                            StatusBadge(inv?.number ?? 'No invoice number', key: const Key('invoiceNumber'), tone: inv == null ? StatusTone.neutral : StatusTone.accent, icon: Icons.receipt_long_rounded),
                            Text(DateFormat('d MMM yyyy, HH:mm').format((inv?.issuedAt ?? s.createdAt).toLocal()), style: t.caption.copyWith(color: p.textMuted)),
                          ],
                        ),
                        if (inv == null) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text('This sale was made before tax invoices were numbered (receipt ${s.saleNumber}).', key: const Key('invoiceLegacy'), style: t.caption.copyWith(color: p.textMuted))),
                        if (inv?.offlineRef != null) Padding(padding: const EdgeInsets.only(top: Space.s1), child: Text('Offline receipt ${inv!.offlineRef}', key: const Key('invoiceOfflineRef'), style: t.caption.copyWith(color: p.textMuted))),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  AppCard(
                    radius: Radii.rMd,
                    child: Column(
                      children: [
                        for (final i in s.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.s2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(i.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                                      Text('${i.qty} × ${m(i.price)}${i.hsCode != null ? ' · HS ${i.hsCode}' : ''}', style: t.caption.copyWith(color: p.textMuted)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(i.netMinor != null ? mm(i.netMinor) : m(i.lineTotal), style: t.amountMd.copyWith(color: p.textPrimary)),
                                    if (i.taxMinor != null) Text('+ ${mm(i.taxMinor)} tax', style: t.caption.copyWith(color: p.textMuted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        const Divider(),
                        ReceiptRow('Subtotal', m(s.subtotal)),
                        if (s.discount > 0) ReceiptRow((s.loyalty?.redeemedPoints ?? 0) > 0 ? 'Points redeemed (${s.loyalty!.redeemedPoints})' : 'Discount', '-${m(s.discount)}', valueColor: p.successFg),
                        ReceiptRow('Sales tax', m(s.tax)),
                        const SizedBox(height: Space.s1),
                        Row(children: [Expanded(child: Text('Total', style: t.subtitle.copyWith(color: p.textPrimary))), AmountText(m(s.total), key: const Key('invoiceTotal'), style: t.amountLg)]),
                        const Divider(),
                        for (final pay in s.paymentLines) ReceiptRow(_label(pay.method), m(pay.amount)),
                      ],
                    ),
                  ),
                  if (c.creditNotes.isNotEmpty) ...[
                    const SizedBox(height: Space.s4),
                    Text('Credit notes', style: t.title.copyWith(color: p.textPrimary)),
                    const SizedBox(height: Space.s2),
                    for (final n in c.creditNotes) _NoteRow(c: c, n: n),
                  ],
                  if (c.error.value != null) Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.error.value!, key: const Key('invoiceShareError'), style: t.body.copyWith(color: p.danger))),
                  const SizedBox(height: Space.s4),
                  if (c.noticeFor('invoice:${c.sale.value?.id}') != null) Padding(padding: const EdgeInsets.only(bottom: Space.s2), child: Text(c.noticeFor('invoice:${c.sale.value?.id}')!, key: const Key('printNotice'), style: t.body.copyWith(color: c.printOk.value ? p.successFg : p.danger))),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: SizedBox(width: double.infinity, child: AppButton(key: const Key('invoicePrint'), label: c.isPrinted('invoice', c.sale.value?.id ?? '') ? 'Reprint' : 'Print original', icon: Icons.print_outlined, variant: AppButtonVariant.secondary, onPressed: c.busy.value ? null : c.printInvoice)),
                  ),
                  AppButton(key: const Key('invoiceViewPdf'), label: 'View PDF', icon: Icons.picture_as_pdf_outlined, variant: AppButtonVariant.secondary, onPressed: c.busy.value ? null : c.viewInvoicePdf),
                  const SizedBox(height: Space.s3),
                  Row(
                    children: [
                      Expanded(child: AppButton(key: const Key('invoicePdf'), label: 'Share PDF', icon: Icons.ios_share_rounded, loading: c.busy.value, onPressed: c.busy.value ? null : c.shareInvoicePdf)),
                      const SizedBox(width: Space.s3),
                      Expanded(child: AppButton(key: const Key('invoiceLink'), label: 'Share link', icon: Icons.link_rounded, variant: AppButtonVariant.secondary, onPressed: c.busy.value || s.invoice == null ? null : c.shareLink)),
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

  static String _label(String m) => switch (m) { 'raast_qr' => 'Raast', 'store_credit' => 'Store credit', _ => '${m[0].toUpperCase()}${m.substring(1)}' };
  static num _p10(int e) => e <= 0 ? 1 : List.filled(e, 10).fold<num>(1, (a, b) => a * b);
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.c, required this.n});
  final PosDocumentsController c;
  final PosCreditNote n;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('note_${n.number}'),
        radius: Radii.rMd,
        child: InkWell(
          onTap: () => Get.to(() => CreditNoteView(controller: c, number: n.number)),
          child: Row(
            children: [
              Icon(n.kind == 'void' ? Icons.block_rounded : Icons.assignment_return_outlined, color: p.textSecondary),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.number, style: context.type.subtitle.copyWith(color: p.textPrimary)),
                    Text('${n.kind == 'void' ? 'Void' : (n.scope == 'full' ? 'Full return' : 'Partial return')}${n.createdAt != null ? ' · ${DateFormat('d MMM').format(n.createdAt!.toLocal())}' : ''}', style: context.type.caption.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              Text('-${Money.format(n.totalMinor / (n.exponent <= 0 ? 1 : List.filled(n.exponent, 10).fold<num>(1, (a, b) => a * b)), currency: n.currency, exponent: n.exponent)}', style: context.type.amountMd.copyWith(color: p.dangerFg)),
            ],
          ),
        ),
      ),
    );
  }
}
