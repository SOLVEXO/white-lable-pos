import 'dart:io';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_page_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// G5.2 — the product page at the till: photos, details, variants (price, cost when allowed, stock), stock by location; managers edit the details,
/// a variant's SKU / cost / reorder point and the photos. Every rule is the server's (matrix, "hide costs", file type and size); this shows its answers.
class ProductPageController extends GetxController {
  ProductPageController({required this.productId, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String productId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<ProductPage> page = Rxn<ProductPage>();
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString notice = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<String> get _sid => invStoreId(_storeIdOverride);

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    final p = await _repo.getProductPage(await _sid, productId);
    page.value = p ?? page.value;
    if (p == null) error.value = productErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this product. Check the connection and try again.');
    loading.value = false;
  }

  Future<bool> _apply(Future<({bool success, String? code, String? message, ProductPage? data})> Function(String sid) call, String ok) async {
    if (busy.value) return false;
    busy.value = true;
    error.value = null;
    notice.value = null;
    try {
      final r = await call(await _sid);
      if (r.success && r.data != null) {
        page.value = r.data;
        notice.value = ok;
        return true;
      }
      error.value = productErrorMessage(r.code, fallback: r.message ?? 'Could not save. Try again.');
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> saveDetails({String? name, String? description, String? status}) => _apply(
    (sid) => _repo.updateProductDetails(sid, productId, {'name': ?name, 'description': ?description, 'status': ?status}),
    'Saved.',
  );

  /// [costMinor]: null leaves cost unchanged; use [clearCost] to remove it.
  Future<bool> saveVariant(String variantId, {String? sku, int? costMinor, bool clearCost = false, int? reorderPoint, bool clearReorder = false}) => _apply(
    (sid) => _repo.updateProductVariant(sid, productId, variantId, {
      'sku': ?sku,
      if (costMinor != null || clearCost) 'costMinor': clearCost ? null : costMinor,
      if (reorderPoint != null || clearReorder) 'reorderPoint': clearReorder ? null : reorderPoint,
    }),
    'Saved.',
  );

  Future<bool> addPhoto(File f) => _apply((sid) => _repo.uploadProductImage(sid, productId, f), 'Photo added.');
  Future<bool> removePhoto(String url) => _apply((sid) => _repo.removeProductImage(sid, productId, url), 'Photo removed.');
  Future<bool> makePrimary(String url) => _apply((sid) => _repo.makeProductImagePrimary(sid, productId, url), 'Main photo changed.');
}

/// The server's codes in words.
String productErrorMessage(String? code, {required String fallback}) => switch (code) {
  'POS_ACTION_FORBIDDEN' || 'POS_OWNER_REQUIRED' => 'Only a manager or the owner can change products.',
  'COSTS_HIDDEN' => 'The owner hides costs from managers — only the owner can change a cost.',
  'SKU_TAKEN' => 'That SKU is already used by another product.',
  'NAME_REQUIRED' => 'A product needs a name.',
  'FILE_TYPE' => 'Only JPEG, PNG or WebP photos can be added.',
  'FILE_TOO_LARGE' => 'That photo is larger than 8 MB.',
  'TOO_MANY_IMAGES' => 'A product can have at most 10 photos.',
  'IMAGE_NOT_FOUND' => 'That photo is no longer on this product.',
  'PRODUCT_NOT_FOUND' => 'This product was not found.',
  'INVALID_AMOUNT' => 'Enter a valid amount.',
  _ => fallback,
};
