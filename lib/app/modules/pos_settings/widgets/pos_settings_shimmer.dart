import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

/// Loading placeholder for the Settings tab: the profile card, three groups of rows and the close-shift button.
class PosSettingsShimmer extends StatelessWidget {
  const PosSettingsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _profile(),
                const SizedBox(height: Space.s6),
                _section(4), // REGISTER
                _section(3), // SHIFT
                _section(3), // PREFERENCES
                const SizedBox(height: Space.s2),
                const SkeletonBox(height: Space.minTouch, radius: Radii.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profile() => const Row(
        children: [
          SkeletonBox(width: 56, height: 56, radius: Radii.full),
          SizedBox(width: Space.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 16, width: 120),
                SizedBox(height: Space.s2),
                SkeletonBox(height: 12, width: 160),
                SizedBox(height: Space.s2),
                SkeletonBox(height: 20, width: 170, radius: Radii.full),
              ],
            ),
          ),
        ],
      );

  Widget _section(int rows) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(alignment: Alignment.centerLeft, child: SkeletonBox(height: 16, width: 90)),
            const SizedBox(height: Space.s3),
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: Space.s2),
              const SkeletonBox(height: 64, radius: Radii.lg),
            ],
          ],
        ),
      );
}
