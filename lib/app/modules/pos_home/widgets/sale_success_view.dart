import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';

/// Shown only after a Charge that the server accepted ([SaleOutcome.completed]) or that was saved on this device
/// ([SaleOutcome.queuedOffline]) — both are read from the controller (`lastOutcome`, `lastReceipt`); a failed Charge
/// leaves them null and this view never opens. The receipt "prints" upward into place.
///
/// Actions: Print again (auto-print already ran per the printer settings), Share (PDF of `lastReceipt`), New sale.
class SaleSuccessView extends StatefulWidget {
  const SaleSuccessView({super.key, required this.c});
  final PosHomeController c;

  @override
  State<SaleSuccessView> createState() => _SaleSuccessViewState();
}

class _SaleSuccessViewState extends State<SaleSuccessView> with SingleTickerProviderStateMixin {
  late final SaleOutcome? _outcome = widget.c.lastOutcome.value;
  late final ReceiptData? _receipt = widget.c.lastReceipt.value;
  late final AnimationController _paper;
  bool _printing = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _paper = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (_outcome == null) {
      // never show a "success" the controller did not report
      WidgetsBinding.instance.addPostFrameCallback((_) => Get.back<void>());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_outcome != null && !_paper.isAnimating && _paper.value == 0) {
      Motion.reduced(context) ? _paper.value = 1 : _paper.forward();
    }
  }

  @override
  void dispose() {
    _paper.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    final r = _receipt;
    if (r == null || _printing) return;
    if (!Get.isRegistered<ThermalPrinterService>()) {
      AppToast.warning('No printer set up. Go to Settings → Receipt Printer.');
      return;
    }
    setState(() => _printing = true);
    try {
      final error = await Get.find<ThermalPrinterService>().printReceipt(receipt: r);
      error == null ? AppToast.success('Receipt printed.') : AppToast.error('$error You can also share it as PDF.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _share() async {
    final r = _receipt;
    if (r == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await ReceiptPdfBuilder.build(data: r);
      final file = XFile.fromData(Uint8List.fromList(bytes), name: 'receipt-${r.receiptNumber}.pdf', mimeType: 'application/pdf');
      await SharePlus.instance.share(ShareParams(files: [file], subject: 'Receipt ${r.receiptNumber}'));
    } catch (_) {
      AppToast.error('Failed to generate the receipt PDF.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_outcome == null) return const Scaffold(body: SizedBox.shrink());
    final p = context.palette;
    final offline = _outcome == SaleOutcome.queuedOffline;
    final tone = offline ? p.warningFg : p.successFg;
    final toneSoft = offline ? p.warningSoft : p.successSoft;
    final r = _receipt;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.s5, Space.s6, Space.s5, Space.s5),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Motion.of(context, Motion.slower),
                    curve: Motion.spring,
                    builder: (context, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: toneSoft, shape: BoxShape.circle),
                      child: Icon(offline ? Icons.cloud_off_rounded : Icons.check_rounded, size: 38, color: tone),
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(offline ? 'Saved offline' : 'Sale complete', key: const Key('successTitle'), style: context.type.headline.copyWith(color: p.textPrimary)),
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    offline
                        ? 'It will sync automatically when the connection returns. Do not ring it up again.'
                        : 'Payment received.',
                    key: const Key('successSubtitle'),
                    textAlign: TextAlign.center,
                    style: context.type.body.copyWith(color: p.textSecondary),
                  ),
                  if (r != null) ...[
                    const SizedBox(height: Space.s3),
                    StatusBadge(
                      'Receipt ${r.receiptNumber}',
                      key: const Key('receiptNumber'),
                      tone: offline ? StatusTone.warning : StatusTone.success,
                      icon: offline ? Icons.schedule_rounded : Icons.receipt_long_rounded,
                    ),
                  ],
                  const SizedBox(height: Space.s5),
                  Expanded(
                    child: r == null
                        ? const SizedBox.shrink()
                        : ClipRect(
                            child: AnimatedBuilder(
                              animation: _paper,
                              builder: (context, child) {
                                final t = Motion.emphasized.transform(_paper.value);
                                return FractionalTranslation(translation: Offset(0, 1 - t), child: Opacity(opacity: t.clamp(0.0, 1.0), child: child));
                              },
                              child: _Paper(receipt: r, offline: offline),
                            ),
                          ),
                  ),
                  const SizedBox(height: Space.s4),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          key: const Key('printAgain'),
                          label: 'Print again',
                          icon: Icons.print_outlined,
                          variant: AppButtonVariant.secondary,
                          loading: _printing,
                          onPressed: r == null ? null : _print,
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: AppButton(
                          key: const Key('shareReceipt'),
                          label: 'Share',
                          icon: Icons.ios_share_rounded,
                          variant: AppButtonVariant.secondary,
                          loading: _sharing,
                          onPressed: r == null ? null : _share,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s3),
                  AppButton(key: const Key('newSale'), label: 'New sale', icon: Icons.add_rounded, size: AppButtonSize.lg, onPressed: () => Get.back<void>()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.receipt, required this.offline});
  final ReceiptData receipt;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return ReceiptPanel(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, Space.s2),
        child: Row(
          children: [
            Expanded(child: Text(receipt.dateText, style: t.caption.copyWith(color: p.textMuted))),
            if (receipt.cashier != null) Text(receipt.cashier!, style: t.caption.copyWith(color: p.textMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        children: [
          for (final l in receipt.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: t.body.copyWith(color: p.textPrimary)),
                        Text(l.qtyAndPrice, style: t.amountMd.copyWith(fontSize: 12, color: p.textMuted)),
                      ],
                    ),
                  ),
                  Text(l.total, style: t.amountMd.copyWith(color: p.textPrimary)),
                ],
              ),
            ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ReceiptDivider(padding: EdgeInsets.only(bottom: Space.s2)),
            ReceiptRow('Subtotal', receipt.subtotal),
            if (receipt.discount != null) ReceiptRow(receipt.discountLabel ?? 'Discount', receipt.discount!, valueColor: p.successFg),
            if (receipt.tax != null) ReceiptRow(receipt.taxLabel ?? 'Tax', receipt.tax!),
            const ReceiptDivider(padding: EdgeInsets.symmetric(vertical: Space.s2)),
            Row(
              children: [
                Expanded(child: Text('Total', style: t.subtitle.copyWith(color: p.textPrimary))),
                AmountText(receipt.total, key: const Key('successTotal'), style: t.amountLg),
              ],
            ),
            const SizedBox(height: Space.s2),
            for (final pay in receipt.payments) ReceiptRow(pay.label, pay.amount),
            if (receipt.change != null) ReceiptRow('Change', receipt.change!, strong: true, valueColor: p.successFg),
          ],
        ),
      ),
    );
  }
}
