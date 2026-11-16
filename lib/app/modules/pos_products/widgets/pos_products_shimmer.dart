import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Loading placeholder for the product list (the design system's shimmering skeleton rows).
class PosProductsShimmer extends StatelessWidget {
  const PosProductsShimmer({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonList();
}
