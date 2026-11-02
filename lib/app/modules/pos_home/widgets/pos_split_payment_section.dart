import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Split-tender entry: one row per tender (method + amount [+ reference for card / bank]).
/// For cash the amount is what the customer HANDS OVER — cash above what's left after the other tenders is
/// change (the server computes and stores it). Card / other can never add up to more than the total.
/// All of this is re-validated by the server; the status line only says what the server will accept.
class PosSplitPaymentSection extends StatelessWidget {
  final PosHomeController c;
  const PosSplitPaymentSection({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < c.splitLines.length; i++) _Row(c: c, index: i),
        const SizedBox(height: 4),
        Row(children: [
          TextButton.icon(
            onPressed: c.splitLines.length >= 8 ? null : c.addSplitLine,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add payment'),
          ),
          const Spacer(),
          _Status(c: c),
        ]),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final PosHomeController c;
  final int index;
  const _Row({required this.c, required this.index});

  @override
  Widget build(BuildContext context) {
    final line = c.splitLines[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Obx(() {
        final method = line.method.value;
        final isCash = method == PosPaymentMethod.cash;
        return Column(children: [
          Row(children: [
            SizedBox(
              width: 96,
              child: DropdownButtonFormField<String>(
                initialValue: method,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                items: [for (final m in PosPaymentMethod.all) DropdownMenuItem(value: m, child: Text(PosPaymentMethod.label(m), style: const TextStyle(fontSize: 13)))],
                onChanged: (v) {
                  if (v != null) {
                    line.method.value = v;
                    c.cartItems.refresh();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomTextField(
                controller: line.amount,
                hintText: isCash ? 'Cash handed over (${Money.symbol()})' : 'Amount (${Money.symbol()})',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                fillColor: AppColors.background,
                onChanged: (_) => c.cartItems.refresh(),
                suffixIcon: GestureDetector(
                  onTap: () => c.fillRemaining(index),
                  child: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18, color: AppColors.iosGrey),
                ),
              ),
            ),
            IconButton(
              onPressed: c.splitLines.length <= 1 ? null : () => c.removeSplitLine(index),
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Remove',
            ),
          ]),
          if (!isCash) ...[
            const SizedBox(height: 6),
            CustomTextField(
              controller: line.reference,
              hintText: method == PosPaymentMethod.card ? 'Card auth code (optional)' : 'Bank / transaction reference (optional)',
              fillColor: AppColors.background,
            ),
          ],
        ]);
      }),
    );
  }
}

class _Status extends StatelessWidget {
  final PosHomeController c;
  const _Status({required this.c});

  @override
  Widget build(BuildContext context) {
    final check = c.paymentCheck;
    late String label;
    late String value;
    late Color color;
    if (check.nonCashExceedsTotal) {
      label = 'Card / other is more than the total';
      value = '';
      color = AppColors.red;
    } else if (!check.covered) {
      label = 'Remaining';
      value = Money.format(check.shortBy);
      color = AppColors.red;
    } else if (check.change > 0) {
      label = 'Change due';
      value = Money.format(check.change);
      color = AppColors.green2;
    } else {
      label = 'Fully paid';
      value = '';
      color = AppColors.green2;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CustomText(text: label, fontSize: AppFontSize.tiny, color: color),
      if (value.isNotEmpty) ...[
        const SizedBox(width: 6),
        CustomText(text: value, fontSize: AppFontSize.verySmall, fontWeight: FontWeight.bold, color: color),
      ],
    ]);
  }
}
