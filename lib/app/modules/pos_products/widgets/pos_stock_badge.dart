import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Stock pill for a product row: the count (or ∞ / Out) as a [StatusBadge], with a caption under it.
class PosStockBadge extends StatelessWidget {
  final int stockCount;
  final bool unlimited;

  const PosStockBadge({super.key, required this.stockCount, this.unlimited = false});

  bool get _inStock => unlimited || stockCount > 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(
          unlimited ? '∞' : (_inStock ? stockCount.toString() : 'Out'),
          tone: _inStock ? StatusTone.success : StatusTone.danger,
        ),
        const SizedBox(height: Space.s1),
        Text(
          unlimited ? 'unlimited' : (_inStock ? 'in stock' : 'out of stock'),
          style: context.type.caption.copyWith(color: p.textMuted),
        ),
      ],
    );
  }
}
