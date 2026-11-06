import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "All categories": every category as a big tap target (the chip row scrolls; this shows them all at once).
class CategorySheet extends StatelessWidget {
  const CategorySheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(CategorySheet(c: c), title: 'Categories');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final cats = c.categories;
      return Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        children: [
          for (final id in cats)
            ChoiceChip(
              key: Key('category_$id'),
              label: Text(c.categoryLabel(id)),
              selected: c.selectedCategoryId.value == id,
              selectedColor: p.accentSoft,
              onSelected: (_) {
                c.selectCategory(id);
                Get.back();
              },
            ),
        ],
      );
    });
  }
}
