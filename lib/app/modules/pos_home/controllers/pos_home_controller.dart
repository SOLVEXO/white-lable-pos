import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/pos_totals.dart';
import 'dart:async';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/local/catalog_pricing_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart' show InvCur;
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_picker_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/cart_lot_advisor.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/sale_customer_state.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_screen.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/qr_availability.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/hid_scan_detector.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_modifier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_variant_picker_sheet.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// G2.4 custom item: `standard` = the store tax rate, `exempt` = no tax on this line (only meaningful for custom items).
  final String taxCategory;
  final String customNote;

  /// G3.2: the lot the sale would take from (null = not lot-tracked / not known yet), whether that answer is live from the server (false =
  /// remembered from an earlier answer, shown as "as of"), and whether a manager approved selling EXPIRED units of this line.
  final Rxn<LotPreview> lotPreview = Rxn<LotPreview>();
  final RxBool lotPreviewLive = false.obs;
  final RxBool sellExpired = false.obs;

  /// G4.5: the options chosen for this line (part of its identity: a Large and a Small latte are two lines). The SERVER prices them.
  final List<ChosenModifier> modifiers;

  /// G4.5: the price book's price for this variant (the cashier picked a book at checkout), an on-screen estimate until the server's quote
  double? bookUnitPrice;

  /// G4.5: the server's unit price for a line it priced with modifiers or a price book (from the quote) — wins over every estimate
  double? serverUnitPrice;

  CartItem({required this.product, this.variant, int qty = 1, this.taxCategory = 'standard', this.customNote = '', this.modifiers = const [], this.bookUnitPrice, this.serverUnitPrice})
    : quantity = qty.obs;

  /// A line with no catalogue product (a service, a one-off, a price the shelf doesn't have). Never touches stock; the server
  /// prices and audits it, and asks for a manager above the store's limit. The product shell here only carries the name.
  factory CartItem.custom({required String id, required String name, required double price, int qty = 1, String taxCategory = 'standard', String note = ''}) {
    return CartItem(
      product: PosProductModel(
        productId: '$kCustomPrefix$id',
        name: name,
        type: 'custom',
        categoryId: '',
        variants: [PosProductVariant(variantId: 'custom', sku: 'CUSTOM', price: price, stock: 0, unlimitedStock: true, isDefault: true)],
      ),
      variant: null,
      qty: qty,
      taxCategory: taxCategory,
      customNote: note,
    );
  }

  static const kCustomPrefix = 'custom:';
  bool get isCustom => product.productId.startsWith(kCustomPrefix);
  bool get isTaxable => !isCustom || taxCategory != 'exempt';

  /// the list price (a custom item's price is its shell product's only variant)
  double get listPrice => variant?.price ?? product.price;

  /// Σ of the chosen options' price deltas, in minor units
  int get modifierDeltaMinor => modifiers.fold(0, (n, m) => n + m.priceDeltaMinor);

  /// What this line charges per unit: the server's price when it has priced the line, else (book price or list price) + the options.
  double get unitPrice {
    if (isCustom) return listPrice;
    if (serverUnitPrice != null) return serverUnitPrice!;
    final base = bookUnitPrice ?? listPrice;
    return modifiers.isEmpty ? base : base + Money.fromMinor(modifierDeltaMinor);
  }

  double get lineTotal => unitPrice * quantity.value;

  /// "Latte (Large, Extra shot)" — the same name the server gives the line
  String get displayName => '${product.name}${ChosenModifier.suffix(modifiers)}';

  /// The key used to deduplicate in the cart (different options = different lines).
  String get cartKey {
    final base = variant != null ? '${product.productId}_${variant!.variantId}' : product.productId;
    return modifiers.isEmpty ? base : '${base}_${ChosenModifier.key(modifiers)}';
  }
}

// ── How the last Charge ended (read by the sale-success view) ────────────────
enum SaleOutcome { completed, queuedOffline }

// ── Payment methods accepted by the backend ───────────────────────────────────
class PosPaymentMethod {
  static const cash = 'cash';
  static const card = 'card';
  static const other = 'other';
  static const raastQr = 'raast_qr';
  /// G3.3: spends the attached customer's store credit (online only; offered by the payment sheet, never one of the plain tiles)
  static const storeCredit = 'store_credit';

  /// The tenders every till offers. Raast QR is added by the payment sheet (it can be unavailable for a store).
  static const List<String> all = [cash, card, other];

  /// Everything the chooser lists, in order.
  static const List<String> tiles = [cash, card, other, raastQr];

  static bool isDigital(String method) => method == raastQr;

  static String label(String method) {
    switch (method) {
      case cash:
        return 'Cash';
      case card:
        return 'Card';
      case raastQr:
        return 'Raast QR';
      case storeCredit:
        return 'Store credit';
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
    PosPaymentsRepository? paymentsRepository,
    PendingQrStore? pendingQrStore,
    CartLotAdvisor? lotAdvisor,
    Future<String?> Function({required String reason, PosRepository? repository})? approval,
  }) : _approval = approval ?? ManagerApproval.request,
       _posRepo = posRepository ?? PosRepository(),
       _payRepo = paymentsRepository ?? PosPaymentsRepository(),
       _pendingQr = pendingQrStore ?? PendingQrStore.instance,
       _categoryRepo = categoryRepository ?? CategoryRepository(),
       _cartStore = cartStore ?? CartSnapshotStore.instance,
       _catalogCache = catalogCache ?? CatalogCacheStore.instance,
       _settingsCache = settingsCache ?? SettingsCacheStore.instance {
    _lots = lotAdvisor ?? CartLotAdvisor(repository: _posRepo, isOnline: () => _online, storeId: () => storeId.value);
    saleCustomer = SaleCustomerState(repository: _posRepo, storeId: () => storeId.value, isOnline: () => _online);
  }

  final PosRepository _posRepo;
  late final CartLotAdvisor _lots;

  /// G3.3: the attached customer's balances and the store's credit / loyalty rules, and the points chosen for this sale.
  late final SaleCustomerState saleCustomer;
  final Future<String?> Function({required String reason, PosRepository? repository}) _approval;
  final CategoryRepository _categoryRepo;
  final CartSnapshotStore _cartStore;
  final CatalogCacheStore _catalogCache;
  final SettingsCacheStore _settingsCache;
  final PosPaymentsRepository _payRepo;
  final PendingQrStore _pendingQr;

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

  /// How the most recent Charge ended: [SaleOutcome.completed] (the server accepted it) or [SaleOutcome.queuedOffline]
  /// (saved on this device, will sync). Null when the last Charge failed, was declined, or no Charge has happened yet.
  /// Reset to null at the start of every [completeSale]; set only where the success / queued toast fires. Read-only for
  /// the UI (the sale-success view) — nothing outside [completeSale] writes it.
  final Rxn<SaleOutcome> lastOutcome = Rxn<SaleOutcome>();

  /// The receipt of that Charge: the server's receipt for [SaleOutcome.completed], the provisional `OFF-…` receipt for
  /// [SaleOutcome.queuedOffline] (null if it could not be built — the sale itself is safe in the queue either way).
  final Rxn<ReceiptData> lastReceipt = Rxn<ReceiptData>();

  /// G3.3: the sale the server just recorded (its points and tenders feed the success view). Null for a queued offline sale.
  final Rxn<PosSaleModel> lastSale = Rxn<PosSaleModel>();
  final RxBool isScanningBarcode = false.obs;

  // ── G2.4: coupon + custom items ───────────────────────────────────────────
  /// The coupon the server accepted for this cart (null = none). Coupons are online-only: applying one is a live check, and
  /// the sale that uses it is never queued. Mutually exclusive with a manual discount (the server refuses both together).
  final Rxn<PosAppliedCoupon> appliedCoupon = Rxn<PosAppliedCoupon>();
  /// True while a coupon is being checked with the server — the Apply button is disabled (double-submit protection).
  final RxBool isApplyingCoupon = false.obs;
  /// True while a custom item is being added (the manager approval step is asynchronous) — double-submit protection.
  final RxBool isAddingCustomItem = false.obs;
  /// The last manager who approved a custom item on this sale (kept in memory only; the server re-checks it on every charge).
  String? _approverToken;

  /// G3.2: the manager's token that approved selling EXPIRED units on this sale (kept only for the sale in progress).
  String? _expiredApproverToken;
  bool get hasCustomItems => cartItems.any((i) => i.isCustom);
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

  /// A manual discount is typed (points cannot be combined with one).
  bool get isManualDiscountEntered => _rawDiscountInput > 0;

  // ── G3.3 loyalty redemption ───────────────────────────────────────────────────
  /// Points spent on this sale. Points cannot be combined with a coupon or a manual discount (the server refuses it), so they count as
  /// zero while one of those is on the sale, and never on a sale without a customer or while offline.
  int get redeemPointsEffective => (saleCustomer.attached && saleCustomer.pointsEnabled && appliedCoupon.value == null && _rawDiscountInput <= 0) ? saleCustomer.redeemPoints.value : 0;

  /// What those points take off the sale, in the sale's major units. Display only — the server prices the redemption and its total is
  /// what the sale is charged; this is the same figure (a flat amount discount).
  double get redeemValueMajor => redeemPointsEffective <= 0 ? 0 : Money.fromMinor(redeemPointsEffective * (saleCustomer.rules.redeemMinorPerPoint ?? 0));

  /// The cart's subtotal in minor units (before any discount).
  int get _subtotalMinor => Money.toMinor(PosTotals.compute([for (final i in cartItems) (price: i.unitPrice, qty: i.quantity.value, taxable: i.isTaxable)], exponent: Money.exponent, percentDiscount: false, discountInput: 0, taxRate: 0).subtotal);

  /// Most points that can be spent on the cart as it is now.
  int get maxRedeemPoints => saleCustomer.maxPoints(_subtotalMinor);

  void setRedeemPoints(int v) {
    if (!saleCustomer.pointsEnabled || !_online) return;
    final max = maxRedeemPoints;
    saleCustomer.redeemPoints.value = v < 0 ? 0 : (v > max ? max : v);
    cartItems.refresh();
  }

  /// The store's tax rate from POS settings (0.08 = 8%). NOT typed by the cashier — the server applies the same
  /// rate and ignores any client tax, so a cashier-editable field would be a lie.
  double get taxRate => settings.value?.taxRate ?? 0.0;
  String get taxLabel => settings.value?.taxRatePercentLabel ?? '0%';

  /// Cart pricing exactly as the server will compute it (see PosTotals). Display only — the server decides.
  PosTotals get totals => PosTotals.compute(
        [for (final i in cartItems) (price: i.unitPrice, qty: i.quantity.value, taxable: i.isTaxable)],
        exponent: Money.exponent,
        percentDiscount: redeemValueMajor > 0 ? false : (appliedCoupon.value != null ? appliedCoupon.value!.discountType == 'percentage' : isPercentDiscount.value),
        discountInput: redeemValueMajor > 0 ? redeemValueMajor : (appliedCoupon.value != null ? appliedCoupon.value!.discountValue : _rawDiscountInput),
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

  // ── Raast QR (G2.3) ───────────────────────────────────────────────────────────
  /// QR payments already CONFIRMED for the checkout in progress, by QR line index: if the sale then fails to save, the next
  /// Charge attaches the SAME payment instead of charging the customer again. Dropped when the amount no longer matches.
  final Map<int, ({String intentId, int amountMinor})> _qrConfirmed = {};
  bool _qrStarted = false;

  /// Whether the till can reach the server (observable: read it inside an Obx).
  bool get tillOnline => _online;

  bool get _online => !Get.isRegistered<NetworkStatusService>() || Get.find<NetworkStatusService>().isOnline.value;

  /// Is Raast QR usable now? (store verified by the server · internet) — and what to tell the user when it is not.
  QrAvailabilityInfo get qrAvailability => QrAvailabilityRules.evaluate(
        verified: PosEntitlementService.maybe?.digitalPaymentsEnabled.value,
        online: _online,
        isManager: isManager.value,
      );

  /// QR lines of the checkout as entered: (line index, amount in minor units, from the split row or the whole total).
  List<({int index, int amountMinor})> _qrLines(double chargeTotal) {
    if (isSplitPayment.value) {
      return [
        for (var i = 0; i < splitLines.length; i++)
          if (splitLines[i].method.value == PosPaymentMethod.raastQr && splitLines[i].amountValue > 0) (index: i, amountMinor: Money.toMinor(splitLines[i].amountValue)),
      ];
    }
    return selectedPayment.value == PosPaymentMethod.raastQr ? [(index: 0, amountMinor: Money.toMinor(chargeTotal))] : const [];
  }

  bool get hasQrLine => _qrLines(total).isNotEmpty;

  /// The tenders a split row may choose from: the usual three, plus Raast QR when it is usable and no OTHER row already uses it
  /// (one QR per checkout in the till; the server itself accepts several). A row that already is QR keeps its choice listed.
  List<String> splitChoicesFor(int index) {
    final qrTaken = [for (var i = 0; i < splitLines.length; i++) if (i != index && splitLines[i].method.value == PosPaymentMethod.raastQr) i].isNotEmpty;
    final isQr = index >= 0 && index < splitLines.length && splitLines[index].method.value == PosPaymentMethod.raastQr;
    final offerQr = isQr || (!qrTaken && qrAvailability.isAvailable);
    final isCredit = index >= 0 && index < splitLines.length && splitLines[index].method.value == PosPaymentMethod.storeCredit;
    final creditTaken = [for (var i = 0; i < splitLines.length; i++) if (i != index && splitLines[i].method.value == PosPaymentMethod.storeCredit) i].isNotEmpty;
    final offerCredit = isCredit || (!creditTaken && storeCreditOffered);
    return [...PosPaymentMethod.all, if (offerQr) PosPaymentMethod.raastQr, if (offerCredit) PosPaymentMethod.storeCredit];
  }

  // ── G3.3 store credit tender ──────────────────────────────────────────────────
  /// Store credit can be offered: the store accepts it as a tender, a customer with a balance is on the sale, and the till is online.
  bool get storeCreditOffered => saleCustomer.storeCreditEnabled && saleCustomer.creditBalanceMinor > 0 && _online;

  /// What the split rows say is paid with store credit.
  double get storeCreditEntered => splitLines.where((l) => l.method.value == PosPaymentMethod.storeCredit).fold(0.0, (a, l) => a + l.amountValue);

  /// Why the store credit tender cannot be charged right now, in plain words (null = nothing in the way). The server decides in the end.
  String? get storeCreditIssue {
    if (!isSplitPayment.value || storeCreditEntered <= 0) return null;
    if (!_online) return customerErrorMessage('STORE_CREDIT_ONLINE_ONLY');
    if (!saleCustomer.attached) return customerErrorMessage('CUSTOMER_REQUIRED');
    if (Money.toMinor(storeCreditEntered) > saleCustomer.creditBalanceMinor) return 'That is more than the customer\'s store credit (${Money.format(saleCustomer.creditBalance)}).';
    return null;
  }

  /// Points chosen but the till went offline: the redemption cannot be checked, so the sale waits (it is never charged without them).
  String? get redeemIssue => saleCustomer.redeemPoints.value > 0 && redeemPointsEffective > 0 && !_online ? customerErrorMessage('LOYALTY_ONLINE_ONLY') : null;

  /// The first thing in the way of charging because of the customer's credit or points (null = nothing).
  String? get customerSaleIssue => storeCreditIssue ?? redeemIssue;

  /// One tap: pay with the customer's store credit — the whole amount due, or the whole balance with the rest left in a second row
  /// (cash) for the cashier to settle. Uses the split-payment rows.
  void useStoreCredit() {
    if (!storeCreditOffered) return;
    final due = Money.toMinor(total);
    final credit = saleCustomer.creditBalanceMinor < due ? saleCustomer.creditBalanceMinor : due;
    for (final l in splitLines) {
      l.dispose();
    }
    splitLines.clear();
    isSplitPayment.value = true;
    final creditLine = SplitPaymentLine(PosPaymentMethod.storeCredit)..amount.text = Money.plain(Money.fromMinor(credit));
    splitLines.add(creditLine);
    if (credit < due) {
      splitLines.add(SplitPaymentLine(PosPaymentMethod.cash)..amount.text = Money.plain(Money.fromMinor(due - credit)));
    }
    cartItems.refresh();
  }

  /// Shows the QR screen for every QR line that is not yet confirmed. True only when every QR line is confirmed.
  /// Nothing is charged here — a confirmed payment becomes a sale only when the server accepts the sale with that payment attached.
  Future<bool> _collectQr(double chargeTotal) async {
    final lines = _qrLines(chargeTotal);
    if (lines.isEmpty) return true;
    final info = qrAvailability;
    if (!info.isAvailable) {
      CustomAppSnackbar.warning(info.message ?? 'Raast QR is not available.');
      return false;
    }
    for (final l in lines) {
      final done = _qrConfirmed[l.index];
      if (done != null && done.amountMinor == l.amountMinor) continue; // paid already, the sale just did not save: attach it again
      _qrConfirmed.remove(l.index);
      _qrStarted = true;
      final r = await RaastQrScreen.collect(
        RaastQrController(
          amountMinor: l.amountMinor,
          sessionId: sessionId.value,
          saleAttemptKey: _pendingKey!,
          qrIndex: l.index,
          storeId: storeId.value,
          repository: _payRepo,
          store: _pendingQr,
        ),
        showSimulate: kDebugMode,
      );
      if (r.isConfirmed && r.intent != null) {
        _qrConfirmed[l.index] = (intentId: r.intent!.id, amountMinor: l.amountMinor);
        continue;
      }
      if (r.kind == QrResultKind.detached) return false; // the till was locked mid-payment: it resumes after unlock
      if (r.kind == QrResultKind.unavailable) CustomAppSnackbar.warning(r.message ?? 'Raast QR is not available.');
      if (r.kind == QrResultKind.expired || r.kind == QrResultKind.failed) CustomAppSnackbar.warning('No payment was taken. Choose a method to continue.');
      return false;
    }
    return true;
  }

  /// A QR payment found on this device after a restart / unlock: look it up on the server and carry on with the same checkout.
  /// Never creates a second payment. Paid → the sale is completed with it; still open → the QR screen reopens; over → forgotten.
  Future<void> resumePendingQr() async {
    final pq = await _pendingQr.read();
    if (pq == null) return;
    final sameCheckout = hasItems && pq.saleAttemptKey == _pendingKey;
    final r = await RaastQrScreen.collect(
      RaastQrController(
        amountMinor: pq.amountMinor,
        sessionId: sessionId.value,
        saleAttemptKey: pq.saleAttemptKey,
        qrIndex: pq.qrIndex,
        storeId: storeId.value,
        resumeFrom: pq,
        repository: _payRepo,
        store: _pendingQr,
      ),
      showSimulate: kDebugMode,
    );
    if (!r.isConfirmed || r.intent == null) return;
    if (sameCheckout && _qrLines(total).any((l) => l.index == pq.qrIndex && l.amountMinor == pq.amountMinor)) {
      _qrConfirmed[pq.qrIndex] = (intentId: r.intent!.id, amountMinor: pq.amountMinor);
      CustomAppSnackbar.success('Payment received — completing the sale.');
      await completeSale();
    } else {
      await _pendingQr.clear();
      CustomAppSnackbar.warning('A Raast payment was received for a sale that is no longer open. A manager can match it in Needs attention.');
    }
  }

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
      hasItems && paymentCheck.covered && !isDiscountBlocked && !isDiscountInvalid && !PosEntitlementService.isRestricted && customerSaleIssue == null;

  int cartQtyFor(PosProductModel p, [PosProductVariant? v]) {
    // every line of this product / variant (G4.5: different options are different lines)
    return cartItems
        .where((c) => c.product.productId == p.productId && (v == null || c.variant?.variantId == v.variantId))
        .fold(0, (n, c) => n + c.quantity.value);
  }

  // ── G4.5: modifier groups + price books (read from the server, cached for offline; the SERVER prices every line) ──
  final Rxn<ModifierGroups> modifierGroups = Rxn<ModifierGroups>();
  final RxList<PriceBook> priceBooks = <PriceBook>[].obs;

  /// the price book the cashier picked for this sale (null = normal prices, or the customer's own book, which the server applies)
  final Rxn<PriceBook> priceBook = Rxn<PriceBook>();

  Future<void> _loadPricing() async {
    final sid = storeId.value;
    if (sid.isEmpty) return;
    try {
      final g = await _posRepo.getModifierGroups(sid);
      if (g != null) {
        modifierGroups.value = g;
        unawaited(CatalogPricingCache.saveGroups(sid, g));
      } else {
        modifierGroups.value ??= await CatalogPricingCache.groups(sid);
      }
      final b = await _posRepo.getPriceBooks(sid);
      if (b != null) {
        priceBooks.assignAll(b.books);
        unawaited(CatalogPricingCache.saveBooks(sid, b));
      } else if (priceBooks.isEmpty) {
        priceBooks.assignAll((await CatalogPricingCache.books(sid))?.books ?? const <PriceBook>[]);
      }
    } catch (e) {
      debugPrint('pricing: $e'); // options and books are extras: selling never waits for them
    }
  }

  /// the books the picker offers (in force now by their own window; the server has the last word)
  List<PriceBook> get bookChoices => priceBooks.where((b) => b.inForceAt(DateTime.now().toUtc())).toList(); // the server's UTC boundaries (store midnight)

  void setPriceBook(PriceBook? b) {
    priceBook.value = b;
    for (final i in cartItems) {
      _applyBookEstimate(i);
    }
    cartItems.refresh();
  }

  /// the book's price for the line as the on-screen estimate (the next quote replaces it with the server's)
  void _applyBookEstimate(CartItem i) {
    if (i.isCustom) return;
    i.serverUnitPrice = null;
    final m = priceBook.value?.entries[i.variant?.variantId];
    i.bookUnitPrice = m == null ? null : Money.fromMinor(m);
  }

  void _showModifierSheet(PosProductModel product, PosProductVariant variant, List<ModifierGroup> groups) {
    Get.bottomSheet(
      PosModifierSheet(product: product, variant: variant, groups: groups, controller: this),
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) async {
      await _restoreCart();
      _attachPersistence();
      unawaited(resumePendingQr());
      _loadProducts();
      _loadSettings();
      unawaited(_loadPricing());
    });
    _loadCategoryNames();
    unawaited(loadRecentSearches());
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
    _lots.dispose();
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
    await _loadPricing();
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

  // ── Recent searches (what the cashier searched for before — plain words, no customer data) ──
  final RxList<String> recentSearches = <String>[].obs;
  static const _recentKey = 'pos_recent_searches';

  Future<void> loadRecentSearches() async {
    try {
      final list = (await SharedPreferences.getInstance()).getStringList(_recentKey) ?? const <String>[];
      recentSearches.assignAll(list.take(6));
    } catch (_) {}
  }

  /// Remembers [term] (most recent first, no duplicates, at most 6). Called when the cashier submits a search or adds a found product.
  Future<void> rememberSearch(String term) async {
    final t = term.trim();
    if (t.length < 2) return;
    recentSearches.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    recentSearches.insert(0, t);
    if (recentSearches.length > 6) recentSearches.removeRange(6, recentSearches.length);
    try {
      await (await SharedPreferences.getInstance()).setStringList(_recentKey, recentSearches.toList());
    } catch (_) {}
  }

  Future<void> clearRecentSearches() async {
    recentSearches.clear();
    try {
      await (await SharedPreferences.getInstance()).remove(_recentKey);
    } catch (_) {}
  }

  /// Runs a remembered search again.
  void useRecentSearch(String term) {
    searchController.text = term;
    onSearchChanged(term);
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
  /// [modifiers] = the options chosen in the modifier sheet; null = not asked yet (a product sold with options opens the sheet first).
  void addToCart(PosProductModel product, [PosProductVariant? variant, List<ChosenModifier>? modifiers]) {
    if (!product.inStock) return;
    if (product.hasMultipleVariants && variant == null) {
      _showVariantSheet(product);
      return;
    }
    variant ??= product.defaultVariant;
    if (variant == null) return;
    final groups = modifiers == null ? (modifierGroups.value?.of(product.productId) ?? const <ModifierGroup>[]) : const <ModifierGroup>[];
    if (groups.isNotEmpty) {
      // after this event: the variant sheet that called us closes itself (Get.back) right after this returns
      final v = variant;
      Future<void>.delayed(Duration.zero, () => _showModifierSheet(product, v, groups));
      return;
    }
    if (searchText.value.trim().isNotEmpty) unawaited(rememberSearch(searchText.value)); // the search that found it is worth keeping
    final item = CartItem(product: product, variant: variant, modifiers: modifiers ?? const []);
    final idx = cartItems.indexWhere((c) => c.cartKey == item.cartKey);
    if (idx >= 0) {
      cartItems[idx].quantity.value++;
      _lots.request(cartItems[idx]);
    } else {
      _applyBookEstimate(item);
      cartItems.add(item);
      _lots.request(item);
    }
    cartItems.refresh();
  }

  void removeFromCart(CartItem item) => cartItems.remove(item);

  void increment(CartItem item) {
    item.quantity.value++;
    _lots.request(item);
    cartItems.refresh();
  }

  void decrement(CartItem item) {
    if (item.quantity.value <= 1) {
      cartItems.remove(item);
    } else {
      item.quantity.value--;
      _lots.request(item);
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
    ever(appliedCoupon, (_) => _onCartEdited());
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
        lines: [for (final i in cartItems) CartLineSnapshot(product: i.product.toJson(), variantId: i.variant?.variantId, qty: i.quantity.value, taxCategory: i.isCustom ? i.taxCategory : null, note: i.isCustom ? i.customNote : null, modifiers: [for (final m in i.modifiers) m.toJson()])],
        coupon: appliedCoupon.value?.toJson(),
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
        final item = CartItem(product: product, variant: variant, qty: l.qty, taxCategory: l.taxCategory ?? 'standard', customNote: l.note ?? '', modifiers: [for (final m in l.modifiers) ChosenModifier.fromJson(m)]);
        cartItems.add(item);
        _lots.request(item);
      }
      if (snap.coupon != null) appliedCoupon.value = PosAppliedCoupon.fromJson(snap.coupon!);
      discountController.text = snap.discountText;
      isPercentDiscount.value = snap.percentDiscount;
      customerController.text = snap.customerName;
      if (snap.customerId != null && snap.customerName.isNotEmpty) {
        selectedCustomer.value = CustomerModel(id: snap.customerId!, name: snap.customerName);
        saleCustomer.attach(PosCustomer(id: snap.customerId!, kind: 'pos', name: snap.customerName), null);
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
    // Giving the checkout up releases any QR that was not paid (a paid one stays for a manager: it is money the till must not lose)
    final qrKey = _pendingKey;
    if (_qrStarted && qrKey != null) unawaited(_payRepo.cancelAttempt(qrKey));
    _qrStarted = false;
    _qrConfirmed.clear();
    unawaited(_pendingQr.clear());
    _pendingKey = null;
    _pendingAt = null;
    _persistTimer?.cancel();
    unawaited(_cartStore.clear());
    cartItems.clear();
    priceBook.value = null;
    appliedCoupon.value = null;
    _approverToken = null;
    _expiredApproverToken = null;
    noteController.clear();
    customerController.clear();
    selectedCustomer.value = null;
    saleCustomer.detach();
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
  ({List<Map<String, dynamic>>? payments, double? amountTendered, String? reference, String method}) _paymentPayload({double? chargeTotal}) {
    if (isSplitPayment.value) {
      final lines = [
        for (var i = 0; i < splitLines.length; i++)
          if (splitLines[i].amountValue > 0)
            {
              'method': splitLines[i].method.value,
              'amount': splitLines[i].amountValue,
              if (splitLines[i].method.value == PosPaymentMethod.raastQr && _qrConfirmed[i] != null) 'intentId': _qrConfirmed[i]!.intentId,
              if (splitLines[i].method.value != PosPaymentMethod.cash && splitLines[i].method.value != PosPaymentMethod.raastQr && splitLines[i].reference.text.trim().isNotEmpty) 'reference': splitLines[i].reference.text.trim(),
            },
      ];
      return (payments: lines, amountTendered: null, reference: null, method: splitLines.first.method.value);
    }
    final method = selectedPayment.value;
    if (method == PosPaymentMethod.raastQr) {
      // the sale carries the CONFIRMED payment's id; the server checks it is paid, matches the amount and is not used elsewhere
      return (payments: [{'method': method, 'amount': chargeTotal ?? total, if (_qrConfirmed[0] != null) 'intentId': _qrConfirmed[0]!.intentId}], amountTendered: null, reference: null, method: method);
    }
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
    final picked = await CustomerPickerSheet.open();
    if (picked != null) attachCustomer(picked.customer, picked.cur);
  }

  /// Attaches a customer to this sale (name field, id, and their balances / points for the payment sheet).
  void attachCustomer(PosCustomer c, InvCur? cur) {
    selectedCustomer.value = CustomerModel(id: c.id, name: c.name, email: c.email, phone: c.phone);
    customerController.text = c.name;
    saleCustomer.attach(c, cur);
    if (c.existing) CustomAppSnackbar.warning('${c.name} already has that phone number, so that customer was used.');
  }

  /// Call from the customer field's onChanged — a manual edit means the
  /// text no longer necessarily matches the previously-picked customer.
  void onCustomerTextChanged(String value) {
    if (selectedCustomer.value != null && value != selectedCustomer.value!.name) {
      selectedCustomer.value = null;
      saleCustomer.detach();
    }
  }

  void selectPayment(String method) => selectedPayment.value = method;
  void selectCategory(String categoryId) =>
      selectedCategoryId.value = categoryId;
  Future<void> retryLoadProducts() => _loadProducts();

  // ── Variant picker ────────────────────────────────────────────────────────
  void _showVariantSheet(PosProductModel product) {
    Get.bottomSheet(
      PosVariantPickerSheet(product: product, controller: this),
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
    );
  }

  // ── Charge (complete sale) ────────────────────────────────────────────────
  Future<void> completeSale() async {
    if (isChargingOrHolding.value) return; // double-submit protection: a second Charge while one is in flight does nothing
    lastOutcome.value = null;
    lastReceipt.value = null;
    lastSale.value = null;
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
    final customerIssue = customerSaleIssue;
    if (customerIssue != null) {
      CustomAppSnackbar.warning(customerIssue);
      return;
    }
    if (appliedCoupon.value != null && _rawDiscountInput > 0) {
      CustomAppSnackbar.warning('A coupon and a manual discount cannot be combined — remove one of them.');
      return;
    }
    var pay = _paymentPayload();
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
      final q = await _quoteCart(version);
      if (q.code != null && q.code!.startsWith('COUPON_') && appliedCoupon.value != null) {
        // the coupon is no longer good for this cart (expired, limit reached, below the minimum spend now…): say why, drop it
        CustomAppSnackbar.error(q.message ?? 'This coupon can no longer be used.');
        appliedCoupon.value = null;
        _pendingKey = null;
        _pendingAt = null;
        return;
      }
      if (q.code != null && catalogSaleCodes.contains(q.code)) {
        // G4.5: the picked price book is no longer in force, or an option rule is broken: say so in words; nothing is charged
        CustomAppSnackbar.error(catalogErrorMessage(q.code, message: q.message));
        if (q.code == 'PRICE_BOOK_NOT_ACTIVE') setPriceBook(null);
        _pendingKey = null;
        _pendingAt = null;
        return;
      }
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

      // Raast QR: the customer pays on the QR screen first; the sale is only sent once every QR line is CONFIRMED by the server.
      if (_qrLines(chargeTotal).isNotEmpty) {
        if (!await _collectQr(chargeTotal)) return;
        pay = _paymentPayload(chargeTotal: chargeTotal);
      }

      final result = await _withApproval(
        (approver) => _sendSale(
          status: 'completed',
          clientTotal: chargeTotal,
          settingsVersion: version,
          clientCreatedAt: _pendingAt,
          idempotencyKey: _pendingKey,
          paymentMethod: pay.method,
          payments: pay.payments,
          amountTendered: pay.amountTendered,
          paymentReference: pay.reference,
          approver: approver,
        ),
      );
      if (result.queued) {
        // Receipt for the customer NOW, under the provisional number (the server assigns the real one at sync).
        final offline = await _offlineReceiptForQueued(pay, chargeTotal);
        clearSale();
        Get.back(); // close cart sheet
        _afterSalePrint(offline, hadCash: _paidWithCash(pay));
        lastReceipt.value = offline;
        lastOutcome.value = SaleOutcome.queuedOffline;
        CustomAppSnackbar.warning(
          'Sale saved on this device${offline != null ? ' as receipt ${offline.receiptNumber}' : ''} and will sync automatically — do not ring it up again.',
        );
        return;
      }
      if (!result.success) {
        CustomAppSnackbar.error(_saleError(result.message));
        if (_qrConfirmed.isNotEmpty) {
          CustomAppSnackbar.warning('The customer has paid by Raast but the sale could not be saved. Try Charge again — the same payment is used. If it keeps failing, ask a manager to check Needs attention.');
        }
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
      lastSale.value = soldSale;
      Get.back(); // close cart sheet
      final receipt = soldSale == null ? null : ReceiptData.fromSale(soldSale, settings.value, isCopy: false, asciiSafeMoney: true);
      lastReceipt.value = receipt;
      lastOutcome.value = SaleOutcome.completed;
      CustomAppSnackbar.success('Sale completed!');
      if (receipt != null) {
        _afterSalePrint(receipt, hadCash: _paidWithCash(pay));
      }
    } finally {
      isChargingOrHolding.value = false;
    }
  }

  /// Builds, stores and returns the provisional receipt of the sale that was just queued (null if it can't be — the
  /// sale itself is safe in the queue either way).
  Future<ReceiptData?> _offlineReceiptForQueued(({List<Map<String, dynamic>>? payments, double? amountTendered, String? reference, String method}) pay, double chargeTotal) async {
    try {
      final key = _pendingKey;
      if (key == null || !Get.isRegistered<PendingSaleSyncService>()) return null;
      final sync = Get.find<PendingSaleSyncService>();
      final number = await sync.provisionalNumberFor(key);
      if (number == null) return null;
      final entries = paymentEntries;
      final check = PosPaymentCheck.evaluate(chargeTotal, entries, exponent: Money.exponent);
      final cashEntries = entries.where((e) => e.method == PosPaymentMethod.cash).toList();
      final tenders = <({String method, double amount, String? reference})>[];
      // what each tender covered: non-cash exactly as entered, cash = the rest of the total (the overage is change)
      var remaining = chargeTotal;
      for (final e in entries.where((e) => e.method != PosPaymentMethod.cash)) {
        tenders.add((method: e.method, amount: e.amount, reference: null));
        remaining -= e.amount;
      }
      if (cashEntries.isNotEmpty) tenders.add((method: PosPaymentMethod.cash, amount: remaining < 0 ? 0 : remaining, reference: null));
      final receipt = ReceiptData.forOfflineSale(
        provisionalNumber: number,
        madeAt: _pendingAt ?? DateTime.now(),
        settings: settings.value,
        currency: Money.currency,
        exponent: Money.exponent,
        items: [for (final c in cartItems) (name: c.displayName, qty: c.quantity.value, unitPrice: c.unitPrice)],
        subtotal: subtotal,
        discount: discountValue,
        taxLabel: taxValue > 0 ? 'Tax ($taxLabel)' : null,
        tax: taxValue,
        total: chargeTotal,
        payments: tenders,
        cashTendered: cashEntries.isEmpty ? null : cashEntries.fold<double>(0, (a, e) => a + e.amount),
        change: check.change,
        cashier: await AppPreferences.getPosEmployeeName(),
        customer: customerController.text,
      );
      await sync.saveOfflineReceipt(key, receipt);
      return receipt;
    } catch (e) {
      debugPrint('offline receipt: $e');
      return null;
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
    final byLine = quote.lines.length == cartItems.length; // the server answers line by line, in the cart's order
    for (var i = 0; i < cartItems.length; i++) {
      final item = cartItems[i];
      if (item.isCustom) continue;
      // G4.5: a line priced with options or a price book takes the server's unit price as is (the list price stays the variant's)
      if (byLine && quote.lines[i].priced) {
        item.serverUnitPrice = quote.lines[i].price;
        continue;
      }
      item.serverUnitPrice = null;
      final price = item.variant == null ? null : (byLine ? quote.lines[i].price : quote.unitPrices[item.variant!.variantId]);
      if (price != null && price != item.variant!.price) {
        cartItems[i] = CartItem(product: item.product, variant: item.variant!.withPrice(price), qty: item.quantity.value, modifiers: item.modifiers, bookUnitPrice: item.bookUnitPrice);
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

  // ── G2.4: server calls with coupon / manager approval ─────────────────────
  // The extra named arguments are only passed when there is something to say, so a sale without a coupon or an approver is
  // exactly the call it always was.
  Future<({PosQuote? quote, String? message, String? code})> _quoteCart(int? version) {
    final coupon = appliedCoupon.value?.code;
    if (coupon == null) {
      return _posRepo.quoteSale(
        storeId: storeId.value,
        items: _buildItems(),
        discountType: redeemValueMajor > 0 ? 'amount' : (isPercentDiscount.value ? 'percent' : 'amount'),
        discountValue: redeemValueMajor > 0 ? redeemValueMajor : _rawDiscountInput, // a redemption prices exactly like a flat discount
        settingsVersion: version,
        priceBookId: priceBook.value?.id,
        customerId: selectedCustomer.value?.id,
      );
    }
    return _posRepo.quoteSale(storeId: storeId.value, items: _buildItems(), settingsVersion: version, couponCode: coupon, priceBookId: priceBook.value?.id, customerId: selectedCustomer.value?.id);
  }

  Future<({bool success, PosSaleModel? sale, String? message, bool queued})> _sendSale({
    required String status,
    required double clientTotal,
    int? settingsVersion,
    DateTime? clientCreatedAt,
    String? idempotencyKey,
    required String paymentMethod,
    List<Map<String, dynamic>>? payments,
    double? amountTendered,
    String? paymentReference,
    String? approver,
    bool withCoupon = true,
  }) {
    final coupon = withCoupon ? appliedCoupon.value?.code : null;
    // G3.2: only a sale with a line the manager approved for expired stock carries the manager's token for it
    final expiredToken = cartItems.any((i) => i.sellExpired.value) ? _expiredApproverToken : null;
    final redeem = redeemPointsEffective;
    final name = customerController.text.trim().isEmpty ? 'Walk-in' : customerController.text.trim();
    if (coupon == null && approver == null && expiredToken == null && redeem == 0) {
      return _posRepo.createSale(
        storeId: storeId.value,
        sessionId: sessionId.value,
        registerId: registerId.value,
        employeeId: employeeId.value,
        items: _buildItems(),
        discountType: isPercentDiscount.value ? 'percent' : 'amount',
        discountValue: _rawDiscountInput,
        clientTotal: clientTotal,
        settingsVersion: settingsVersion,
        clientCreatedAt: clientCreatedAt,
        idempotencyKey: idempotencyKey,
        paymentMethod: paymentMethod,
        payments: payments,
        amountTendered: amountTendered,
        paymentReference: paymentReference,
        customerName: name,
        customerId: selectedCustomer.value?.id,
        notes: _buildNotes(),
        status: status,
        priceBookId: priceBook.value?.id,
      );
    }
    return _posRepo.createSale(
      storeId: storeId.value,
      sessionId: sessionId.value,
      registerId: registerId.value,
      employeeId: employeeId.value,
      items: _buildItems(),
      discountType: coupon == null ? (isPercentDiscount.value ? 'percent' : 'amount') : null,
      discountValue: coupon == null ? _rawDiscountInput : null,
      clientTotal: clientTotal,
      settingsVersion: settingsVersion,
      clientCreatedAt: clientCreatedAt,
      idempotencyKey: idempotencyKey,
      paymentMethod: paymentMethod,
      payments: payments,
      amountTendered: amountTendered,
      paymentReference: paymentReference,
      customerName: name,
      customerId: selectedCustomer.value?.id,
      notes: _buildNotes(),
      status: status,
      couponCode: coupon,
      approverToken: approver,
      expiredApproverToken: expiredToken,
      redeemPoints: redeem > 0 ? redeem : null,
      priceBookId: priceBook.value?.id,
    );
  }

  /// Sends the sale; when the server says a custom item needs a manager (it alone knows the store's limit), asks for a manager
  /// PIN once and sends it again with that manager's token. Nothing about the limit is decided on this device.
  Future<({bool success, PosSaleModel? sale, String? message, bool queued})> _withApproval(
    Future<({bool success, PosSaleModel? sale, String? message, bool queued})> Function(String? approver) send,
  ) async {
    var result = await send(_approverToken);
    if (!result.success && !result.queued && _posRepo.lastErrorCode == 'CUSTOM_ITEM_NEEDS_MANAGER') {
      final token = await ManagerApproval.request(reason: 'A manager must approve the custom item on this sale.', repository: _posRepo);
      if (token == null) return result;
      _approverToken = token;
      result = await send(token);
    }
    return result;
  }

  // ── G3.2: expired stock ───────────────────────────────────────────────────
  final RxBool isApprovingExpired = false.obs;

  /// The cashier asks to sell EXPIRED units of a line (the server said the sellable units do not cover the quantity). A manager types
  /// their PIN; their token rides with the sale and the line is marked. Online only — an offline sale is never sent `sellExpired`.
  Future<bool> approveSellExpired(CartItem item) async {
    if (isApprovingExpired.value || !_online) return false;
    final p = item.lotPreview.value;
    if (p == null || !p.needsExpiredOverride) return false;
    isApprovingExpired.value = true;
    try {
      final token = await _approval(reason: 'Selling expired stock needs a manager\'s approval.', repository: _posRepo);
      if (token == null) return false;
      _expiredApproverToken = token;
      item.sellExpired.value = true;
      _onCartEdited();
      return true;
    } finally {
      isApprovingExpired.value = false;
    }
  }

  /// Takes the approval back (the sale will then use only sellable units, or be refused for stock).
  void withdrawSellExpired(CartItem item) {
    item.sellExpired.value = false;
    _onCartEdited();
  }

  // ── G2.4: custom item ─────────────────────────────────────────────────────
  /// Adds a custom line. [price] is in the store's currency; the server re-prices, audits it and decides whether a manager must
  /// approve (at Charge). Guarded against a double tap.
  bool addCustomItem({required String name, required double price, int qty = 1, String taxCategory = 'standard', String note = ''}) {
    final n = name.trim();
    if (n.isEmpty || price <= 0 || qty < 1) return false;
    if (isAddingCustomItem.value) return false;
    isAddingCustomItem.value = true;
    try {
      cartItems.add(CartItem.custom(id: DateTime.now().microsecondsSinceEpoch.toString(), name: n, price: price, qty: qty, taxCategory: taxCategory, note: note.trim()));
      cartItems.refresh();
      return true;
    } finally {
      // released on the next frame, so a second tap on the same frame is swallowed
      Future.microtask(() => isAddingCustomItem.value = false);
    }
  }

  /// The total as the server prices a HELD sale: with no coupon applied.
  double get _totalIgnoringCoupon => PosTotals.compute(
        [for (final i in cartItems) (price: i.unitPrice, qty: i.quantity.value, taxable: i.isTaxable)],
        exponent: Money.exponent,
        percentDiscount: isPercentDiscount.value,
        discountInput: appliedCoupon.value != null ? 0 : _rawDiscountInput,
        taxRate: taxRate,
      ).total;

  /// What resuming the last held sale said about its coupon (null = nothing to say). Shown as a message and kept for the UI / tests.
  final RxnString heldCouponNotice = RxnString();

  /// A held sale kept a coupon CODE: check it again now. Still good → applied; no longer valid → removed, with the reason and the new total.
  Future<void> _revalidateHeldCoupon(String code) async {
    heldCouponNotice.value = null;
    final err = await applyCoupon(code);
    if (err != null || appliedCoupon.value == null) {
      appliedCoupon.value = null;
      final msg = 'The coupon $code can no longer be used${err == null ? '' : ' — $err'}. The total is now ${Money.format(total)}.';
      heldCouponNotice.value = msg;
      CustomAppSnackbar.warning(msg);
    }
  }

  // ── G2.4: coupon ──────────────────────────────────────────────────────────
  /// Checks [code] with the server for this cart (a live check — coupons are online-only). Returns null on success, else the
  /// message to show. Ignored while a check is already running (double-submit protection).
  Future<String?> applyCoupon(String code) async {
    final c = code.trim();
    if (c.isEmpty) return 'Enter a coupon code';
    if (isApplyingCoupon.value) return null;
    if (!hasItems) return 'Add items before applying a coupon';
    if (_rawDiscountInput > 0) return 'Remove the discount first — a coupon and a discount cannot be combined';
    if (!_online) return 'Coupons need a connection to check — try again when online, or charge without it';
    isApplyingCoupon.value = true;
    try {
      final q = await _posRepo.quoteSale(storeId: storeId.value, items: _buildItems(), settingsVersion: settings.value?.settingsVersion, couponCode: c, priceBookId: priceBook.value?.id, customerId: selectedCustomer.value?.id);
      if (q.quote?.coupon != null) {
        appliedCoupon.value = q.quote!.coupon;
        return null;
      }
      return q.message ?? 'That coupon could not be checked — try again';
    } finally {
      isApplyingCoupon.value = false;
    }
  }

  void removeCoupon() => appliedCoupon.value = null;

  // ── Hold sale ─────────────────────────────────────────────────────────────
  Future<void> holdSale() async {
    if (isChargingOrHolding.value) return;
    if (!hasItems) return;
    if (!_hasValidSession()) return;
    if (isDiscountBlocked) {
      CustomAppSnackbar.warning('Only managers can apply a discount.');
      return;
    }
    isChargingOrHolding.value = true;
    try {
      // a held sale keeps the coupon CODE (not a reservation): the server prices the held sale WITHOUT it, and the code is checked again
      // when the sale is resumed — so the total sent here is the one without the coupon
      final result = await _withApproval(
        (approver) => _sendSale(
          status: 'held',
          clientTotal: _totalIgnoringCoupon,
          settingsVersion: settings.value?.settingsVersion,
          paymentMethod: selectedPayment.value,
          approver: approver,
        ),
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

  /// A short tap in the hand (and the system click) when a scan put a line in the cart.
  void _scanFeedback() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  // ── Barcode scan → add straight to cart ──────────────────────────────────
  /// How long the last scan took from the scanner's event to the line being in the cart (ms) — measured, shown by the acceptance test.
  int? lastScanMs;

  Future<void> addProductByBarcode(String barcode) async {
    if (storeId.value.isEmpty || barcode.trim().isEmpty) return;
    final watch = Stopwatch()..start();
    final code = barcode.trim();
    // 1) the catalogue already on this device: no network, so the line is added (and the feedback given) at once
    for (final p in allProducts) {
      final v = p.variants.firstWhereOrNull((v) => (v.barcode ?? '') == code);
      if (v != null && p.inStock) {
        addToCart(p, v);
        _scanFeedback();
        lastScanMs = watch.elapsedMilliseconds;
        return;
      }
    }
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
      _scanFeedback();
      lastScanMs = watch.elapsedMilliseconds;
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
      final line = CartItem(
        product: product,
        variant: variant,
        qty: item.qty,
        modifiers: item.modifiers,
        // G4.5: the held price of a line priced with options or a book is the server's (re-priced when the sale is completed)
        serverUnitPrice: item.modifiers.isNotEmpty || item.basePriceMinor != null ? item.price : null,
      );
      cartItems.add(line);
      _lots.request(line);
    }
    cartItems.refresh();
    customerController.text = sale.customerName == 'Walk-in'
        ? ''
        : sale.customerName;
    if (sale.customerId != null && sale.customerId!.isNotEmpty) {
      selectedCustomer.value = CustomerModel(id: sale.customerId!, name: sale.customerName);
      saleCustomer.attach(PosCustomer(id: sale.customerId!, kind: 'pos', name: sale.customerName), null);
    }
    noteController.text = sale.notes;
    final held = sale.heldCouponCode;
    heldCouponNotice.value = null;
    if (held != null && held.isNotEmpty) unawaited(_revalidateHeldCoupon(held));
  }

  PosProductModel _productFromSaleItemSnapshot(PosSaleItemModel item) {
    // the line name carries the options ("Tea (Large)"); the cart adds them back from the line's modifiers
    final suffix = ChosenModifier.suffix(item.modifiers);
    return PosProductModel(
      productId: item.productId,
      name: suffix.isNotEmpty && item.name.endsWith(suffix) ? item.name.substring(0, item.name.length - suffix.length) : item.name,
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
          (c) => c.isCustom
              ? <String, dynamic>{
                  'isCustom': true,
                  'customName': c.product.name,
                  'taxCategory': c.taxCategory,
                  if (c.customNote.isNotEmpty) 'customNote': c.customNote,
                  'qty': c.quantity.value,
                  'unitPrice': c.unitPrice,
                }
              : {
            'productId': c.product.productId,
            if (c.variant != null) 'variantId': c.variant!.variantId,
            'qty': c.quantity.value,
            if (c.sellExpired.value) 'sellExpired': true,
            if (c.modifiers.isNotEmpty) 'modifiers': ChosenModifier.toRequest(c.modifiers),
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

  /// The words for a refused sale: the server's machine code first (G3.2 / G3.3 rules), else the older message matching.
  String _saleError(String? message) {
    final code = _posRepo.lastErrorCode;
    if (code == 'POS_APPROVAL_REQUIRED' || code == 'EXPIRED_LOT_APPROVAL_REQUIRED') {
      // the approval did not count (expired / not a manager): take it back so the cashier asks again
      for (final i in cartItems) {
        i.sellExpired.value = false;
      }
      _expiredApproverToken = null;
      return 'A manager must approve selling expired stock. Ask the manager again.';
    }
    if (code != null && customerCodes.contains(code)) return customerErrorMessage(code);
    if (code != null && catalogSaleCodes.contains(code)) return catalogErrorMessage(code, message: message);
    return _friendlyError(message ?? '');
  }

  /// G4.5: server codes of the price book / option rules of a sale (explained by [catalogErrorMessage]).
  static const catalogSaleCodes = {'PRICE_BOOK_NOT_ACTIVE', 'MODIFIER_REQUIRED', 'MODIFIER_TOO_MANY', 'MODIFIER_OPTION_UNKNOWN', 'MODIFIER_NOT_ON_PRODUCT', 'MODIFIER_GROUP_TWICE', 'PRICE_BELOW_ZERO'};

  /// Server codes of the store-credit / points rules of a sale (explained by [customerErrorMessage]).
  static const customerCodes = {
    'STORE_CREDIT_ONLINE_ONLY', 'CUSTOMER_REQUIRED', 'STORE_CREDIT_NOT_ENABLED', 'STORE_CREDIT_INSUFFICIENT',
    'LOYALTY_ONLINE_ONLY', 'LOYALTY_NOT_ENABLED', 'LOYALTY_WITH_DISCOUNT', 'LOYALTY_EXCEEDS_SALE', 'LOYALTY_INSUFFICIENT_POINTS',
  };

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
