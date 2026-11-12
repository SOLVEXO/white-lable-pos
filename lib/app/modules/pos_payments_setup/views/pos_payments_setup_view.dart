import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/controllers/pos_payments_setup_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G5.4 — Owner → Payments setup. Raast QR (verification status, test-mode badge, on / off), card on a separate bank terminal (on / off) and
/// the card gateway (not available yet). Errors are shown in place; nothing here is decided on the device.
class PosPaymentsSetupView extends StatelessWidget {
  PosPaymentsSetupView({super.key, PosPaymentsSetupController? controller}) : c = controller ?? Get.put(PosPaymentsSetupController());
  final PosPaymentsSetupController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Payments setup'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Obx(() {
              if (c.loading.value && c.status.value == null) return const Center(child: CircularProgressIndicator(key: Key('paySetupLoading')));
              final s = c.status.value;
              if (s == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s5),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.error_outline_rounded, size: 40, color: p.textMuted),
                      const SizedBox(height: Space.s3),
                      Text(c.error.value ?? 'Could not load payment settings.', key: const Key('paySetupError'), textAlign: TextAlign.center, style: context.type.body.copyWith(color: p.textSecondary)),
                      const SizedBox(height: Space.s4),
                      AppButton(key: const Key('paySetupReload'), label: 'Reload', expand: false, onPressed: c.load),
                    ]),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  children: [
                    if (c.error.value != null)
                      Padding(padding: const EdgeInsets.only(bottom: Space.s3), child: Text(c.error.value!, key: const Key('paySetupSaveError'), style: context.type.body.copyWith(color: p.danger))),
                    _RaastCard(c: c, r: s.raast),
                    const SizedBox(height: Space.s4),
                    _SwitchCard(
                      key: const Key('cardTerminalCard'),
                      icon: Icons.point_of_sale_rounded,
                      title: 'Card on a bank terminal',
                      text: 'Take cards on your own bank machine. The cashier types the approval code from the slip; it shows on the shift close, reports and refunds.',
                      value: s.cardExternalTerminal,
                      busy: c.saving.value == 'cardExternalTerminal',
                      switchKey: const Key('cardTerminalSwitch'),
                      onChanged: c.setCardTerminal,
                    ),
                    const SizedBox(height: Space.s4),
                    _ProviderCard(
                      key: const Key('cardGatewayCard'),
                      icon: Icons.credit_score_rounded,
                      title: 'Card payments in the app',
                      provider: s.cardGateway,
                      offText: 'Not available yet. Solvexo is choosing a card provider; until then, use a bank terminal.',
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _RaastCard extends StatelessWidget {
  const _RaastCard({required this.c, required this.r});
  final PosPaymentsSetupController c;
  final RaastStatus? r;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = this.r;
    final (label, tone) = switch (r?.kybStatus) {
      'verified' => ('Verified', StatusTone.success),
      'submitted' || 'under_review' => ('In review', StatusTone.warning),
      'rejected' => ('Sent back', StatusTone.danger),
      'draft' => ('Draft', StatusTone.neutral),
      _ => ('Not started', StatusTone.neutral),
    };
    final on = r != null && !r.disabledByStore;
    final why = r == null
        ? 'Raast status is not available.'
        : !r.verified
            ? 'Raast QR needs your business verification first.'
            : r.enabled
                ? 'Customers can pay by scanning a Raast QR at the till.'
                : r.disabledByStore
                    ? 'Raast QR is switched off for this store.'
                    : r.reason == 'no_sub_merchant'
                        ? 'Verified. Raast switches on once the payment provider finishes setting up your business.'
                        : 'Raast is not available right now (${r.reason ?? 'unknown'}).';
    return AppCard(
      key: const Key('raastCard'),
      radius: Radii.rMd,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.qr_code_2_rounded, color: p.textPrimary),
          const SizedBox(width: Space.s2),
          Expanded(child: Text('Raast QR', style: context.type.subtitle)),
          if (r?.testMode == true) ...[const StatusBadge('Test mode', key: Key('raastTestMode'), tone: StatusTone.warning), const SizedBox(width: Space.s2)],
          StatusBadge(label, key: const Key('raastKybStatus'), tone: tone),
        ]),
        const SizedBox(height: Space.s2),
        Text(why, key: const Key('raastWhy'), style: context.type.body.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s3),
        if (r != null && r.verified)
          SwitchListTile.adaptive(
            key: const Key('raastSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Accept Raast QR'),
            value: on,
            onChanged: c.saving.value != null ? null : c.setRaast,
          )
        else
          AppButton(key: const Key('raastVerify'), label: 'Business verification', variant: AppButtonVariant.secondary, expand: false, onPressed: () => Get.toNamed(Routes.posKyb)),
      ]),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({super.key, required this.icon, required this.title, required this.text, required this.value, required this.busy, required this.switchKey, required this.onChanged});
  final IconData icon;
  final String title;
  final String text;
  final bool value;
  final bool busy;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: p.textPrimary),
          const SizedBox(width: Space.s2),
          Expanded(child: Text(title, style: context.type.subtitle)),
          if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) else Switch.adaptive(key: switchKey, value: value, onChanged: onChanged),
        ]),
        const SizedBox(height: Space.s2),
        Text(text, style: context.type.body.copyWith(color: p.textSecondary)),
      ]),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({super.key, required this.icon, required this.title, required this.provider, required this.offText});
  final IconData icon;
  final String title;
  final ConnectorProvider provider;
  final String offText;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready = provider.configured;
    return AppCard(
      radius: Radii.rMd,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: p.textPrimary),
          const SizedBox(width: Space.s2),
          Expanded(child: Text(title, style: context.type.subtitle)),
          if (provider.testMode) const StatusBadge('Test mode', tone: StatusTone.warning) else StatusBadge(ready ? 'Ready' : 'Not available', tone: ready ? StatusTone.success : StatusTone.neutral),
        ]),
        const SizedBox(height: Space.s2),
        Text(ready && !provider.testMode ? 'Connected.' : offText, style: context.type.body.copyWith(color: p.textSecondary)),
      ]),
    );
  }
}
