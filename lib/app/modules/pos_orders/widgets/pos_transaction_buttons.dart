import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosTransactionButtons extends StatelessWidget {
  final VoidCallback onReceipt;
  final VoidCallback? onReturn;

  const PosTransactionButtons({
    super.key,
    required this.onReceipt,
    this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final receipt = AppButton(
      label: 'Receipt',
      icon: Icons.receipt_long_outlined,
      variant: AppButtonVariant.secondary,
      onPressed: onReceipt,
    );
    if (onReturn == null) return receipt;
    final ret = AppButton(
      label: 'Return / void',
      icon: Icons.undo_rounded,
      variant: AppButtonVariant.danger,
      onPressed: onReturn,
    );
    // Stack the two buttons when large text would squeeze the labels.
    if (MediaQuery.textScalerOf(context).scale(16) > 19) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [receipt, const SizedBox(height: Space.s2), ret],
      );
    }
    return Row(
      children: [
        Expanded(child: receipt),
        const SizedBox(width: Space.s3),
        Expanded(child: ret),
      ],
    );
  }
}
