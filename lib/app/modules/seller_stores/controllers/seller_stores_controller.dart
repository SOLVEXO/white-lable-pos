import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
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
}

// ── Controller ─────────────────────────────────────────────────────────────────

class SellerStoresController extends GetxController {
  final _repo = SellerRepository();

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
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> refreshStores() => _loadStores();

  /// Saves the selected store ID so the rest of the seller app can use it,
  /// then navigates to the seller home (dashboard).
  Future<void> openStore(SellerStore store) async {
    await AppPreferences.saveStoreId(store.id);
    await AppPreferences.saveStoreName(store.name);
    Get.offAllNamed(Routes.sellerHome);
  }

  void createNewStore() => Get.toNamed(Routes.sellerOnboarding);
}
