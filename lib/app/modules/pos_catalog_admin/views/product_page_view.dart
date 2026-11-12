import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/app_image_picker.dart';
import 'package:solvexo_pos/app/components/costs_hidden_note.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart' show invMoney;
import 'package:solvexo_pos/app/data/models/pos/pos_product_page_models.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/product_page_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// G5.2 — the product page at the till. Photos come as small thumbnails, cached on the device for offline viewing (cached_network_image).
class ProductPageView extends StatelessWidget {
  ProductPageView({super.key, required String productId, ProductPageController? controller})
    : c = controller ?? Get.put(ProductPageController(productId: productId), tag: 'product_$productId');
  final ProductPageController c;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = context.type;
    return Obx(() {
      final p = c.page.value;
      return HubScaffold(
        title: p?.name ?? 'Product',
        listKey: const Key('productPage'),
        children: [
          if (c.loading.value && p == null) const Padding(padding: EdgeInsets.all(Space.s6), child: Center(child: CircularProgressIndicator())),
          if (c.error.value != null) Padding(padding: const EdgeInsets.symmetric(vertical: Space.s2), child: Text(c.error.value!, key: const Key('productError'), style: t.body.copyWith(color: pal.danger))),
          if (c.notice.value != null) Padding(padding: const EdgeInsets.symmetric(vertical: Space.s2), child: Text(c.notice.value!, key: const Key('productNotice'), style: t.body.copyWith(color: pal.successFg))),
          if (p != null) ...[
            _Photos(c: c, page: p),
            const SizedBox(height: Space.s3),
            Row(
              children: [
                Expanded(child: Text(p.name, style: t.title.copyWith(color: pal.textPrimary))),
                StatusBadge(p.status == 'draft' ? 'Draft' : 'Active', tone: p.status == 'draft' ? StatusTone.neutral : StatusTone.success),
              ],
            ),
            if (p.categoryName != null) Text(p.categoryName!, style: t.caption.copyWith(color: pal.textSecondary)),
            if (p.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(p.description, style: t.body.copyWith(color: pal.textSecondary))),
            if (p.canEdit) Padding(padding: const EdgeInsets.only(top: Space.s3), child: AppButton(key: const Key('productEditDetails'), label: 'Edit details', icon: Icons.edit_outlined, variant: AppButtonVariant.secondary, onPressed: () => _editDetails(p))),
            if (p.costsHidden) const Padding(padding: EdgeInsets.only(top: Space.s3), child: CostsHiddenNote(what: 'Costs')),
            HubSection('Variants', [
              for (final v in p.variants)
                ReportRow(
                  key: Key('productVariant_${v.id}'),
                  title: v.label,
                  subtitle: [if (v.sku != null) v.sku!, if (v.barcode != null) v.barcode!, if (v.status == 'archived') 'archived'].join(' · '),
                  value: p.cur == null ? '' : invMoney(v.priceMinor, p.cur!),
                  detail: [v.unlimitedStock ? 'unlimited' : '${v.stock} in stock', if (v.costMinor != null && p.cur != null) 'cost ${invMoney(v.costMinor!, p.cur!)}', if (v.reorderPoint != null) 'reorder at ${v.reorderPoint}'].join(' · '),
                  onTap: p.canEdit ? () => _editVariant(p, v) : null,
                ),
            ]),
            if (p.stockByLocation.isNotEmpty)
              HubSection('Stock by location', [for (final l in p.stockByLocation) ReportRow(title: l.name, value: '${l.stock}')]),
          ],
        ],
      );
    });
  }

  Future<void> _editDetails(ProductPage p) async {
    await AppBottomSheet.showGet<void>(_DetailsSheet(c: c, page: p), title: 'Edit details');
  }

  Future<void> _editVariant(ProductPage p, ProductPageVariant v) async {
    await AppBottomSheet.showGet<void>(_VariantSheet(c: c, page: p, v: v), title: v.label);
  }
}

class _Photos extends StatelessWidget {
  const _Photos({required this.c, required this.page});
  final ProductPageController c;
  final ProductPage page;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    return SizedBox(
      height: 132,
      child: ListView(
        key: const Key('productPhotos'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, img) in page.images.indexed)
            Padding(
              padding: const EdgeInsets.only(right: Space.s2),
              child: GestureDetector(
                key: Key('productPhoto_$i'),
                onLongPress: page.canEdit ? () => _photoActions(context, img.url, i == 0) : null,
                child: ClipRRect(
                  borderRadius: Radii.rMd,
                  child: Stack(
                    children: [
                      CachedNetworkImage(imageUrl: img.thumbUrl, width: 132, height: 132, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(width: 132, height: 132, color: pal.fill, child: Icon(Icons.image_not_supported_outlined, color: pal.textMuted))),
                      if (i == 0) Positioned(left: 6, top: 6, child: StatusBadge('Main', tone: StatusTone.accent)),
                    ],
                  ),
                ),
              ),
            ),
          if (page.images.isEmpty && !page.canEdit) Container(width: 132, height: 132, decoration: BoxDecoration(color: pal.fill, borderRadius: Radii.rMd), child: Icon(Icons.image_outlined, color: pal.textMuted, size: 40)),
          if (page.canEdit && page.images.length < 10)
            InkWell(
              key: const Key('productAddPhoto'),
              borderRadius: Radii.rMd,
              onTap: () => AppImagePicker.show(onPicked: (f) => c.addPhoto(f), title: 'Product photo'),
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(color: pal.surface, borderRadius: Radii.rMd, border: Border.all(color: pal.border)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo_outlined, color: pal.accentFg), const SizedBox(height: Space.s1), Text('Add photo', style: context.type.caption.copyWith(color: pal.textSecondary))]),
              ),
            ),
        ],
      ),
    );
  }

  void _photoActions(BuildContext context, String url, bool isMain) {
    AppBottomSheet.showGet<void>(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMain) ListTile(key: const Key('photoMakeMain'), leading: const Icon(Icons.star_outline_rounded), title: const Text('Make main photo'), onTap: () { Get.back<void>(); c.makePrimary(url); }),
          ListTile(key: const Key('photoRemove'), leading: Icon(Icons.delete_outline_rounded, color: context.palette.danger), title: const Text('Remove photo'), onTap: () { Get.back<void>(); c.removePhoto(url); }),
        ],
      ),
      title: 'Photo',
    );
  }
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.c, required this.page});
  final ProductPageController c;
  final ProductPage page;
  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final _name = TextEditingController(text: widget.page.name);
  late final _desc = TextEditingController(text: widget.page.description);
  late bool _active = widget.page.status != 'draft';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(key: const Key('productName'), label: 'Name', controller: _name),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('productDescription'), label: 'Description (optional)', controller: _desc, maxLines: 4),
        SwitchListTile(key: const Key('productActive'), contentPadding: EdgeInsets.zero, title: const Text('Active (sold at the till)'), value: _active, onChanged: (v) => setState(() => _active = v)),
        const SizedBox(height: Space.s2),
        Obx(() => AppButton(
          key: const Key('productSaveDetails'),
          label: 'Save',
          loading: widget.c.busy.value,
          onPressed: () async {
            final ok = await widget.c.saveDetails(
              name: _name.text.trim() == widget.page.name ? null : _name.text.trim(),
              description: _desc.text.trim() == widget.page.description ? null : _desc.text.trim(),
              status: (_active ? 'active' : 'draft') == widget.page.status ? null : (_active ? 'active' : 'draft'),
            );
            if (ok) Get.back<void>();
          },
        )),
        Obx(() => widget.c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(widget.c.error.value!, style: context.type.body.copyWith(color: context.palette.danger)))),
      ],
    );
  }
}

class _VariantSheet extends StatefulWidget {
  const _VariantSheet({required this.c, required this.page, required this.v});
  final ProductPageController c;
  final ProductPage page;
  final ProductPageVariant v;
  @override
  State<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends State<_VariantSheet> {
  late final _sku = TextEditingController(text: widget.v.sku ?? '');
  late final _cost = TextEditingController(text: widget.v.costMinor == null ? '' : Money.plain(Money.fromMinor(widget.v.costMinor!)));
  late final _reorder = TextEditingController(text: widget.v.reorderPoint?.toString() ?? '');

  @override
  void dispose() {
    _sku.dispose();
    _cost.dispose();
    _reorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCost = !widget.page.costsHidden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(key: const Key('variantSku'), label: 'SKU', controller: _sku, mono: true),
        if (showCost) ...[
          const SizedBox(height: Space.s3),
          AppTextField(key: const Key('variantCost'), label: 'Cost (per unit)', controller: _cost, mono: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))]),
        ],
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('variantReorder'), label: 'Reorder when stock is at or below (optional)', controller: _reorder, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
        const SizedBox(height: Space.s1),
        Text('Price and barcode are changed on the item\'s price screen (with its approval rules).', style: context.type.caption.copyWith(color: context.palette.textMuted)),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(
          key: const Key('variantSave'),
          label: 'Save',
          loading: widget.c.busy.value,
          onPressed: () async {
            final sku = _sku.text.trim();
            final costText = _cost.text.trim();
            final reorderText = _reorder.text.trim();
            final costMinor = costText.isEmpty ? null : Money.toMinor(double.tryParse(costText) ?? -1);
            final ok = await widget.c.saveVariant(
              widget.v.id,
              sku: sku.isEmpty || sku == widget.v.sku ? null : sku,
              costMinor: showCost && costMinor != null && costMinor != widget.v.costMinor ? costMinor : null,
              clearCost: showCost && costText.isEmpty && widget.v.costMinor != null,
              reorderPoint: reorderText.isEmpty || int.tryParse(reorderText) == widget.v.reorderPoint ? null : int.tryParse(reorderText),
              clearReorder: reorderText.isEmpty && widget.v.reorderPoint != null,
            );
            if (ok) Get.back<void>();
          },
        )),
        Obx(() => widget.c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(widget.c.error.value!, style: context.type.body.copyWith(color: context.palette.danger)))),
      ],
    );
  }
}
