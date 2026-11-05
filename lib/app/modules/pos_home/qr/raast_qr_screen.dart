import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The Raast QR screen — the customer side of the counter has to read it too, so the amount and the QR are large.
///
/// States (all from [RaastQrController.phase]): creating · waiting (QR + countdown) · checking ("Checking payment…", the network
/// dropped) · confirmed · failed / expired / cancelled ("Generate new QR" or "Choose another method") · unavailable.
/// The system back gesture is intercepted: leaving goes through Cancel so a live QR is never abandoned unpaid-but-active.
class RaastQrScreen extends StatefulWidget {
  const RaastQrScreen({super.key, required this.tag, this.showSimulate = false});
  final String tag;

  /// "Simulate customer paid" — only for the mock provider in debug builds (the server refuses it anywhere else).
  final bool showSimulate;

  /// Opens the screen and resolves with how the payment ended. The caller then continues (or not) with the sale.
  static Future<QrResult> collect(RaastQrController controller, {bool showSimulate = false}) async {
    final tag = 'qr-${identityHashCode(controller)}';
    Get.put<RaastQrController>(controller, tag: tag);
    Get.to<void>(() => RaastQrScreen(tag: tag, showSimulate: showSimulate), fullscreenDialog: true, transition: Transition.fadeIn, duration: const Duration(milliseconds: 220));
    try {
      final r = await controller.result;
      if (r.isConfirmed) await Future<void>.delayed(const Duration(milliseconds: 1100)); // let "Payment received" be seen
      if (r.kind != QrResultKind.detached) Get.back<void>(); // close this screen — unless it is already gone (the till locked)
      return r;
    } finally {
      await Get.delete<RaastQrController>(tag: tag, force: true);
    }
  }

  @override
  State<RaastQrScreen> createState() => _RaastQrScreenState();
}

class _RaastQrScreenState extends State<RaastQrScreen> {
  late final RaastQrController c = Get.find<RaastQrController>(tag: widget.tag); // captured: the controller may already be deleted at dispose
  bool get showSimulate => widget.showSimulate;

  @override
  void dispose() {
    c.detach(); // no-op when the payment already ended; otherwise the till was locked / replaced: keep the pending payment
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final phase = c.phase.value;
      final busy = c.busy.value;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (phase == QrPhase.waiting || phase == QrPhase.checking) {
            c.cancel();
          } else {
            c.giveUp();
          }
        },
        child: Scaffold(
          backgroundColor: p.background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 700 && box.maxWidth > box.maxHeight;
                final qrSide = (wide ? box.maxHeight * 0.62 : box.maxWidth * 0.8).clamp(220.0, 460.0);
                final info = _Info(c: c, busy: busy, showSimulate: showSimulate);
                final infoTop = _Info(c: c, busy: busy, showSimulate: showSimulate, showActions: false);
                final infoActions = _Info(c: c, busy: busy, showSimulate: showSimulate, showTop: false);
                final qr = _QrBox(c: c, side: qrSide);
                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.all(Space.s8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: info), const SizedBox(width: Space.s8), qr]),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s4),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - Space.s8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [infoTop, const SizedBox(height: Space.s5), Center(child: qr), infoActions]), // phone: the code sits right under the amount, the buttons below it
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

String _mmss(int s) => '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';

class _Info extends StatelessWidget {
  const _Info({required this.c, required this.busy, required this.showSimulate, this.showTop = true, this.showActions = true});
  final bool showTop;
  final bool showActions;
  final RaastQrController c;
  final bool busy;
  final bool showSimulate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phase = c.phase.value;
    final amount = Money.format(Money.fromMinor(c.amountMinor));
    final i = c.intent.value;
    final (tone, title, icon) = switch (phase) {
      QrPhase.creating => (StatusTone.neutral, 'Preparing QR…', Icons.hourglass_empty_rounded),
      QrPhase.waiting => (StatusTone.info, 'Waiting for payment', Icons.qr_code_scanner_rounded),
      QrPhase.checking => (StatusTone.warning, 'Checking payment…', Icons.sync_rounded),
      QrPhase.confirmed => (StatusTone.success, 'Payment received', Icons.check_circle_rounded),
      QrPhase.failed => (StatusTone.danger, 'Payment failed', Icons.error_outline_rounded),
      QrPhase.expired => (StatusTone.warning, 'QR expired', Icons.timer_off_outlined),
      QrPhase.cancelled => (StatusTone.neutral, 'Payment cancelled', Icons.cancel_outlined),
      QrPhase.unavailable => (StatusTone.warning, 'Raast QR unavailable', Icons.cloud_off_rounded),
    };
    final open = phase == QrPhase.waiting || phase == QrPhase.checking;
    final ended = phase == QrPhase.expired || phase == QrPhase.failed || phase == QrPhase.cancelled;
    final top = <Widget>[
        Text('Raast QR', style: context.type.label.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: Space.s1),
        // the customer reads this from across the counter
        Center(child: AmountText(amount, key: const Key('qrAmount'), style: context.type.display.copyWith(fontSize: 56, height: 1.05))),
        const SizedBox(height: Space.s4),
        Center(key: const Key('qrStatus'), child: StatusBadge(title, tone: tone, icon: icon)),
        if (open && i != null) ...[
          const SizedBox(height: Space.s4),
          _Countdown(c: c),
        ],
        if (c.message.value.isNotEmpty) ...[
          const SizedBox(height: Space.s3),
          Text(c.message.value, key: const Key('qrMessage'), textAlign: TextAlign.center, style: context.type.body.copyWith(color: phase == QrPhase.confirmed ? p.textSecondary : p.textPrimary)),
        ],
        if (phase == QrPhase.waiting || phase == QrPhase.checking) ...[
          const SizedBox(height: Space.s2),
          Text('Customer: open your bank app, choose Raast and scan.', textAlign: TextAlign.center, style: context.type.bodySmall.copyWith(color: p.textSecondary)),
        ],
      ];
    final bottom = <Widget>[
        const SizedBox(height: Space.s6),
        if (open) AppButton(key: const Key('qrCancel'), label: 'Cancel payment', variant: AppButtonVariant.secondary, size: AppButtonSize.lg, loading: busy, onPressed: busy ? null : c.cancel),
        if (ended) ...[
          AppButton(key: const Key('qrRegenerate'), label: 'Generate new QR', size: AppButtonSize.lg, icon: Icons.qr_code_2_rounded, loading: busy, onPressed: busy ? null : c.regenerate),
          const SizedBox(height: Space.s3),
          AppButton(key: const Key('qrAnother'), label: 'Choose another method', variant: AppButtonVariant.secondary, size: AppButtonSize.lg, onPressed: busy ? null : c.giveUp),
        ],
        if (phase == QrPhase.unavailable) ...[
          AppButton(key: const Key('qrRetry'), label: 'Try again', size: AppButtonSize.lg, onPressed: busy ? null : c.regenerate),
          const SizedBox(height: Space.s3),
          AppButton(key: const Key('qrBack'), label: 'Choose another method', variant: AppButtonVariant.secondary, size: AppButtonSize.lg, onPressed: c.giveUp),
        ],
        if (showSimulate && kDebugMode && open) ...[
          const SizedBox(height: Space.s4),
          AppButton(key: const Key('qrSimulate'), label: 'Simulate customer paid (mock)', variant: AppButtonVariant.ghost, onPressed: c.simulatePaid),
        ],
      ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (showTop) ...top, if (showActions) ...bottom]);
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.c});
  final RaastQrController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final left = c.secondsLeft.value;
      final total = c.totalSeconds.value;
      final frac = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
      final low = left <= 30;
      return Semantics(
        liveRegion: true,
        label: 'QR valid for ${_mmss(left)}',
        child: Column(
          children: [
            Text(_mmss(left), key: const Key('qrCountdown'), style: context.type.amountXl.copyWith(color: low ? p.warningFg : p.textPrimary)),
            const SizedBox(height: Space.s2),
            ClipRRect(
              borderRadius: Radii.rFull,
              child: LinearProgressIndicator(value: frac, minHeight: 8, backgroundColor: p.fill, valueColor: AlwaysStoppedAnimation(low ? p.warning : p.accent)),
            ),
          ],
        ),
      );
    });
  }
}

class _QrBox extends StatelessWidget {
  const _QrBox({required this.c, required this.side});
  final RaastQrController c;
  final double side;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final phase = c.phase.value;
      final i = c.intent.value;
      final showQr = i != null && (phase == QrPhase.waiting || phase == QrPhase.checking);
      return Container(
        key: const Key('qrBox'),
        width: side,
        height: side,
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: Radii.rLg, border: Border.all(color: p.border)), // always white: scanners need the contrast, light or dark theme
        child: Center(
          child: switch (phase) {
            QrPhase.creating => const CircularProgressIndicator(),
            QrPhase.confirmed => Icon(Icons.check_circle_rounded, key: const Key('qrConfirmedIcon'), size: side * 0.5, color: p.success),
            QrPhase.unavailable => Icon(Icons.cloud_off_rounded, size: side * 0.4, color: p.textMuted),
            _ when showQr => Opacity(
                opacity: phase == QrPhase.checking ? 0.55 : 1,
                child: QrImageView(key: const Key('qrImage'), data: i.qrPayload, size: side - Space.s8, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M, semanticsLabel: 'Raast QR code for ${Money.format(Money.fromMinor(c.amountMinor))}'),
              ),
            _ => Icon(Icons.qr_code_2_rounded, size: side * 0.5, color: p.textMuted.withValues(alpha: 0.35)), // expired / failed / cancelled: the old code is never shown again
          },
        ),
      );
    });
  }
}
