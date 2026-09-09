import 'dart:async';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';

// ── Display model (consumed by StoreCard widget) ───────────────────────────────

class SellerStore {
  final String id;
  final String name;
  final String category;
  final String initials;
  final String logo;
  final String plan;
  final String sellerType;
  final bool isActive;
  final String status;
  final int productCount;
  final double totalSales;

  /// Null until `PosSubscriptionRepository.getStatus` returns for this
  /// store (fetched separately, after the store list itself renders — see
  /// SellerStoresController._loadSubscriptionStatuses). Not to be confused
  /// with [status], the store's own business status.
  final PosSubscriptionStatusValue? posSubscriptionStatus;

  const SellerStore({
    required this.id,
    required this.name,
    required this.category,
    required this.initials,
    this.logo = '',
    this.plan = '',
    this.sellerType = '',
    this.isActive = true,
    this.status = '',
    this.productCount = 0,
    this.totalSales = 0,
    this.posSubscriptionStatus,
  });

  factory SellerStore.fromModel(StoreModel m) => SellerStore(
    id: m.id,
    name: m.name,
    // Use sellerTypeLabel as subtitle until a category-name lookup is available
    category: m.sellerTypeLabel,
    initials: m.initials,
    logo: m.logo,
    plan: m.plan,
    sellerType: m.sellerType,
    isActive: m.isActive,
    status: m.status,
    productCount: m.productCount,
    totalSales: m.totalSalesUSD,
  );

  SellerStore copyWith({PosSubscriptionStatusValue? posSubscriptionStatus}) =>
      SellerStore(
        id: id,
        name: name,
        category: category,
        initials: initials,
        logo: logo,
        plan: plan,
        sellerType: sellerType,
        isActive: isActive,
        status: status,
        productCount: productCount,
        totalSales: totalSales,
        posSubscriptionStatus:
            posSubscriptionStatus ?? this.posSubscriptionStatus,
      );
}

// ── Controller ─────────────────────────────────────────────────────────────────

class SellerStoresController extends GetxController {
  SellerStoresController({
    SellerRepository? sellerRepository,
    PosSubscriptionRepository? posSubscriptionRepository,
  }) : _repo = sellerRepository ?? SellerRepository(),
       _subscriptionRepo =
           posSubscriptionRepository ?? PosSubscriptionRepository();

  final SellerRepository _repo;
  final PosSubscriptionRepository _subscriptionRepo;

  final RxBool isLoading = true.obs;
  final RxList<SellerStore> stores = <SellerStore>[].obs;

  // Profile — populated from preferences first, enriched from API response
  final RxString userName = ''.obs;
  final RxString userEmail = ''.obs;
  final RxString userInitials = 'S'.obs;
  final RxString userProfileImage = ''.obs;

  int get storeCount => stores.length;
  int get totalProducts => stores.fold(0, (sum, s) => sum + s.productCount);
  double get totalRevenue => stores.fold(0.0, (sum, s) => sum + s.totalSales);

  @override
  void onInit() {
    super.onInit();
    _loadProfileFromPrefs();
    _loadStores();
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<void> _loadProfileFromPrefs() async {
    final name = await AppPreferences.getUserName();
    final email = await AppPreferences.getUserEmail();
    final image = await AppPreferences.getProfileImage();
    if (name != null && name.trim().isNotEmpty) {
      userName.value = name.trim();
      _updateInitials(name.trim());
    }
    if (email != null) userEmail.value = email;
    if (image != null && image.isNotEmpty) userProfileImage.value = image;
  }

  void _updateInitials(String name) {
    final parts = name.trim().split(' ');
    userInitials.value = (parts.length >= 2)
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : 'S';
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _loadStores() async {
    isLoading.value = true;

    final models = await _repo.getMyStores();

    if (models.isEmpty) {
      isLoading.value = false;
      Get.offAllNamed(Routes.sellerOnboarding);
      return;
    }

    stores.assignAll(models.map(SellerStore.fromModel));

    // Enrich profile display from API if prefs were empty
    final first = models.first;
    if (userName.value.isEmpty && first.sellerName.isNotEmpty) {
      userName.value = first.sellerName;
      _updateInitials(first.sellerName);
    }
    if (userEmail.value.isEmpty && first.sellerEmail.isNotEmpty) {
      userEmail.value = first.sellerEmail;
    }

    // On first launch, default the active store to the first one returned
    final savedId = await AppPreferences.getStoreId();
    if (savedId == null || savedId.isEmpty) {
      await AppPreferences.saveStoreId(first.id);
      await AppPreferences.saveStoreName(first.name);
    }

    isLoading.value = false;

    // Fire-and-forget: badges pop in once each store's status resolves,
    // rather than delaying the list itself. Runs in parallel (Future.wait),
    // not sequential, so this is one round of concurrent requests — but it
    // is still one request per store (no bulk-status endpoint exists yet).
    // Flag for a bulk `GET /pos-subscriptions?storeIds=...` if a seller with
    // many stores notices this being slow.
    unawaited(_loadSubscriptionStatuses());
  }

  Future<void> _loadSubscriptionStatuses() async {
    final ids = stores.map((s) => s.id).toList();
    if (ids.isEmpty) return;
    final results = await Future.wait(ids.map(_subscriptionRepo.getStatus));
    for (var i = 0; i < stores.length; i++) {
      if (stores[i].id != ids[i])
        continue; // list changed underneath us — skip stale write
      stores[i] = stores[i].copyWith(posSubscriptionStatus: results[i].status);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> refreshStores() => _loadStores();

  /// Saves the selected store ID so the rest of the seller app can use it,
  /// then navigates to the seller home (dashboard).
  Future<void> openStore(SellerStore store) async {
    await AppPreferences.saveStoreId(store.id);
    await AppPreferences.saveStoreName(store.name);
    Get.toNamed(Routes.sellerHome);
  }

  void createNewStore() => Get.toNamed(Routes.sellerOnboarding);
}
