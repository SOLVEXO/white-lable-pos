import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/views/pos_pin_login_view.dart' show kPinBorder, kPinSurface;
import 'package:flutter/material.dart';

/// Dark-themed skeleton for the PIN login screen's brief "loading store" state.
/// Uses [Skeleton]'s own `switchColor: false` (light-on-dark) sweep directly,
/// since this screen sits on [kPinBg] rather than the app's usual light cards.
class PosPinLoginShimmer extends StatelessWidget {
  const PosPinLoginShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(children: [
        const Skeleton(width: 64, height: 64, cornerRadius: 32, switchColor: false),
        const SizedBox(height: 14),
        const Skeleton(height: 18, width: 150, switchColor: false),
        const SizedBox(height: 8),
        const Skeleton(height: 12, width: 190, switchColor: false),
        const SizedBox(height: 28),
        _fieldBar(),
        const SizedBox(height: 20),
        _fieldBar(),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const Skeleton(width: 16, height: 16, cornerRadius: 8, switchColor: false),
            ),
          ),
        ),
        const SizedBox(height: 32),
        _keypadGrid(),
      ]),
    );
  }

  Widget _fieldBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPinSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPinBorder),
      ),
      child: const Skeleton(height: 16, width: double.infinity, switchColor: false),
    );
  }

  Widget _keypadGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: List.generate(
        12,
        (i) => const Skeleton(height: double.infinity, width: double.infinity, cornerRadius: 16, switchColor: false),
      ),
    );
  }
}
