import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class PosSessionHistoryShimmer extends StatelessWidget {
  const PosSessionHistoryShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonList(padding: EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8));
  }
}
