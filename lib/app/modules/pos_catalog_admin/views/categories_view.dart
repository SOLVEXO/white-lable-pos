import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.5 categories: each with how many products it holds; add, rename, delete (the server refuses one that still has products, in words).
class CatalogCategoriesView extends StatefulWidget {
  const CatalogCategoriesView({super.key, this.controller});
  final CatalogCategoriesController? controller;
  @override
  State<CatalogCategoriesView> createState() => _CatalogCategoriesViewState();
}

class _CatalogCategoriesViewState extends State<CatalogCategoriesView> with CatOwnedController<CatalogCategoriesView, CatalogCategoriesController> {
  @override
  CatalogCategoriesController? get given => widget.controller;
  @override
  CatalogCategoriesController create() => CatalogCategoriesController();

  Future<void> _add() async {
    final name = await CatTextSheet.open(title: 'New category', label: 'Name', confirmLabel: 'Add');
    if (name != null && name.isNotEmpty) await c.create(name);
  }

  Future<void> _rename(CatalogCategory cat) async {
    final name = await CatTextSheet.open(title: 'Rename category', label: 'Name', initial: cat.name);
    if (name != null && name.isNotEmpty && name != cat.name) await c.rename(cat, name);
  }

  Future<void> _delete(CatalogCategory cat) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Delete "${cat.name}"?',
      message: cat.products > 0 ? 'It still has ${cat.products} product${cat.products == 1 ? '' : 's'}.' : null,
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await c.delete(cat);
  }

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Categories',
    actions: [Obx(() => c.hasData ? TextButton(key: const Key('catAdd'), onPressed: c.busy.value ? null : _add, child: const Text('Add')) : const SizedBox.shrink())],
    body: CatStateBody(
      c: c,
      subject: 'Categories',
      builder: (context) {
        final p = context.palette;
        final t = context.type;
        return [
          if (c.categories.isEmpty) const CatEmpty(icon: Icons.category_outlined, title: 'No categories yet', message: 'Add one with "Add".'),
          for (final cat in c.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('cat_${cat.id}'),
                radius: Radii.rMd,
                padding: const EdgeInsets.fromLTRB(Space.s3, Space.s1, Space.s1, Space.s1),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                          Text(
                            '${cat.products} product${cat.products == 1 ? '' : 's'}${cat.status == 'active' ? '' : ' · ${cat.status}'}',
                            key: Key('catCount_${cat.id}'),
                            style: t.caption.copyWith(color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(key: Key('catRename_${cat.id}'), tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: c.busy.value ? null : () => _rename(cat)),
                    IconButton(key: Key('catDelete_${cat.id}'), tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded), onPressed: c.busy.value ? null : () => _delete(cat)),
                  ],
                ),
              ),
            ),
        ];
      },
    ),
  );
}
