import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/product_page_view.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_catalog/controllers/pos_catalog_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Catalog (POS): find an item and edit its price, barcode, PCT/HS code, category and stock. A manager's PIN is needed for every change.
class PosCatalogView extends StatelessWidget {
  PosCatalogView({super.key, PosCatalogController? controller}) : c = controller ?? Get.put(PosCatalogController());
  final PosCatalogController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Catalog'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2), child: AppSearchBar(hint: 'Search items or SKU', onChanged: c.onQueryChanged)),
                Expanded(
                  child: Obx(() {
                    if (c.loading.value && c.results.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('catalogLoading')));
                    if (c.results.isEmpty) return const EmptyState(icon: Icons.inventory_2_outlined, title: 'No items found', message: 'Try another name or SKU.');
                    return ListView(
                      key: const Key('catalogList'),
                      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s6),
                      children: [
                        for (final prod in c.results)
                          for (final v in prod.variants) _Row(product: prod, variant: v),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.product, required this.variant});
  final PosProductModel product;
  final PosProductVariant variant;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('catalogItem_${variant.variantId}'),
        radius: Radii.rMd,
        child: InkWell(
          onTap: () => Get.to<void>(() => PosCatalogItemView(product: product, variant: variant)),
          child: Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(product.hasMultipleVariants ? '${product.name} · ${variant.label}' : product.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                  Text('${variant.sku}${(variant.barcode ?? '').isNotEmpty ? ' · ${variant.barcode}' : ''}', style: t.caption.copyWith(color: p.textMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(Money.format(variant.price), style: t.amountMd.copyWith(color: p.textPrimary)), Text(variant.unlimitedStock ? 'Unlimited' : '${variant.stock} in stock', style: t.caption.copyWith(color: p.textMuted))]),
              Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit one item. Stock is a movement (+/−) with a reason, never an overwrite.
class PosCatalogItemView extends StatelessWidget {
  PosCatalogItemView({super.key, required this.product, required this.variant, PosCatalogItemController? controller})
      : c = controller ?? Get.put(PosCatalogItemController(product: product, variant: variant), tag: variant.variantId);
  final PosProductModel product;
  final PosProductVariant variant;
  final PosCatalogItemController c;

  static const _reasons = <(String, String)>[('correction', 'Count correction'), ('restocked', 'Received stock'), ('damaged', 'Damaged'), ('write_off', 'Write-off')];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: Text(product.name), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0, actions: [
        // G5.2: the full product page (photos, details, every variant, stock by location; managers edit)
        TextButton.icon(key: const Key('openProductPage'), onPressed: () => Get.to<void>(() => ProductPageView(productId: product.productId)), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Product page')),
      ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
              children: [
                Text('SKU ${variant.sku}', style: t.caption.copyWith(color: p.textMuted)),
                const SizedBox(height: Space.s3),
                Obx(() => c.isManager.value ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: Space.s3), child: Text('A manager will be asked to approve each change.', key: const Key('catalogApprovalNote'), style: t.caption.copyWith(color: p.warningFg)))),
                AppTextField(key: const Key('catalogPrice'), label: 'Price', controller: c.price, mono: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))]),
                const SizedBox(height: Space.s3),
                AppTextField(key: const Key('catalogBarcode'), label: 'Barcode', controller: c.barcode, mono: true),
                const SizedBox(height: Space.s3),
                AppTextField(key: const Key('catalogHs'), label: 'PCT / HS code', controller: c.hsCode, mono: true, hint: 'e.g. 0902.40.90', keyboardType: TextInputType.number),
                const SizedBox(height: Space.s3),
                Obx(() {
                  if (c.categories.isEmpty) return const SizedBox.shrink();
                  return DropdownButtonFormField<String>(
                    key: const Key('catalogCategory'),
                    initialValue: c.categories.any((e) => e.id == c.categoryId.value) ? c.categoryId.value : null,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [for (final e in c.categories) DropdownMenuItem(value: e.id, child: Text(e.name))],
                    onChanged: (v) => c.categoryId.value = v,
                  );
                }),
                const SizedBox(height: Space.s4),
                Obx(() => AppButton(key: const Key('catalogSave'), label: 'Save changes', loading: c.saving.value, onPressed: c.saving.value ? null : () async {
                      final ok = await c.save();
                      if (ok) Get.back<void>();
                    })),
                const SizedBox(height: Space.s5),
                Text('Stock', style: t.title.copyWith(color: p.textPrimary)),
                const SizedBox(height: Space.s1),
                if (variant.unlimitedStock)
                  Text('This item has unlimited stock.', style: t.body.copyWith(color: p.textSecondary))
                else ...[
                  Obx(() => Text('${c.stock.value} on hand', key: const Key('catalogStock'), style: t.body.copyWith(color: p.textSecondary))),
                  const SizedBox(height: Space.s2),
                  AppTextField(key: const Key('catalogDelta'), label: 'Add (+) or remove (−) units', controller: c.stockDelta, keyboardType: const TextInputType.numberWithOptions(signed: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))]),
                  const SizedBox(height: Space.s2),
                  Obx(() => Wrap(spacing: Space.s2, children: [for (final (code, label) in _reasons) ChoiceChip(key: Key('stockReason_$code'), label: Text(label), selected: c.stockReason.value == code, onSelected: (_) => c.stockReason.value = code)])),
                  const SizedBox(height: Space.s2),
                  AppTextField(key: const Key('catalogStockNote'), label: 'Note (optional)', controller: c.stockNote),
                  const SizedBox(height: Space.s3),
                  Obx(() => AppButton(key: const Key('catalogAdjust'), label: 'Apply stock change', variant: AppButtonVariant.secondary, loading: c.saving.value, onPressed: c.saving.value ? null : c.adjustStock)),
                ],
                Obx(() => c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.error.value!, key: const Key('catalogError'), style: t.body.copyWith(color: p.danger)))),
                Obx(() => c.info.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.info.value!, key: const Key('catalogInfo'), style: t.body.copyWith(color: p.successFg)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

