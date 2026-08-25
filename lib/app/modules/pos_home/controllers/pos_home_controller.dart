import 'dart:async';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── POS theme colours (shared across the POS module) ─────────────────────────
const kPosBg = Color(0xFF1A1A1A);
const kPosSurface = Color(0xFF252525);
const kPosBorder = Color(0xFF333333);
const kPosSubText = Color(0xFF888888);
const kPosText = Color(0xFFE8E8E8);
const kPosOrange = Color(0xFFd97757);
const kPosGreen = Color(0xFF4CAF50);
const kPosRed = Color(0xFFEF5350);

// ── Cart item (local only — not serialised) ───────────────────────────────────
class CartItem {
  final PosProductModel product;
  final PosProductVariant? variant;
  final RxInt quantity;

  CartItem({required this.product, this.variant, int qty = 1})
    : quantity = qty.obs;

  double get unitPrice => variant?.price ?? product.price;
  double get lineTotal => unitPrice * quantity.value;

  /// The key used to deduplicate in the cart.
  String get cartKey => variant != null
      ? '${product.productId}_${variant!.variantId}'
      : product.productId;
}

// ── Payment methods accepted by the backend ───────────────────────────────────
class PosPaymentMethod {
  static const cash = 'cash';
  static const card = 'card';
  static const other = 'other';

  static const List<String> all = [cash, card, other];

  static String label(String method) {
    switch (method) {
      case cash:
        return 'Cash';
      case card:
        return 'Card';
      case other:
        return 'Other';
      default:
        return method;
    }
  }
}

// ── Controller ────────────────────────────────────────────────────────────────
class PosHomeController extends GetxController {
  PosHomeController({
    PosRepository? posRepository,
    CategoryRepository? categoryRepository,
  }) : _posRepo = posRepository ?? PosRepository(),
       _categoryRepo = categoryRepository ?? CategoryRepository();

  final PosRepository _posRepo;
  final CategoryRepository _categoryRepo;

  // ── Session context (loaded from prefs) ───────────────────────────────────
  final RxString sessionId = ''.obs;
  final RxString registerId = ''.obs;
  final RxString shiftId = ''.obs;
  final RxString employeeId = ''.obs;
  final RxString storeId = ''.obs;

  // ── UI state ──────────────────────────────────────────────────────────────
  final RxBool isLoadingProducts = true.obs;
  final RxBool isChargingOrHolding = false.obs;
  final RxBool isScanningBarcode = false.obs;

  // ── Products ──────────────────────────────────────────────────────────────
  final RxList<PosProductModel> allProducts = <PosProductModel>[].obs;
  final RxString searchText = ''.obs;
  final RxString selectedCategoryId = 'All'.obs;
  final RxMap<String, String> _categoryNames = <String, String>{}.obs;
  Timer? _debounce;

  // ── Cart ──────────────────────────────────────────────────────────────────
  final RxList<CartItem> cartItems = <CartItem>[].obs;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController customerController = TextEditingController();
  final TextEditingController discountController = TextEditingController(
    text: '0',
  );
  final TextEditingController taxController = TextEditingController(text: '0');

  // ── Payment ───────────────────────────────────────────────────────────────
  final RxString selectedPayment = PosPaymentMethod.cash.obs;
  final List<String> paymentMethods = PosPaymentMethod.all;

  // ── Computed ──────────────────────────────────────────────────────────────
  /// Display labels for the category filter row: `'All'` plus every
  /// categoryId present in the loaded products, resolved to a friendly name
  /// where possible (falls back to the raw id if not resolved yet).
  List<String> get categories {
    final ids =
        allProducts
            .map((p) => p.categoryId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...ids];
  }

  String categoryLabel(String categoryId) =>
      categoryId == 'All' ? 'All' : (_categoryNames[categoryId] ?? categoryId);

  List<PosProductModel> get filteredProducts {
    return allProducts.where((p) {
      final matchCat =
          selectedCategoryId.value == 'All' ||
          p.categoryId == selectedCategoryId.value;
      final q = searchText.value.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
      return matchCat && matchSearch;
    }).toList();
  }

  double get _discountAmount => double.tryParse(discountController.text) ?? 0.0;
  double get _taxRate => (double.tryParse(taxController.text) ?? 0.0) / 100.0;

  double get subtotal => cartItems.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get discountValue => _discountAmount;
  double get taxValue => (subtotal - _discountAmount) * _taxRate;
  double get total => subtotal - _discountAmount + taxValue;

  int get itemCount => cartItems.fold(0, (sum, i) => sum + i.quantity.value);
  bool get hasItems => cartItems.isNotEmpty;

  int cartQtyFor(PosProductModel p, [PosProductVariant? v]) {
    final key = v != null ? '${p.productId}_${v.variantId}' : p.productId;
    return cartItems
            .firstWhereOrNull((c) => c.cartKey == key)
            ?.quantity
            .value ??
        0;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => _loadProducts());
    _loadCategoryNames();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    searchController.dispose();
    noteController.dispose();
    customerController.dispose();
    discountController.dispose();
    taxController.dispose();
    super.onClose();
  }

  // ── Load session context from prefs ───────────────────────────────────────
  Future<void> _loadContext() async {
    sessionId.value = await AppPreferences.getPosSessionId() ?? '';
    registerId.value = await AppPreferences.getPosRegisterId() ?? '';
    shiftId.value = await AppPreferences.getPosShiftId() ?? '';
    employeeId.value = await AppPreferences.getPosEmployeeId() ?? '';
    storeId.value = await AppPreferences.getStoreId() ?? '';
  }

  // ── Products ──────────────────────────────────────────────────────────────
  /// A generous single page is fine for the in-store Quick Sale grid — a
  /// physical store's catalog rarely exceeds this, and search narrows it
  /// further. See getSales/getSessionHistory for proper cursor pagination
  /// used elsewhere in the module.
  static const _productPageLimit = 200;

  Future<void> _loadProducts() async {
    if (storeId.value.isEmpty) return;
    isLoadingProducts.value = true;
    try {
      final result = await _posRepo.getProducts(
        storeId.value,
        limit: _productPageLimit,
      );
      allProducts.assignAll(result.items);
    } finally {
      isLoadingProducts.value = false;
    }
  }

  Future<void> _loadCategoryNames() async {
    try {
      final categories = await _categoryRepo.getCategories();
      if (categories == null) return;
      final map = <String, String>{};
      void flatten(List<CategoryModel> nodes) {
        for (final c in nodes) {
          map[c.id] = c.name;
          if (c.children.isNotEmpty) flatten(c.children);
        }
      }

      flatten(categories);
      _categoryNames.assignAll(map);
    } catch (_) {
      // Non-critical — category chips fall back to raw ids.
    }
  }

  void onSearchChanged(String v) {
    searchText.value = v;
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      _loadProducts();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (storeId.value.isEmpty) return;
      final results = await _posRepo.searchProducts(
        storeId: storeId.value,
        q: v.trim(),
      );
      allProducts.assignAll(results);
    });
  }

  // ── Cart actions ──────────────────────────────────────────────────────────
  void addToCart(PosProductModel product, [PosProductVariant? variant]) {
    if (!product.inStock) return;
    if (product.hasMultipleVariants && variant == null) {
      _showVariantSheet(product);
      return;
    }
    variant ??= product.defaultVariant;
    if (variant == null) return;
    final key = '${product.productId}_${variant.variantId}';
    final idx = cartItems.indexWhere((c) => c.cartKey == key);
    if (idx >= 0) {
      cartItems[idx].quantity.value++;
    } else {
      cartItems.add(CartItem(product: product, variant: variant));
    }
    cartItems.refresh();
  }

  void removeFromCart(CartItem item) => cartItems.remove(item);

  void increment(CartItem item) {
    item.quantity.value++;
    cartItems.refresh();
  }

  void decrement(CartItem item) {
    if (item.quantity.value <= 1) {
      cartItems.remove(item);
    } else {
      item.quantity.value--;
      cartItems.refresh();
    }
  }

  void clearSale() {
    cartItems.clear();
    noteController.clear();
    customerController.clear();
    discountController.text = '0';
    taxController.text = '0';
  }

  void selectPayment(String method) => selectedPayment.value = method;
  void selectCategory(String categoryId) =>
      selectedCategoryId.value = categoryId;
  Future<void> retryLoadProducts() => _loadProducts();

  // ── Variant picker ────────────────────────────────────────────────────────
  void _showVariantSheet(PosProductModel product) {
    Get.bottomSheet(
      _VariantPickerSheet(product: product, controller: this),
      backgroundColor: kPosSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  // ── Charge (complete sale) ────────────────────────────────────────────────
  Future<void> completeSale() async {
    if (!hasItems) return;
    if (!_hasValidSession()) return;
    isChargingOrHolding.value = true;
    try {
      final result = await _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discount: _discountAmount,
        tax: taxValue,
        paymentMethod: selectedPayment.value,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        notes: noteController.text.trim(),
        status: 'completed',
        idempotencyKey: _newIdempotencyKey(),
      );
      if (!result.success) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }
      clearSale();
      Get.back(); // close cart sheet
      CustomAppSnackbar.success('Sale completed!');
    } finally {
      isChargingOrHolding.value = false;
    }
  }

  // ── Hold sale ─────────────────────────────────────────────────────────────
  Future<void> holdSale() async {
    if (!hasItems) return;
    if (!_hasValidSession()) return;
    isChargingOrHolding.value = true;
    try {
      final result = await _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discount: _discountAmount,
        tax: taxValue,
        paymentMethod: selectedPayment.value,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        notes: noteController.text.trim(),
        status: 'held',
        idempotencyKey: _newIdempotencyKey(),
      );
      if (!result.success) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }
      clearSale();
      Get.back();
      CustomAppSnackbar.success('Sale held.');
    } finally {
      isChargingOrHolding.value = false;
    }
  }

  String _newIdempotencyKey() =>
      '${employeeId.value}-${DateTime.now().microsecondsSinceEpoch}';

  // ── Held sales ────────────────────────────────────────────────────────────
  void openHeldSales() => Get.toNamed(Routes.posHeldSales);

  // ── Barcode scan → add straight to cart ──────────────────────────────────
  Future<void> addProductByBarcode(String barcode) async {
    if (storeId.value.isEmpty || barcode.trim().isEmpty) return;
    isScanningBarcode.value = true;
    try {
      final product = await _posRepo.getProductByBarcode(
        storeId: storeId.value,
        barcode: barcode.trim(),
      );
      if (product == null) {
        CustomAppSnackbar.error('No product found for that barcode.');
        return;
      }
      addToCart(product, product.defaultVariant);
    } finally {
      isScanningBarcode.value = false;
    }
  }

  // ── Resume a held sale into the cart ─────────────────────────────────────
  void resumeHeldSale(PosSaleModel sale) {
    clearSale();
    for (final item in sale.items) {
      final product = allProducts.firstWhereOrNull(
        (p) => p.productId == item.productId,
      );
      if (product == null) continue;
      final variant = product.variantById(item.variantId);
      cartItems.add(
        CartItem(product: product, variant: variant, qty: item.qty),
      );
    }
    cartItems.refresh();
    customerController.text = sale.customerName == 'Walk-in'
        ? ''
        : sale.customerName;
    noteController.text = sale.notes;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _buildItems() {
    return cartItems
        .map(
          (c) => {
            'productId': c.product.productId,
            if (c.variant != null) 'variantId': c.variant!.variantId,
            'qty': c.quantity.value,
          },
        )
        .toList();
  }

  bool _hasValidSession() {
    if (sessionId.value.isEmpty) {
      CustomAppSnackbar.error(
        'No active session. Please open a register first.',
      );
      return false;
    }
    return true;
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('stock') || lower.contains('insufficient')) {
      return 'One or more items are out of stock.';
    }
    if (lower.contains('held') && lower.contains('open')) {
      return 'Cannot close register: there are held sales pending.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ── Variant picker bottom sheet ───────────────────────────────────────────────
class _VariantPickerSheet extends StatelessWidget {
  final PosProductModel product;
  final PosHomeController controller;

  const _VariantPickerSheet({required this.product, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kPosBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          CustomText(
            text: 'Select Variant — ${product.name}',
            color: kPosText,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          const SizedBox(height: 12),
          ...product.variants.map(
            (v) => GestureDetector(
              onTap: v.stock > 0
                  ? () {
                      controller.addToCart(product, v);
                      Get.back();
                    }
                  : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: kPosBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kPosBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomText(
                            text: v.label,
                            color: v.stock > 0 ? kPosText : kPosSubText,
                            fontWeight: FontWeight.w600,
                          ),
                          CustomText(
                            text: v.stock > 0
                                ? '${v.stock} in stock'
                                : 'Out of stock',
                            color: v.stock > 0 ? kPosSubText : kPosRed,
                            fontSize: 12,
                          ),
                        ],
                      ),
                    ),
                    CustomText(
                      text: '\$${v.price.toStringAsFixed(2)}',
                      color: kPosOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
