import 'dart:async';
import 'dart:math' as math;

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/hid_scan_detector.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_customer_picker_sheet.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';

// ── POS theme colours (shared across the POS module) ─────────────────────────
const kPosBg = AppColors.posThemeBg;
const kPosSurface = AppColors.posThemeSurface;
const kPosBorder = AppColors.posThemeBorder;
const kPosSubText = AppColors.posThemeSubText;
const kPosText = AppColors.posThemeText;
const kPosGreen = AppColors.posStatusGreen;
const kPosRed = AppColors.posStatusRed;

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
        // The backend only has cash|card|other — bank transfer and any
        // other non-card electronic payment are recorded as 'other' with an
        // optional reference captured in the sale's notes (see
        // PosHomeController._buildNotes).
        return 'Bank / Other';
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
  /// See PosRole.isCurrentEmployeeManager's doc comment — gates the
  /// discount field to match the backend's real, token-verified check.
  final RxBool isManager = false.obs;

  // ── Store settings (tax label/currency come from here) ─────────────────────
  final Rx<PosSettingsModel?> settings = Rx(null);
  final RxString currencySymbol = '\$'.obs;

  // ── Products ──────────────────────────────────────────────────────────────
  final RxList<PosProductModel> allProducts = <PosProductModel>[].obs;
  final RxString searchText = ''.obs;
  final RxString selectedCategoryId = 'All'.obs;
  final RxMap<String, String> _categoryNames = <String, String>{}.obs;
  final RxBool isLoadingMoreProducts = false.obs;
  final ScrollController productScrollController = ScrollController();
  Timer? _debounce;
  int _productPage = 1;
  bool _hasMoreProducts = true;
  bool get hasMoreProducts => _hasMoreProducts;

  // ── HID (keyboard-wedge) barcode scanning ───────────────────────────────
  late final HidScanDetector _hidScanDetector;

  // ── Cart ──────────────────────────────────────────────────────────────────
  final RxList<CartItem> cartItems = <CartItem>[].obs;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  final TextEditingController customerController = TextEditingController();
  /// Set when a real customer is attached via the picker sheet (see
  /// [openCustomerPicker]) — sent as `customerId` on the sale. Cleared
  /// whenever [customerController]'s text is edited afterward, so a stale
  /// id is never sent alongside a name that no longer matches it.
  final Rx<CustomerModel?> selectedCustomer = Rx(null);
  final TextEditingController discountController = TextEditingController(
    text: '0',
  );
  final TextEditingController taxController = TextEditingController(text: '0');
  final RxBool isPercentDiscount = false.obs;

  // ── Payment ───────────────────────────────────────────────────────────────
  final RxString selectedPayment = PosPaymentMethod.cash.obs;
  final List<String> paymentMethods = PosPaymentMethod.all;
  final TextEditingController tenderedController = TextEditingController();
  final TextEditingController paymentReferenceController = TextEditingController();

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
          p.sku.toLowerCase().contains(q) ||
          p.variants.any((v) => (v.barcode ?? '').toLowerCase().contains(q));
      return matchCat && matchSearch;
    }).toList();
  }

  double get _rawDiscountInput => double.tryParse(discountController.text) ?? 0.0;
  double get _taxRate => (double.tryParse(taxController.text) ?? 0.0) / 100.0;

  double get subtotal => cartItems.fold(0.0, (sum, i) => sum + i.lineTotal);

  /// Converts a percentage input to an absolute amount (the backend's
  /// `discount` field is always a flat number — see Phase 1 plan), then
  /// clamps so a discount can never exceed the subtotal and drive the total
  /// negative.
  double get discountValue {
    final amount = isPercentDiscount.value
        ? subtotal * (_rawDiscountInput / 100.0)
        : _rawDiscountInput;
    return amount.clamp(0.0, subtotal);
  }

  double get taxValue => ((subtotal - discountValue) * _taxRate).clamp(0.0, double.infinity);
  double get total => (subtotal - discountValue + taxValue).clamp(0.0, double.infinity);

  int get itemCount => cartItems.fold(0, (sum, i) => sum + i.quantity.value);
  bool get hasItems => cartItems.isNotEmpty;

  void toggleDiscountType() {
    isPercentDiscount.value = !isPercentDiscount.value;
    cartItems.refresh();
  }

  // ── Cash tendered / change ───────────────────────────────────────────────
  // Not sent to the backend (the sale schema has no tendered/change field) —
  // purely a cashier-facing convenience computed and shown at checkout time.
  double get tenderedAmount => double.tryParse(tenderedController.text) ?? 0.0;
  double get changeDue =>
      selectedPayment.value == PosPaymentMethod.cash ? math.max(0.0, tenderedAmount - total) : 0.0;
  bool get isCashUnderTendered =>
      selectedPayment.value == PosPaymentMethod.cash && hasItems && tenderedAmount < total;

  /// Mirrors the backend's real, token-verified discount gate (createSale/
  /// completeSale/editHeldSaleItems all reject discount>0 without a
  /// verified manager token) — client-side so a cashier gets a clear
  /// message instead of a 403 after filling out the whole cart.
  bool get isDiscountBlocked => discountValue > 0 && !isManager.value;

  bool get canCharge => hasItems && !isCashUnderTendered && !isDiscountBlocked;

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
    _loadContext().then((_) {
      _loadProducts();
      _loadSettings();
    });
    _loadCategoryNames();
    PosRole.isCurrentEmployeeManager().then((v) => isManager.value = v);

    productScrollController.addListener(() {
      if (productScrollController.position.pixels >=
          productScrollController.position.maxScrollExtent - 300) {
        loadMoreProducts();
      }
    });

    _hidScanDetector = HidScanDetector(
      isArmed: () =>
          Get.currentRoute == Routes.posHome &&
          !(Get.isDialogOpen ?? false) &&
          !(Get.isBottomSheetOpen ?? false) &&
          FocusManager.instance.primaryFocus?.context?.widget is! EditableText,
      onScan: (code) => addProductByBarcode(code),
    )..start();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _hidScanDetector.stop();
    productScrollController.dispose();
    searchController.dispose();
    noteController.dispose();
    customerController.dispose();
    discountController.dispose();
    taxController.dispose();
    tenderedController.dispose();
    paymentReferenceController.dispose();
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

  // ── Store settings (currency symbol) ────────────────────────────────────
  Future<void> _loadSettings() async {
    if (storeId.value.isEmpty) return;
    settings.value = await _posRepo.getPosSettings(storeId.value);
    final symbol = settings.value?.currencySymbol;
    if (symbol != null && symbol.trim().isNotEmpty) {
      currencySymbol.value = symbol;
    }
  }

  // ── Products ──────────────────────────────────────────────────────────────
  static const _productPageSize = 40;

  Future<void> _loadProducts() async {
    if (storeId.value.isEmpty) return;
    isLoadingProducts.value = true;
    _productPage = 1;
    try {
      final result = await _posRepo.getProducts(
        storeId.value,
        page: _productPage,
        limit: _productPageSize,
      );
      allProducts.assignAll(result.items);
      _hasMoreProducts = result.hasMore;
    } finally {
      isLoadingProducts.value = false;
    }
  }

  /// Loads the next page of the store's catalog — the Quick Sale grid used
  /// to fetch a single hardcoded 200-item page; this uses the same cursor
  /// pagination `getSales`/`getSessionHistory` already rely on. Only used
  /// while browsing (no active search text — a search already narrows the
  /// catalog via `searchProducts`, which returns its own unpaginated result).
  Future<void> loadMoreProducts() async {
    if (isLoadingMoreProducts.value || !_hasMoreProducts) return;
    if (searchText.value.trim().isNotEmpty) return;
    isLoadingMoreProducts.value = true;
    try {
      final result = await _posRepo.getProducts(
        storeId.value,
        page: _productPage + 1,
        limit: _productPageSize,
      );
      allProducts.addAll(result.items);
      _productPage++;
      _hasMoreProducts = result.hasMore;
    } finally {
      isLoadingMoreProducts.value = false;
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
    selectedCustomer.value = null;
    discountController.text = '0';
    taxController.text = '0';
    isPercentDiscount.value = false;
    tenderedController.clear();
    paymentReferenceController.clear();
    selectedPayment.value = PosPaymentMethod.cash;
  }

  /// Prepends the "Bank / Other" reference (if any) to the free-text notes
  /// sent to the backend — there's no dedicated payment-reference field on
  /// the sale schema, so this rides in `notes` instead of inventing one.
  String _buildNotes() {
    final base = noteController.text.trim();
    if (selectedPayment.value == PosPaymentMethod.other &&
        paymentReferenceController.text.trim().isNotEmpty) {
      final ref = 'Ref: ${paymentReferenceController.text.trim()}';
      return base.isEmpty ? ref : '$ref | $base';
    }
    return base;
  }

  // ── Customer picker ───────────────────────────────────────────────────────
  Future<void> openCustomerPicker() async {
    if (storeId.value.isEmpty) return;
    final picked = await Get.bottomSheet<CustomerModel>(
      PosCustomerPickerSheet(storeId: storeId.value),
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
    );
    if (picked != null) {
      selectedCustomer.value = picked;
      customerController.text = picked.name;
    }
  }

  /// Call from the customer field's onChanged — a manual edit means the
  /// text no longer necessarily matches the previously-picked customer.
  void onCustomerTextChanged(String value) {
    if (selectedCustomer.value != null && value != selectedCustomer.value!.name) {
      selectedCustomer.value = null;
    }
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
    if (isCashUnderTendered) {
      CustomAppSnackbar.warning('Amount tendered is less than the total due.');
      return;
    }
    if (isDiscountBlocked) {
      CustomAppSnackbar.warning('Only managers can apply a discount.');
      return;
    }
    isChargingOrHolding.value = true;
    try {
      final result = await _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discount: discountValue,
        tax: taxValue,
        paymentMethod: selectedPayment.value,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        customerId: selectedCustomer.value?.id,
        notes: _buildNotes(),
        status: 'completed',
        idempotencyKey: _newIdempotencyKey(),
      );
      if (result.queued) {
        clearSale();
        Get.back(); // close cart sheet
        CustomAppSnackbar.warning('No connection — sale saved and will sync automatically.');
        return;
      }
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
    if (isDiscountBlocked) {
      CustomAppSnackbar.warning('Only managers can apply a discount.');
      return;
    }
    isChargingOrHolding.value = true;
    try {
      final result = await _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discount: discountValue,
        tax: taxValue,
        paymentMethod: selectedPayment.value,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        customerId: selectedCustomer.value?.id,
        notes: _buildNotes(),
        status: 'held',
        idempotencyKey: _newIdempotencyKey(),
      );
      if (result.queued) {
        clearSale();
        Get.back();
        CustomAppSnackbar.warning('No connection — held sale saved and will sync automatically.');
        return;
      }
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
  /// Rebuilds the cart from a held sale's own line items. Each
  /// `PosSaleItemModel` already carries a full snapshot (name/sku/image/
  /// price) taken by the backend at hold time, so a product missing from
  /// the currently-loaded catalog page (or since removed/edited) doesn't
  /// need to be silently dropped — a synthetic single-variant product is
  /// built from that snapshot instead, at the originally-held price.
  void resumeHeldSale(PosSaleModel sale) {
    clearSale();
    for (final item in sale.items) {
      final liveProduct = allProducts.firstWhereOrNull(
        (p) => p.productId == item.productId,
      );
      final product = liveProduct ?? _productFromSaleItemSnapshot(item);
      final variant = liveProduct != null
          ? liveProduct.variantById(item.variantId)
          : product.defaultVariant;
      cartItems.add(
        CartItem(product: product, variant: variant, qty: item.qty),
      );
    }
    cartItems.refresh();
    customerController.text = sale.customerName == 'Walk-in'
        ? ''
        : sale.customerName;
    if (sale.customerId != null && sale.customerId!.isNotEmpty) {
      selectedCustomer.value = CustomerModel(id: sale.customerId!, name: sale.customerName);
    }
    noteController.text = sale.notes;
  }

  PosProductModel _productFromSaleItemSnapshot(PosSaleItemModel item) {
    return PosProductModel(
      productId: item.productId,
      name: item.name,
      type: 'physical',
      image: item.image,
      categoryId: '',
      variants: [
        PosProductVariant(
          variantId: item.variantId ?? item.productId,
          sku: item.sku ?? '',
          price: item.price,
          // Stock is unknown from a sale snapshot — resuming bypasses the
          // normal inStock/addToCart gate anyway, so this is display-only.
          stock: item.qty,
          isDefault: true,
          images: item.image != null ? [item.image!] : const [],
        ),
      ],
    );
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
                      text: '${controller.currencySymbol.value}${v.price.toStringAsFixed(2)}',
                      color: AppColors.primaryColor,
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
