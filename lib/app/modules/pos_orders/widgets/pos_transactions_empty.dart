import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosTransactionsEmpty extends StatelessWidget {
  const PosTransactionsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No transactions today',
      message: 'Completed sales will appear here',
    );
  }
}
