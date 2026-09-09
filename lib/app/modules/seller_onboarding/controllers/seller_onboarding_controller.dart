import 'dart:io';

import 'package:solvexo_pos/app/components/app_image_picker.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/repositories/upload_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

enum OnboardingStep { storeInfo, sellerType, goLive }

enum SellerTypeOption {
  creator,
  educator,
  retailer,
  brandBusiness,
  freelancer,
  mixOfAbove,
}

// ── Data models ────────────────────────────────────────────────────────────────

class SellerTypeData {
  final SellerTypeOption type;
  final String emoji;
  final String name;
  final String description;
  const SellerTypeData({
    required this.type,
    required this.emoji,
    required this.name,
    required this.description,
  });
}

// ── Static data ────────────────────────────────────────────────────────────────

const kSellerTypes = [
  SellerTypeData(
    type: SellerTypeOption.creator,
    emoji: '🎨',
    name: 'Creator',
    description: 'Sell digital art, templates, fonts, music, presets',
  ),
  SellerTypeData(
    type: SellerTypeOption.educator,
    emoji: '📚',
    name: 'Educator',
    description: 'Worksheets, lesson plans, curriculum, assessments',
  ),
  SellerTypeData(
    type: SellerTypeOption.retailer,
    emoji: '🏪',
    name: 'Retailer',
    description: 'Physical goods, handmade products, branded items',
  ),
  SellerTypeData(
    type: SellerTypeOption.brandBusiness,
    emoji: '💼',
    name: 'Brand / Business',
    description: 'Run a full online store with inventory and POS',
  ),
  SellerTypeData(
    type: SellerTypeOption.freelancer,
    emoji: '💻',
    name: 'Freelancer',
    description: 'Offer services, bookings, or consulting packages',
  ),
  SellerTypeData(
    type: SellerTypeOption.mixOfAbove,
    emoji: '🌐',
    name: 'Mix of the above',
    description: 'I sell across multiple categories and formats',
  ),
];

// ── API value helpers ─────────────────────────────────────────────────────────

extension SellerTypeApi on SellerTypeOption {
  String get apiValue {
    switch (this) {
      case SellerTypeOption.creator:
        return 'creator';
      case SellerTypeOption.educator:
        return 'educator';
      case SellerTypeOption.retailer:
        return 'retailer';
      case SellerTypeOption.brandBusiness:
        return 'brand_business';
      case SellerTypeOption.freelancer:
        return 'freelancer';
      case SellerTypeOption.mixOfAbove:
        return 'mix_of_above';
    }
  }
}

// POS only ever sells physical, shippable goods — the app has no digital-
// delivery/booking/subscription flows, so onboarding no longer asks; this is
// the one and only `productTypes` value every store created here gets.
const kPosProductType = 'physical_products';

// ── Controller ─────────────────────────────────────────────────────────────────

class SellerOnboardingController extends GetxController {
  SellerOnboardingController({
    SellerRepository? sellerRepository,
    UploadRepository? uploadRepository,
  }) : _sellerRepo = sellerRepository ?? SellerRepository(),
       _uploadRepo = uploadRepository ?? UploadRepository();

  // Starts at storeInfo — account creation is handled by AuthController
  final Rx<OnboardingStep> step = OnboardingStep.storeInfo.obs;
  final RxBool isSaving = false.obs;
  Rx<StoreModel?> createdStore = Rx(null);

  final SellerRepository _sellerRepo;
  final UploadRepository _uploadRepo;

  // Step 1 — Store Info
  final RxString storeName = ''.obs;
  final RxString storeDescription = ''.obs;
  final Rx<File?> logoFile = Rx<File?>(null);
  // Currency for pricing/payouts — required, immutable after store creation.
  // Populated from the backend's admin-configurable enabled-currencies list
  // (see _fetchCurrencies), not a hardcoded set.
  final RxString storeCurrency = ''.obs;
  final RxList<String> availableCurrencies = <String>[].obs;
  final RxBool isLoadingCurrencies = false.obs;

  // Step 2 — Seller Type (single-select)
  final Rx<SellerTypeOption?> sellerType = Rx(null);

  // Text controllers
  late final TextEditingController storeNameCtrl;
  late final TextEditingController storeDescCtrl;

  // ── Computed ─────────────────────────────────────────────────────────────────

  bool get isFirstStep => step.value == OnboardingStep.storeInfo;
  bool get isLastStep => step.value == OnboardingStep.goLive;

  bool get canProceed {
    switch (step.value) {
      case OnboardingStep.storeInfo:
        return storeName.value.trim().isNotEmpty && storeCurrency.value.isNotEmpty;
      case OnboardingStep.sellerType:
        return sellerType.value != null;
      case OnboardingStep.goLive:
        return true;
    }
  }

  String get primaryButtonLabel {
    switch (step.value) {
      case OnboardingStep.sellerType:
        return canProceed ? 'Continue' : 'Select one to continue';
      case OnboardingStep.goLive:
        return 'Go to My Dashboard';
      default:
        return 'Continue';
    }
  }

  String get sellerTypeName {
    final t = kSellerTypes.firstWhereOrNull((t) => t.type == sellerType.value);
    return t?.name ?? '';
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  void goNext() {
    final idx = step.value.index;
    if (idx < OnboardingStep.values.length - 1) {
      step.value = OnboardingStep.values[idx + 1];
    }
  }

  void goBack() {
    final idx = step.value.index;
    if (idx > 0) {
      step.value = OnboardingStep.values[idx - 1];
    } else {
      Get.back();
    }
  }

  void selectSellerType(SellerTypeOption type) => sellerType.value = type;

  void pickLogo() {
    AppImagePicker.show(
      title: 'Store Logo',
      canRemove: logoFile.value != null,
      onPicked: (file) => logoFile.value = file,
      onRemove: () => logoFile.value = null,
    );
  }

  Future<void> _fetchCurrencies() async {
    isLoadingCurrencies.value = true;
    final currencies = await _sellerRepo.getEnabledCurrencies();
    availableCurrencies.assignAll(currencies);
    isLoadingCurrencies.value = false;

    if (storeCurrency.value.isEmpty) {
      // Pre-fill (never force) from the seller's IP-detected country, same
      // as the web onboarding wizard — only applied if that currency is
      // actually one of the admin-enabled ones just fetched.
      final suggested = await _sellerRepo.getSuggestedCurrency();
      if (suggested != null && availableCurrencies.contains(suggested)) {
        storeCurrency.value = suggested;
      }
    }
  }

  Future<void> pickCurrency() async {
    if (availableCurrencies.isEmpty && !isLoadingCurrencies.value) {
      await _fetchCurrencies();
    }
    if (availableCurrencies.isEmpty) {
      ToastUtil.showToast('No store currencies are available right now.');
      return;
    }

    Get.bottomSheet(
      _PickerSheet(
        title: 'Store Currency',
        items: availableCurrencies,
        selected: storeCurrency.value,
        onSelect: (code) => storeCurrency.value = code,
      ),
      backgroundColor: AppColors.transparent,
    );
  }

  Future<void> complete() async {
    if (isSaving.value) return;
    isSaving.value = true;

    // Upload logo first if one was selected, then pass the URL to createStore
    String? logoUrl;
    if (logoFile.value != null) {
      logoUrl = await _uploadRepo.uploadFile(logoFile.value!);
      if (logoUrl == null) {
        ToastUtil.showToast('Logo upload failed. Please try again.');
        isSaving.value = false;
        return;
      }
    }

    final store = await _sellerRepo.createStore(
      name: storeName.value.trim(),
      sellerType: sellerType.value?.apiValue ?? 'creator',
      productTypes: const [kPosProductType],
      description: storeDescription.value.trim(),
      logoUrl: logoUrl,
      baseCurrency: storeCurrency.value,
    );

    isSaving.value = false;

    if (store != null) {
      createdStore.value = store;
      await AppPreferences.saveStoreId(store.id);
      await AppPreferences.saveStoreName(store.name);
      // Local role is already set to 'seller' at login time (this app is
      // seller-only — see PosLoginController), so no role handling needed
      // here.
      // Self-serve activation is unconditional now (StoreService.createStore
      // hardcodes selfServeActivation = true) — the store is created
      // 'active' immediately, no admin review queue. Business/KYC
      // verification is submitted separately on Seller Web, not in this app.
      Get.offAllNamed(Routes.sellerHome);
    }
    // On failure, _sellerRepo already shows a toast — stay on screen.
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    storeNameCtrl = TextEditingController();
    storeDescCtrl = TextEditingController();
    _fetchCurrencies();
  }

  @override
  void onClose() {
    storeNameCtrl.dispose();
    storeDescCtrl.dispose();
    super.onClose();
  }
}

// ── Reusable picker bottom sheet ──────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  final String title;
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelect;

  const _PickerSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: CustomText(
              text: title,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.black,
            ),
          ),
          const Divider(height: 1, color: AppColors.lightGrey2),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 20,
                color: AppColors.lightGrey2,
              ),
              itemBuilder: (_, i) {
                final isSelected = items[i] == selected;
                return ListTile(
                  title: CustomText(
                    text: items[i],
                    fontSize: 15,
                    color: isSelected
                        ? AppColors.primaryColor
                        : AppColors.black,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          color: AppColors.primaryColor,
                          size: 18,
                        )
                      : null,
                  onTap: () {
                    onSelect(items[i]);
                    Get.back();
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
