import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';

/// Find an item to edit (search by name / SKU). The edit itself is [PosCatalogItemController].
class PosCatalogController extends GetxController {
  PosCatalogController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxList<PosProductModel> results = <PosProductModel>[].obs;
  final RxBool loading = false.obs;
  final RxBool searched = false.obs;
  Timer? _debounce;
  String storeId = '';

  Future<String> _store() async => storeId = _storeIdOverride ?? (await AppPreferences.getStoreId()) ?? '';

  @override
  void onInit() {
    super.onInit();
    search('');
  }

  void onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => search(q));
  }

  Future<void> search(String q) async {
    loading.value = true;
    try {
      final sid = await _store();
      final list = q.trim().isEmpty ? (await _repo.getProducts(sid, limit: 40)).items : await _repo.searchProducts(storeId: sid, q: q.trim());
      results.assignAll(list);
      searched.value = true;
    } finally {
      loading.value = false;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

/// One item's edit: price, barcode, PCT/HS code, category, and stock (as a movement). A MANAGER's PIN session is required: when the person
/// signed in is not a manager, a manager approves each save on the spot. The server audits before/after and enforces per-store barcode
/// uniqueness and currency-exact prices.
class PosCatalogItemController extends GetxController {
  PosCatalogItemController({required this.product, required this.variant, PosRepository? repository, CategoryRepository? categories, String? storeId, bool? isManager})
      : _repo = repository ?? PosRepository(),
        _categories = categories ?? CategoryRepository(),
        _storeIdOverride = storeId,
        _isManagerOverride = isManager;

  final PosProductModel product;
  final PosProductVariant variant;
  final PosRepository _repo;
  final CategoryRepository _categories;
  final String? _storeIdOverride;
  final bool? _isManagerOverride;

  late final price = TextEditingController(text: _fmt(variant.price));
  late final barcode = TextEditingController(text: variant.barcode ?? '');
  late final hsCode = TextEditingController(text: variant.hsCode ?? '');
  final stockDelta = TextEditingController();
  final stockNote = TextEditingController();
  final RxString stockReason = 'correction'.obs;
  final RxnString categoryId = RxnString();
  final RxList<({String id, String name})> categories = <({String id, String name})>[].obs;

  final RxBool saving = false.obs;
  final RxnString error = RxnString();
  final RxnString info = RxnString();
  final RxInt stock = 0.obs;
  final RxBool isManager = false.obs;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void onInit() {
    super.onInit();
    stock.value = variant.stock;
    categoryId.value = product.categoryId.isEmpty ? null : product.categoryId;
    if (_isManagerOverride != null) {
      isManager.value = _isManagerOverride;
    } else {
      PosRole.isCurrentEmployeeManager().then((v) => isManager.value = v);
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final tree = await _categories.getCategories();
      final out = <({String id, String name})>[];
      void walk(List<CategoryModel> nodes) {
        for (final c in nodes) {
          out.add((id: c.id, name: c.name));
          if (c.children.isNotEmpty) walk(c.children);
        }
      }
      walk(tree ?? const []);
      categories.assignAll(out);
    } catch (_) {}
  }

  @override
  void onClose() {
    price.dispose();
    barcode.dispose();
    hsCode.dispose();
    stockDelta.dispose();
    stockNote.dispose();
    super.onClose();
  }

  Future<String> _store() async => _storeIdOverride ?? (await AppPreferences.getStoreId()) ?? '';

  Future<String?> _approval() async {
    if (isManager.value) return null;
    return ManagerApproval.request(reason: 'Changing the catalog needs a manager.', repository: _repo);
  }

  Map<String, dynamic> _changes() {
    final m = <String, dynamic>{};
    final p = double.tryParse(price.text.trim());
    if (p != null && p != variant.price) m['price'] = p;
    final b = barcode.text.trim();
    if (b != (variant.barcode ?? '')) m['barcode'] = b.isEmpty ? null : b;
    final h = hsCode.text.trim();
    if (h != (variant.hsCode ?? '')) m['hsCode'] = h.isEmpty ? null : h;
    if (categoryId.value != null && categoryId.value != product.categoryId) m['categoryId'] = categoryId.value;
    return m;
  }

  bool get hasChanges => _changes().isNotEmpty;

  /// Saves what changed. Guarded against a double tap. Returns true on success.
  Future<bool> save() async {
    if (saving.value) return false;
    error.value = null;
    info.value = null;
    final changes = _changes();
    if (price.text.trim().isNotEmpty && double.tryParse(price.text.trim()) == null) {
      error.value = 'Enter a valid price.';
      return false;
    }
    if (changes.isEmpty) {
      info.value = 'Nothing to save.';
      return false;
    }
    saving.value = true;
    try {
      final token = await _approval();
      if (!isManager.value && token == null) return false; // approval cancelled
      final r = await _repo.updateCatalogVariant(await _store(), variant.variantId, changes, approverToken: token);
      if (!r.success) {
        error.value = r.message;
        return false;
      }
      info.value = 'Saved.';
      return true;
    } finally {
      saving.value = false;
    }
  }

  /// Stock is a MOVEMENT (+ / − units with a reason), never an overwrite.
  Future<bool> adjustStock() async {
    if (saving.value) return false;
    error.value = null;
    info.value = null;
    final delta = int.tryParse(stockDelta.text.trim());
    if (delta == null || delta == 0) {
      error.value = 'Enter how many units to add (+) or remove (−).';
      return false;
    }
    saving.value = true;
    try {
      final token = await _approval();
      if (!isManager.value && token == null) return false;
      final r = await _repo.adjustCatalogStock(await _store(), variant.variantId, delta: delta, reason: stockReason.value, note: stockNote.text, approverToken: token);
      if (!r.success) {
        error.value = r.message;
        return false;
      }
      final after = (r.data?['after'] as num?)?.toInt();
      if (after != null) stock.value = after;
      stockDelta.clear();
      info.value = 'Stock updated.';
      return true;
    } finally {
      saving.value = false;
    }
  }
}
