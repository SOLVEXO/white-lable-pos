import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/refund_instructions.dart';

/// "Do this now" after a refund is recorded: per tender, exactly what the cashier must do (refund on the card
/// machine, give cash from the drawer) — taken from the SERVER's recorded split, so the cash slice is precisely
/// what the shift report will expect to be missing from the drawer.
Future<void> showRefundDoneDialog(PosSaleModel sale, List<PosPaymentLine> tenders, double? amount) async {
  final lines = posRefundInstructions(
    [for (final t in tenders) PosRefundSplit(t.method, t.amount)],
    currency: sale.currency,
    exponent: sale.currencyExponent,
  );
  if (lines.isEmpty) return;
  await Get.dialog<void>(
    AlertDialog(
      title: const Text('Refund recorded'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (amount != null)
          Text('Refunded ${Money.format(amount, currency: sale.currency, exponent: sale.currencyExponent)}. Now:', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $l')),
      ]),
      actions: [TextButton(onPressed: () => Get.back(), child: const Text('Done'))],
    ),
  );
}
