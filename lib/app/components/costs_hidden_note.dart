import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.8: shown where cost figures would be when the owner hides costs from managers (the server sends `costsHidden: true` and leaves them out) —
/// a short notice instead of blanks or zeros.
class CostsHiddenNote extends StatelessWidget {
  const CostsHiddenNote({super.key, this.what = 'Costs, margins and stock value'});
  final String what;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('costsHidden'),
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rMd),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: p.textSecondary),
          const SizedBox(width: Space.s2),
          Expanded(child: Text('$what are hidden for your role by the owner.', style: context.type.bodySmall.copyWith(color: p.textSecondary))),
        ],
      ),
    );
  }
}
