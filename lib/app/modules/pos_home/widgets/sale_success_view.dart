import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';

/// Shown only after a Charge that the server accepted ([SaleOutcome.completed]) or that was saved on this device
/// ([SaleOutcome.queuedOffline]) — both are read from the controller (`lastOutcome`, `lastReceipt`); a failed Charge
/// leaves them null and this view never opens. The receipt "prints" upward into place.
///
/// Actions: Print again (auto-print already ran per the printer settings), Share (PDF of `lastReceipt`), New sale.
class SaleSuccessView extends StatefulWidget {
  const SaleSuccessView({super.key, required this.c, this.repository});
  final PosHomeController c;

  /// Asks the server for the digital-receipt link (injectable for tests).
  final PosRepository? repository;

  @override
  State<SaleSuccessView> createState() => _SaleSuccessViewState();
}

class _SaleSuccessViewState extends State<SaleSuccessView> with SingleTickerProviderStateMixin {
  late final SaleOutcome? _outcome = widget.c.lastOutcome.value;
  late final ReceiptData? _receipt = widget.c.lastReceipt.value;
  late final PosSaleModel? _sale = widget.c.lastSale.value;
  late final AnimationController _paper;
  bool _printing = false;
  bool _sharing = false;

  /// The public digital-receipt link (G2.4): its QR is shown to the customer, and it can be shared. Null while loading / when the
  /// sale has none yet (an offline sale gets one after it syncs).
  String? _link;
  bool _linkLoading = false;

  Future<void> _loadLink() async {
    final id = _receipt?.saleId;
    if (id == null || _outcome != SaleOutcome.completed) return;
    setState(() => _linkLoading = true);
    final url = await (widget.repository ?? PosRepository()).getReceiptLink(id);
    if (!mounted) return;
    setState(() {
      _link = url;
      _linkLoading = false;
    });
  }

  Future<void> _shareLink() async {
    final link = _link;
    if (link == null) return;
    await SharePlus.instance.share(ShareParams(text: link, subject: 'Receipt ${_receipt?.receiptNumber ?? ''}'));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLink());
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
                  if (_sale != null) _CustomerRecap(sale: _sale),
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
                  const SizedBox(height: Space.s3),
                  _DigitalReceipt(link: _link, loading: _linkLoading, offline: offline, onShare: _shareLink),
                  const SizedBox(height: Space.s3),
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


/// The customer's digital receipt: a QR that opens the public receipt page, and the same link to share. Hidden for a sale with no
/// link (a failed lookup just means no QR — the printed / PDF receipt is unaffected).
class _DigitalReceipt extends StatelessWidget {
  const _DigitalReceipt({required this.link, required this.loading, required this.offline, required this.onShare});
  final String? link;
  final bool loading;
  final bool offline;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    if (offline) {
      return Text('The digital receipt (QR) is available once this sale syncs.', key: const Key('digitalReceiptOffline'), textAlign: TextAlign.center, style: t.caption.copyWith(color: p.textMuted));
    }
    if (link == null) {
      return loading ? const SizedBox(height: 4, child: LinearProgressIndicator(key: Key('digitalReceiptLoading'))) : const SizedBox.shrink();
    }
    return AppCard(
      color: p.surface,
      radius: Radii.rMd,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            color: Colors.white, // a QR needs a light quiet zone in dark mode too
            child: QrImageView(key: const Key('receiptQr'), data: link!, size: 92, padding: EdgeInsets.zero, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square), dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square)),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Digital receipt', style: t.subtitle.copyWith(color: p.textPrimary)),
                Text('The customer scans this to see their receipt — no personal details on it.', style: t.caption.copyWith(color: p.textSecondary)),
                TextButton.icon(key: const Key('shareReceiptLink'), onPressed: onShare, icon: const Icon(Icons.link_rounded, size: 18), label: const Text('Share link')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// G3.3: what the sale did for the customer — points earned and redeemed, store credit spent. Nothing for a sale without those.
/// Money is shown in the SALE's own currency and decimals.
class _CustomerRecap extends StatelessWidget {
  const _CustomerRecap({required this.sale});
  final PosSaleModel sale;

  @override
  Widget build(BuildContext context) {
    String m(num v) => Money.format(v, currency: sale.currency, exponent: sale.currencyExponent);
    final loyalty = sale.loyalty;
    final credit = sale.payments.where((p) => p.method == 'store_credit').fold(0.0, (a, p) => a + p.amount);
    final lines = <(Key, IconData, String)>[
      if (credit > 0) (const Key('recapCredit'), Icons.account_balance_wallet_outlined, 'Store credit used ${m(credit)}'),
      if (loyalty != null && loyalty.redeemedPoints > 0) (const Key('recapRedeemed'), Icons.stars_rounded, 'Redeemed ${loyalty.redeemedPoints} points (−${m(loyalty.redeemValueMinor / _pow10(sale.currencyExponent))})'),
      if (loyalty != null && loyalty.earnedPoints > 0) (const Key('recapEarned'), Icons.add_circle_outline_rounded, 'Earned ${loyalty.earnedPoints} points'),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Column(
        children: [
          for (final (key, icon, text) in lines)
            Padding(
              key: key,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: p.successFg),
                  const SizedBox(width: Space.s2),
                  Flexible(child: Text(text, textAlign: TextAlign.center, style: context.type.body.copyWith(color: p.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static num _pow10(int e) => e <= 0 ? 1 : List.filled(e, 10).fold<num>(1, (a, b) => a * b);
}
