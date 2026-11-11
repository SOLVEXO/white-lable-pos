import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// G4.5 products & pricing: the entry to the catalog-admin screens. Managers by default (the permission matrix); the server refuses the rest
/// and each screen says so.
class CatalogAdminHubView extends StatelessWidget {
  const CatalogAdminHubView({super.key});

  @override
  Widget build(BuildContext context) => HubScaffold(
    title: 'Products & pricing',
    listKey: const Key('catalogHub'),
    children: [
      const ReportInfo('Changes here need an internet connection and apply on every till.'),
      HubSection('Products', [
        HubRow(
          key: const Key('hubNewProduct'),
          icon: Icons.add_box_outlined,
          title: 'New product',
          subtitle: 'Name, category, variants, prices and starting stock',
          onTap: () => Get.toNamed(Routes.posCatalogNewProduct),
        ),
        HubRow(key: const Key('hubCategories'), icon: Icons.category_outlined, title: 'Categories', subtitle: 'Add, rename and delete', onTap: () => Get.toNamed(Routes.posCatalogCategories)),
        HubRow(
          key: const Key('hubImport'),
          icon: Icons.upload_file_rounded,
          title: 'Import from CSV',
          subtitle: 'Products or categories, same columns as the dashboard',
          onTap: () => Get.toNamed(Routes.posCatalogImport),
        ),
      ]),
      HubSection('Pricing', [
        HubRow(
          key: const Key('hubModifiers'),
          icon: Icons.tune_rounded,
          title: 'Modifier groups',
          subtitle: 'Options sold with a product, like size or extras',
          onTap: () => Get.toNamed(Routes.posModifierGroups),
        ),
        HubRow(
          key: const Key('hubPriceBooks'),
          icon: Icons.sell_outlined,
          title: 'Price books',
          subtitle: 'Other prices for some items, for a time or a customer',
          onTap: () => Get.toNamed(Routes.posPriceBooks),
        ),
      ]),
    ],
  );
}
