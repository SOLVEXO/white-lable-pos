import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosProductsEmpty extends StatelessWidget {
  const PosProductsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No products found',
      message: 'Try a different name or SKU',
    );
  }
}
