import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/app/modules/seller_stores/widgets/store_card.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresList extends StatelessWidget {
  final SellerStoresController controller;

  const StoresList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        itemCount: controller.stores.length,
        separatorBuilder: (_, __) => Space.gap3,
        itemBuilder: (_, i) => StoreCard(
          store: controller.stores[i],
          onOpen: () => controller.openStore(controller.stores[i]),
        ),
      ),
    );
  }
}
