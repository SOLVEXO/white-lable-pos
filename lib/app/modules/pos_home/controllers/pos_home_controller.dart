import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/pos_totals.dart';
import 'dart:async';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
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
    CartSnapshotStore? cartStore,
    CatalogCacheStore? catalogCache,
    SettingsCacheStore? settingsCache,
  }) : _posRepo = posRepository ?? PosRepository(),
       _categoryRepo = categoryRepository ?? CategoryRepository(),
       _cartStore = cartStore ?? CartSnapshotStore.instance,
       _catalogCache = catalogCache ?? CatalogCacheStore.instance,
       _settingsCache = settingsCache ?? SettingsCacheStore.instance;

  final PosRepository _posRepo;
  final CategoryRepository _categoryRepo;
  final CartSnapshotStore _cartStore;
  final CatalogCacheStore _catalogCache;
  final SettingsCacheStore _settingsCache;

  // ── Offline resilience ────────────────────────────────────────────────────
  /// The catalog / settings on screen came from the on-device cache (the server couldn't be reached) — prices and
  /// the tax rate may be out of date. [catalogUpdatedAt] / [settingsUpdatedAt] say how old.
  final RxBool catalogFromCache = false.obs;
  final Rxn<DateTime> catalogUpdatedAt = Rxn<DateTime>();
  final RxBool settingsFromCache = false.obs;
  final Rxn<DateTime> settingsUpdatedAt = Rxn<DateTime>();
  bool get isDataStale => catalogFromCache.value || settingsFromCache.value;

  /// The checkout currently being charged: its idempotency key and the moment Charge was tapped. Set on the first
  /// Charge tap, saved with the cart, reused on every retry / after a restart, cleared when the attempt reaches a
  /// final result or the cart is edited (a changed cart is a different sale and must not reuse the key).
  String? _pendingKey;
  DateTime? _pendingAt;
  Timer? _persistTimer;
  bool _restoring = false;

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
  final RxString currencySymbol = Money.symbol().obs;

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

  /// The store's tax rate from POS settings (0.08 = 8%). NOT typed by the cashier — the server applies the same
  /// rate and ignores any client tax, so a cashier-editable field would be a lie.
  double get taxRate => settings.value?.taxRate ?? 0.0;
  String get taxLabel => settings.value?.taxRatePercentLabel ?? '0%';

  /// Cart pricing exactly as the server will compute it (see PosTotals). Display only — the server decides.
  PosTotals get totals => PosTotals.compute(
        [for (final i in cartItems) (price: i.unitPrice, qty: i.quantity.value)],
        exponent: Money.exponent,
        percentDiscount: isPercentDiscount.value,
        discountInput: _rawDiscountInput,
        taxRate: taxRate,
      );

  double get subtotal => totals.subtotal;
  double get discountValue => totals.discount;
  double get taxValue => totals.tax;
  double get total => totals.total;

  /// The discount asked for is more than the subtotal — the server rejects it, so Charge/Hold are blocked.
  bool get isDiscountInvalid => totals.discountExceedsSubtotal;

  int get itemCount => cartItems.fold(0, (sum, i) => sum + i.quantity.value);
  bool get hasItems => cartItems.isNotEmpty;

  void toggleDiscountType() {
    isPercentDiscount.value = !isPercentDiscount.value;
    cartItems.refresh();
  }

  // ── Payment (single or split tender) ──────────────────────────────────────────
  // The server validates all of this again (card/other can't exceed the total, cash may exceed → change); the
  // checks here only tell the cashier what the server will accept.
  final RxBool isSplitPayment = false.obs;
  final RxList<SplitPaymentLine> splitLines = <SplitPaymentLine>[].obs;

  double get tenderedAmount => double.tryParse(tenderedController.text) ?? 0.0;

  /// The tenders as entered: one line (cash = what was handed over; card/other = the whole total) or the split rows.
  List<PosPaymentEntry> get paymentEntries {
    if (isSplitPayment.value) {
      return [
        for (final l in splitLines)
          if (l.amountValue > 0) PosPaymentEntry(l.method.value, l.amountValue),
      ];
    }
    final method = selectedPayment.value;
    return [PosPaymentEntry(method, method == PosPaymentMethod.cash ? tenderedAmount : total)];
  }

  PosPaymentCheck get paymentCheck => PosPaymentCheck.evaluate(total, paymentEntries, exponent: Money.exponent);

  double get changeDue => paymentCheck.change;
  bool get isCashUnderTendered => hasItems && !paymentCheck.covered && !paymentCheck.nonCashExceedsTotal;

  void toggleSplitPayment() {
    isSplitPayment.toggle();
    if (isSplitPayment.value && splitLines.isEmpty) {
      splitLines.add(SplitPaymentLine(PosPaymentMethod.card));
      splitLines.add(SplitPaymentLine(PosPaymentMethod.cash));
    }
    cartItems.refresh();
  }

  void addSplitLine() {
    if (splitLines.length >= 8) return;
    splitLines.add(SplitPaymentLine(PosPaymentMethod.cash));
  }

  void removeSplitLine(int index) {
    if (splitLines.length <= 1 || index < 0 || index >= splitLines.length) return;
    splitLines.removeAt(index).dispose();
    cartItems.refresh();
  }

  /// Puts what is still owed into a split row (card/other: the remainder; cash: what's left to hand over).
  void fillRemaining(int index) {
    final others = [
      for (var i = 0; i < splitLines.length; i++)
        if (i != index && splitLines[i].amountValue > 0) PosPaymentEntry(splitLines[i].method.value, splitLines[i].amountValue),
    ];
    final left = PosPaymentCheck.evaluate(total, others, exponent: Money.exponent).shortBy;
    splitLines[index].amount.text = Money.plain(left);
    cartItems.refresh();
  }

  /// Mirrors the backend's real, token-verified discount gate (createSale/
  /// completeSale/editHeldSaleItems all reject discount>0 without a
  /// verified manager token) — client-side so a cashier gets a clear
  /// message instead of a 403 after filling out the whole cart.
  bool get isDiscountBlocked => _rawDiscountInput > 0 && !isManager.value;

  bool get canCharge =>
      hasItems && paymentCheck.covered && !isDiscountBlocked && !isDiscountInvalid && !PosEntitlementService.isRestricted;

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
    _loadContext().then((_) async {
      await _restoreCart();
      _attachPersistence();
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
    tenderedController.dispose();
    paymentReferenceController.dispose();
    for (final l in splitLines) {
      l.dispose();
    }
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
    final fresh = await _posRepo.getPosSettings(storeId.value);
    if (fresh != null) {
      settings.value = fresh;
      settingsFromCache.value = false;
      settingsUpdatedAt.value = DateTime.now();
      unawaited(_settingsCache.save(fresh));
    } else {
      // Can't reach the server: price and print receipts with the last settings we saw (tax rate, version, header…).
      final cached = await _settingsCache.load(storeId.value);
      if (cached != null && settings.value == null) {
        settings.value = cached.settings;
        settingsFromCache.value = true;
        settingsUpdatedAt.value = cached.savedAt;
      }
    }
    currencySymbol.value = Money.symbol(); // from the store's currency code, never free text
  }

  /// Re-tries the server for the catalog and settings (the 'Refresh' on the stale-data bar).
  Future<void> refreshCatalogAndSettings() async {
    await _loadSettings();
    await _loadProducts();
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
      if (result.items.isNotEmpty) {
        allProducts.assignAll(result.items);
        _hasMoreProducts = result.hasMore;
        catalogFromCache.value = false;
        catalogUpdatedAt.value = DateTime.now();
        unawaited(_catalogCache.save(storeId.value, allProducts));
      } else {
        // Nothing came back (offline / server down): sell from the last catalog we saw, and say how old it is.
        final cached = await _catalogCache.load(storeId.value);
        if (cached != null && cached.products.isNotEmpty) {
          allProducts.assignAll(cached.products);
          _hasMoreProducts = false;
          catalogFromCache.value = true;
          catalogUpdatedAt.value = cached.savedAt;
        } else {
          allProducts.assignAll(result.items);
          _hasMoreProducts = result.hasMore;
        }
      }
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
      if (!catalogFromCache.value) unawaited(_catalogCache.save(storeId.value, allProducts));
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

  // ── Cart persistence (crash / kill / restart) ─────────────────────────────
  void _attachPersistence() {
    ever(cartItems, (_) => _onCartEdited());
    for (final c in [discountController, noteController, customerController, tenderedController, paymentReferenceController]) {
      c.addListener(_onCartEdited);
    }
    ever(selectedPayment, (_) => _onCartEdited());
    ever(isPercentDiscount, (_) => _onCartEdited());
    ever(isSplitPayment, (_) => _onCartEdited());
  }

  /// Any edit to the cart or payment entry makes it a different sale: drop the in-flight key (reusing it would make
  /// the server answer with the OLD sale), and save the cart a moment later.
  void _onCartEdited() {
    if (_restoring) return;
    if (!isChargingOrHolding.value) {
      _pendingKey = null;
      _pendingAt = null;
    }
    persistSoon();
  }

  void persistSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () => unawaited(persistNow()));
  }

  CartSnapshot _snapshot() => CartSnapshot(
        storeId: storeId.value,
        sessionId: sessionId.value,
        lines: [for (final i in cartItems) CartLineSnapshot(product: i.product.toJson(), variantId: i.variant?.variantId, qty: i.quantity.value)],
        discountText: discountController.text,
        percentDiscount: isPercentDiscount.value,
        customerName: customerController.text,
        customerId: selectedCustomer.value?.id,
        note: noteController.text,
        payment: selectedPayment.value,
        tendered: tenderedController.text,
        paymentReference: paymentReferenceController.text,
        split: isSplitPayment.value,
        splitLines: [for (final l in splitLines) SplitLineSnapshot(method: l.method.value, amount: l.amount.text, reference: l.reference.text)],
        pendingKey: _pendingKey,
        pendingAt: _pendingAt,
        savedAt: DateTime.now(),
      );

  Future<void> persistNow() async {
    if (storeId.value.isEmpty || sessionId.value.isEmpty) return;
    await _cartStore.save(_snapshot());
  }

  /// Rebuilds the cart left by a crash / kill / restart (same store + same register session, recent), including the
  /// checkout that may have been in flight.
  @visibleForTesting
  Future<void> restoreCart() => _restoreCart();

  Future<void> _restoreCart() async {
    if (storeId.value.isEmpty || sessionId.value.isEmpty) return;
    final snap = await _cartStore.load(storeId: storeId.value, sessionId: sessionId.value);
    if (snap == null) return;
    _restoring = true;
    try {
      for (final l in snap.lines) {
        final product = PosProductModel.fromJson(l.product);
        final variant = l.variantId == null ? null : product.variantById(l.variantId);
        cartItems.add(CartItem(product: product, variant: variant, qty: l.qty));
      }
      discountController.text = snap.discountText;
      isPercentDiscount.value = snap.percentDiscount;
      customerController.text = snap.customerName;
      if (snap.customerId != null && snap.customerName.isNotEmpty) {
        selectedCustomer.value = CustomerModel(id: snap.customerId!, name: snap.customerName);
      }
      noteController.text = snap.note;
      selectedPayment.value = snap.payment;
      tenderedController.text = snap.tendered;
      paymentReferenceController.text = snap.paymentReference;
      if (snap.split) {
        isSplitPayment.value = true;
        for (final sl in snap.splitLines) {
          final line = SplitPaymentLine(sl.method);
          line.amount.text = sl.amount;
          line.reference.text = sl.reference;
          splitLines.add(line);
        }
      }
      _pendingKey = snap.pendingKey;
      _pendingAt = snap.pendingAt;
    } finally {
      _restoring = false;
    }
    if (cartItems.isNotEmpty) cartItems.refresh();
  }

  void clearSale() {
    _pendingKey = null;
    _pendingAt = null;
    _persistTimer?.cancel();
    unawaited(_cartStore.clear());
    cartItems.clear();
    noteController.clear();
    customerController.clear();
    selectedCustomer.value = null;
    discountController.text = '0';
    isPercentDiscount.value = false;
    tenderedController.clear();
    paymentReferenceController.clear();
    selectedPayment.value = PosPaymentMethod.cash;
    isSplitPayment.value = false;
    for (final l in splitLines) {
      l.dispose();
    }
    splitLines.clear();
  }

  /// Free-text note for the sale. (The card auth code / bank reference now travels on the payment line itself.)
  String _buildNotes() => noteController.text.trim();

  /// What goes to the server for the tenders: split rows as `payments`, or the single method with the
  /// cash handed over / the card or bank reference.
  ({List<Map<String, dynamic>>? payments, double? amountTendered, String? reference, String method}) _paymentPayload() {
    if (isSplitPayment.value) {
      final lines = [
        for (final l in splitLines)
          if (l.amountValue > 0)
            {
              'method': l.method.value,
              'amount': l.amountValue,
              if (l.method.value != PosPaymentMethod.cash && l.reference.text.trim().isNotEmpty) 'reference': l.reference.text.trim(),
            },
      ];
      return (payments: lines, amountTendered: null, reference: null, method: splitLines.first.method.value);
    }
    final method = selectedPayment.value;
    return (
      payments: null,
      amountTendered: method == PosPaymentMethod.cash ? tenderedAmount : null,
      reference: method == PosPaymentMethod.cash ? null : paymentReferenceController.text.trim(),
      method: method,
    );
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
    if (isDiscountInvalid) {
      CustomAppSnackbar.warning('The discount cannot be more than the subtotal.');
      return;
    }
    final pay = _paymentPayload();
    isChargingOrHolding.value = true;
    try {
      // This checkout's identity — fixed on the first Charge tap, saved with the cart, reused on every retry and
      // after a crash/restart, so the same intent can never become two sales.
      _pendingKey ??= IdempotencyIntentStore.newKey();
      _pendingAt ??= DateTime.now();
      await persistNow();

      // Price it on the server first (when reachable) and charge THAT total with the settingsVersion it used.
      var chargeTotal = total;
      var version = settings.value?.settingsVersion;
      final q = await _posRepo.quoteSale(
        storeId: storeId.value,
        items: _buildItems(),
        discountType: isPercentDiscount.value ? 'percent' : 'amount',
        discountValue: _rawDiscountInput,
        settingsVersion: version,
      );
      if (q.quote != null) {
        version = q.quote!.settingsVersion;
        if (Money.toMinor(q.quote!.total) != Money.toMinor(total)) {
          // This device's prices / tax rate were out of date. Bring the cart in line with the server and let the
          // cashier see the new total BEFORE anyone is charged.
          _applyQuote(q.quote!);
          final ok = await _confirmNewTotal(q.quote!.total);
          if (!ok) {
            _pendingKey = null;
            _pendingAt = null;
            return;
          }
          chargeTotal = q.quote!.total;
          if (!PosPaymentCheck.evaluate(chargeTotal, paymentEntries, exponent: Money.exponent).covered) {
            CustomAppSnackbar.warning('The total changed — please re-enter the payment.');
            _pendingKey = null;
            _pendingAt = null;
            return;
          }
        }
      } else if (q.message != null) {
        // a business refusal (e.g. POS plan not active) — nothing to charge
        CustomAppSnackbar.error(q.message!);
        _pendingKey = null;
        _pendingAt = null;
        return;
      } // else: server unreachable → price with the cached settings; the sale goes through the offline queue if needed

      final result = await _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discountType: isPercentDiscount.value ? 'percent' : 'amount',
        discountValue: _rawDiscountInput,
        clientTotal: chargeTotal,
        settingsVersion: version,
        clientCreatedAt: _pendingAt,
        idempotencyKey: _pendingKey,
        paymentMethod: pay.method,
        payments: pay.payments,
        amountTendered: pay.amountTendered,
        paymentReference: pay.reference,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        customerId: selectedCustomer.value?.id,
        notes: _buildNotes(),
        status: 'completed',
      );
      if (result.queued) {
        clearSale();
        Get.back(); // close cart sheet
        _afterSalePrint(null, hadCash: _paidWithCash(pay));
        CustomAppSnackbar.warning('Sale saved on this device and will sync automatically — do not ring it up again.');
        return;
      }
      if (!result.success) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        // A definite answer ends this checkout attempt; no answer at all (message null) keeps the key so the
        // retry is the SAME sale.
        if (result.message != null) {
          _pendingKey = null;
          _pendingAt = null;
        }
        if ((result.message ?? '').toLowerCase().contains('does not match')) {
          await _loadSettings();
          await _loadProducts();
        }
        return;
      }
      final soldSale = result.sale;
      clearSale();
      Get.back(); // close cart sheet
      CustomAppSnackbar.success('Sale completed!');
      if (soldSale != null) {
        _afterSalePrint(ReceiptData.fromSale(soldSale, settings.value, isCopy: false, asciiSafeMoney: true), hadCash: _paidWithCash(pay));
      }
    } finally {
      isChargingOrHolding.value = false;
    }
  }

  bool _paidWithCash(({List<Map<String, dynamic>>? payments, double? amountTendered, String? reference, String method}) pay) =>
      pay.payments != null ? pay.payments!.any((p) => p['method'] == PosPaymentMethod.cash) : pay.method == PosPaymentMethod.cash;

  /// Auto-print + cash-drawer kick. Fire-and-forget: the sale is already saved, a printer problem only produces a notice.
  void _afterSalePrint(ReceiptData? receipt, {required bool hadCash}) {
    if (!Get.isRegistered<ThermalPrinterService>()) return;
    final printer = Get.find<ThermalPrinterService>();
    printer.onBackgroundFailure ??= (m) => CustomAppSnackbar.warning('$m (Reprint or share it from Orders.)');
    printer.afterSale(receipt: receipt, hadCash: hadCash);
  }

  /// Takes the server's current unit prices and tax rate into the cart/settings so the on-screen numbers equal its.
  void _applyQuote(PosQuote quote) {
    for (var i = 0; i < cartItems.length; i++) {
      final item = cartItems[i];
      final price = item.variant == null ? null : quote.unitPrices[item.variant!.variantId];
      if (price != null && price != item.variant!.price) {
        cartItems[i] = CartItem(product: item.product, variant: item.variant!.withPrice(price), qty: item.quantity.value);
      }
    }
    final cur = settings.value;
    if (cur != null) settings.value = cur.withPricing(taxRate: quote.taxRate, settingsVersion: quote.settingsVersion);
    cartItems.refresh();
  }

  Future<bool> _confirmNewTotal(double newTotal) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Total updated'),
        content: Text('Prices or tax were updated since this device last loaded them.\n\nThe total is now ${Money.format(newTotal)}. Charge this amount?'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          TextButton(onPressed: () => Get.back(result: true), child: Text('Charge ${Money.format(newTotal)}')),
        ],
      ),
      barrierDismissible: false,
    );
    return ok ?? false;
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
        discountType: isPercentDiscount.value ? 'percent' : 'amount',
        discountValue: _rawDiscountInput,
        clientTotal: total,
        settingsVersion: settings.value?.settingsVersion,
        paymentMethod: selectedPayment.value,
        customerName: customerController.text.trim().isEmpty
            ? 'Walk-in'
            : customerController.text.trim(),
        customerId: selectedCustomer.value?.id,
        notes: _buildNotes(),
        status: 'held',
      );
      if (result.queued) {
        clearSale();
        Get.back();
        CustomAppSnackbar.warning('Held sale saved on this device and will sync automatically.');
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
            // the price this till shows/charges — the server uses it only when the sale is replayed offline
            'unitPrice': c.unitPrice,
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
    if (lower.contains('does not match')) return 'Prices or tax changed — the total was refreshed. Please review and charge again.';
    if (lower.contains('cannot be more than') || lower.contains('exceed')) return 'The discount or payment is more than allowed. Please check the amounts.';
    if (lower.contains('do not cover') || lower.contains('payments')) return 'The payments do not cover the total.';
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
              onTap: v.isAvailable
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
                            color: v.isAvailable ? kPosText : kPosSubText,
                            fontWeight: FontWeight.w600,
                          ),
                          CustomText(
                            text: v.unlimitedStock
                                ? 'Unlimited stock'
                                : (v.stock > 0 ? '${v.stock} in stock' : 'Out of stock'),
                            color: v.isAvailable ? kPosSubText : kPosRed,
                            fontSize: 12,
                          ),
                        ],
                      ),
                    ),
                    CustomText(
                      text: Money.format(v.price),
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

/// One row of a split-tender payment being entered. For cash [amount] is what the customer hands over.
class SplitPaymentLine {
  SplitPaymentLine(String method) : method = method.obs;

  final RxString method;
  final TextEditingController amount = TextEditingController();
  final TextEditingController reference = TextEditingController();

  double get amountValue => double.tryParse(amount.text.trim()) ?? 0.0;

  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}
