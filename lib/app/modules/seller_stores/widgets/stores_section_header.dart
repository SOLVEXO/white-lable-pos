import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresSectionHeader extends StatelessWidget {
  final SellerStoresController controller;

  const StoresSectionHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: Row(
        children: [
          Text('Your Stores', style: t.title.copyWith(color: p.textPrimary)),
          const SizedBox(width: Space.s2),
          Obx(
            () => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2 + 2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: Radii.rFull,
              ),
              child: Text(
                '${controller.stores.length}',
                style: t.caption.copyWith(
                  color: p.accentFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
