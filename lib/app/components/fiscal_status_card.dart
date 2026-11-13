import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G6.1 — a document's fiscal state on screen (checkout result, sale detail, tax invoice, credit note), from the server's contract
/// (FISCAL_CONTRACT.md). Hidden when the store does not fiscalise. Never blocks anything: the sale is complete whatever this says.
///  * confirmed → the server's display lines (and "Test mode" when the provider is not live);
///  * pending   → "Fiscal: pending" (+ "sent automatically" when the server will retry);
///  * failed    → warning + the server's message; the owner can retry from Integrations → Fiscal;
///  * rejected  → error + the server's message.
class FiscalStatusCard extends StatelessWidget {
  const FiscalStatusCard({super.key, required this.fiscal, this.compact = false});
  final PosFiscalInfo? fiscal;
  final bool compact;

  static const ownerHint = 'The sale is complete. The owner can send it again from Integrations → Fiscal.';

  @override
  Widget build(BuildContext context) {
    final f = fiscal;
    if (f == null || !f.required) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.type;
    final (label, tone, icon) = switch (f.status) {
      'confirmed' => ('Fiscal: confirmed', StatusTone.success, Icons.verified_outlined),
      'pending' => ('Fiscal: pending', StatusTone.info, Icons.schedule_rounded),
      'failed' => ('Fiscal: not sent', StatusTone.warning, Icons.warning_amber_rounded),
      _ => ('Fiscal: refused', StatusTone.danger, Icons.error_outline_rounded),
    };
    final body = <Widget>[
      Wrap(spacing: Space.s2, runSpacing: Space.s1, children: [
        StatusBadge(label, tone: tone, icon: icon),
        if (f.testMode) const StatusBadge('Test mode', tone: StatusTone.neutral),
      ]),
      if (f.confirmed)
        for (final l in f.displayLines.isNotEmpty ? f.displayLines : [if (f.number != null) FiscalLine('', f.number!)])
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Text(l.label.isEmpty ? l.value : '${l.label}  ${l.value}', style: t.body.copyWith(color: p.textPrimary)),
          ),
      if (f.pending && !compact)
        Padding(
          padding: const EdgeInsets.only(top: Space.s1),
          child: Text(f.willRetry ? 'It will be sent to the tax authority automatically.' : 'Not sent to the tax authority yet.', style: t.caption.copyWith(color: p.textSecondary)),
        ),
      if (f.needsAttention) ...[
        if ((f.message ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Text(f.message!, key: const Key('fiscalMessage'), style: t.body.copyWith(color: f.rejected ? p.dangerFg : p.warningFg)),
          ),
        if (f.failed && !compact)
          Padding(padding: const EdgeInsets.only(top: Space.s1), child: Text(ownerHint, style: t.caption.copyWith(color: p.textSecondary))),
      ],
    ];
    return Padding(
      key: const Key('fiscalStatus'),
      padding: const EdgeInsets.only(top: Space.s3),
      child: AppCard(padding: const EdgeInsets.all(Space.s3), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body)),
    );
  }
}
