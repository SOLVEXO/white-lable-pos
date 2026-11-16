import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class PosCloseShiftButton extends StatelessWidget {
  final VoidCallback onTap;

  const PosCloseShiftButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: AppButton(
        label: 'Close Shift & Log Out',
        variant: AppButtonVariant.danger,
        icon: Icons.logout_rounded,
        onPressed: onTap,
      ),
    );
  }
}
