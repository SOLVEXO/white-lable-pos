// G5.2: the product page at the till — photos, details, variants; managers edit details / a variant / photos; cost respects "hide costs".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_page_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/product_page_controller.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/product_page_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class _Repo extends Mock implements PosRepository {}

ProductPage page({bool canEdit = true, bool hidden = false, String name = 'Green tea 100g'}) => ProductPage.fromJson({
  'currency': 'PKR', 'currencyExponent': 2, 'canEdit': canEdit, if (hidden) 'costsHidden': true,
  'product': {
    'id': 'p1', 'name': name, 'description': 'Loose leaf', 'status': 'active', 'categoryName': 'Tea',
    'images': [],
    'variants': [
      {'id': 'v1', 'sku': 'TEA-100', 'options': [{'name': 'Size', 'value': '100g'}], 'priceMinor': 45000, if (!hidden) 'costMinor': 30000, 'stock': 12, 'reorderPoint': 4},
    ],
    'stockByLocation': [{'locationId': 'l1', 'name': 'Tariq Road', 'stock': 8}],
  },
});

void main() {
  late _Repo repo;
  setUp(() {
    Get.testMode = true;
    Get.reset();
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Money.configure(currency: 'PKR', exponent: 2);
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
  });
  Future<void> pump(WidgetTester t, Widget w) async {
    await t.binding.setSurfaceSize(const Size(430, 1400));
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: w)));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows details, the variant with price / cost / stock and stock by location; edit details sends only what changed', (t) async {
    when(() => repo.getProductPage('st1', 'p1')).thenAnswer((_) async => page());
    Map<String, dynamic>? sent;
    when(() => repo.updateProductDetails('st1', 'p1', any())).thenAnswer((i) async {
      sent = i.positionalArguments[2] as Map<String, dynamic>;
      return (success: true, code: null, message: null, data: page(name: 'Green tea 250g'));
    });
    final c = ProductPageController(productId: 'p1', repository: repo, storeId: 'st1');
    Get.put(c);
    await pump(t, ProductPageView(productId: 'p1', controller: c));
    expect(find.text('Green tea 100g'), findsWidgets);
    expect(find.textContaining('cost'), findsOneWidget);
    expect(find.text('Tariq Road'), findsOneWidget);
    expect(find.byKey(const Key('productAddPhoto')), findsOneWidget);
    expect(await c.saveDetails(name: 'Green tea 250g'), isTrue);
    expect(sent, {'name': 'Green tea 250g'});
    expect(c.page.value!.name, 'Green tea 250g');
  });

  testWidgets('a cashier (no edit) sees no edit controls; costs hidden → a notice and no cost', (t) async {
    when(() => repo.getProductPage('st1', 'p1')).thenAnswer((_) async => page(canEdit: false, hidden: true));
    final c = ProductPageController(productId: 'p1', repository: repo, storeId: 'st1');
    Get.put(c);
    await pump(t, ProductPageView(productId: 'p1', controller: c));
    expect(find.byKey(const Key('productEditDetails')), findsNothing);
    expect(find.byKey(const Key('productAddPhoto')), findsNothing);
    expect(find.textContaining('cost '), findsNothing);
  });

  test('the server\'s refusals in words (COSTS_HIDDEN, SKU_TAKEN, FILE_TYPE)', () async {
    when(() => repo.updateProductVariant('st1', 'p1', 'v1', any())).thenAnswer((_) async => (success: false, code: 'COSTS_HIDDEN', message: 'x', data: null));
    final c = ProductPageController(productId: 'p1', repository: repo, storeId: 'st1');
    expect(await c.saveVariant('v1', costMinor: 100), isFalse);
    expect(c.error.value, contains('only the owner'));
    expect(productErrorMessage('SKU_TAKEN', fallback: ''), contains('already used'));
    expect(productErrorMessage('FILE_TYPE', fallback: ''), contains('JPEG'));
  });
}
