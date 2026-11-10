import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Search the existing products (the inventory search) and pick one to add as a line. Closes with the chosen [InvRow].
class SupplyProductSearchSheet extends StatelessWidget {
  const SupplyProductSearchSheet({super.key, required this.search});
  final SupplyProductSearch search;

  static Future<InvRow?> open(SupplyProductSearch search) => AppBottomSheet.showGet<InvRow>(SupplyProductSearchSheet(search: search), title: 'Add a product', scrollable: false);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          AppSearchBar(hint: 'Search name, SKU or barcode', autofocus: true, onChanged: search.onChanged),
          const SizedBox(height: Space.s2),
          Expanded(
            child: Obx(() {
              if (search.searching.value && search.results.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('supplySearching')));
              if (search.error.value != null) {
                return Center(
                  child: Text(
                    search.error.value!,
                    key: const Key('supplySearchError'),
                    style: t.body.copyWith(color: p.dangerFg),
                  ),
                );
              }
              if (search.results.isEmpty) {
                return Center(
                  child: Text('Type to search the products you already sell.', style: t.body.copyWith(color: p.textMuted)),
                );
              }
              return ListView.builder(
                key: const Key('supplySearchResults'),
                itemCount: search.results.length,
                itemBuilder: (_, i) {
                  final r = search.results[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Space.s2),
                    child: AppCard(
                      key: Key('supplyPick_${r.variantId}'),
                      radius: Radii.rMd,
                      onTap: () => Get.back<InvRow>(result: r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.subtitle.copyWith(color: p.textPrimary),
                          ),
                          Text([if (r.sku.isNotEmpty) r.sku, if (r.optionsLabel.isNotEmpty) r.optionsLabel, '${r.stock} on hand'].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
