import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Return complete: the credit note number, how much, and what to do per tender (card machine / bank transfer / cash from the drawer).
class PosReturnCompleteView extends StatelessWidget {
  const PosReturnCompleteView({super.key, required this.c});
  final PosReturnController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final s = c.sale.value;
    final note = c.result.value ?? const {};
    final number = note['number'] as String?;
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
                  Container(width: 72, height: 72, decoration: BoxDecoration(color: p.successSoft, shape: BoxShape.circle), child: Icon(Icons.check_rounded, size: 38, color: p.successFg)),
                  const SizedBox(height: Space.s4),
                  Semantics(header: true, liveRegion: true, child: Text('Return recorded', key: const Key('returnDoneTitle'), style: t.headline.copyWith(color: p.textPrimary))),
                  const SizedBox(height: Space.s2),
                  AmountText(Money.format(c.resultAmount, currency: s?.currency, exponent: s?.currencyExponent), key: const Key('returnDoneAmount'), style: t.amountLg),
                  if (number != null) ...[const SizedBox(height: Space.s2), StatusBadge('Credit note $number', key: const Key('returnDoneNote'), tone: StatusTone.accent, icon: Icons.assignment_return_outlined)],
                  const SizedBox(height: Space.s5),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppCard(
                        radius: Radii.rMd,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Now give the customer', style: t.title.copyWith(color: p.textPrimary)),
                            const SizedBox(height: Space.s2),
                            for (final line in c.resultInstructions) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(line, key: const Key('returnDoneInstruction'), style: t.body.copyWith(color: p.textSecondary))),
                            if (c.resultInstructions.isEmpty) Text('Nothing to hand back.', style: t.body.copyWith(color: p.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s3),
                  if (number != null && s != null)
                    AppButton(
                      key: const Key('openCreditNote'),
                      label: 'Credit note — print / share',
                      icon: Icons.description_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () async {
                        final d = PosDocumentsController(saleId: s.id);
                        Get.put<PosDocumentsController>(d, tag: 'return-${s.id}');
                        await d.load();
                        Get.to<void>(() => CreditNoteView(controller: d, number: number));
                      },
                    ),
                  const SizedBox(height: Space.s3),
                  AppButton(key: const Key('returnDone'), label: 'Done', size: AppButtonSize.lg, onPressed: () => Get.back<void>()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
