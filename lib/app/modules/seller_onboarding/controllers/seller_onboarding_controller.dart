import 'dart:io';

import 'package:solvexo_pos/app/components/app_image_picker.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/repositories/category_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/repositories/upload_repository.dart';
import 'package:solvexo_pos/app/modules/category/models/category_model.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

enum OnboardingStep { storeInfo, sellerType, whatYouSell, goLive }

enum SellerTypeOption {
  creator,
  educator,
  retailer,
  brandBusiness,
  freelancer,
  mixOfAbove,
}

enum WhatYouSellOption {
  physicalProducts,
  digitalDownloads,
  educationalResources,
  servicesBookings,
  subscriptions,
  inPersonPos,
}

// ── Data models ────────────────────────────────────────────────────────────────

class ActivatedTool {
  final String name;
  final Color textColor;
  final Color bgColor;
  const ActivatedTool(this.name, this.textColor, this.bgColor);
}

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

class WhatYouSellData {
  final WhatYouSellOption option;
  final String emoji;
  final String name;
  final String description;
  final List<ActivatedTool> tools;
  const WhatYouSellData({
    required this.option,
    required this.emoji,
    required this.name,
    required this.description,
    required this.tools,
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

final kWhatYouSell = [
  WhatYouSellData(
    option: WhatYouSellOption.physicalProducts,
    emoji: '📦',
    name: 'Physical Products',
    description: 'Ship items to customers',
    tools: [
      ActivatedTool(
        'Inventory Manager',
        AppColors.darkGreen,
        AppColors.greenContainerInnerColor,
      ),
      ActivatedTool('Shipping Manager', AppColors.iosBlue, AppColors.lightBlue),
    ],
  ),
  WhatYouSellData(
    option: WhatYouSellOption.digitalDownloads,
    emoji: '💾',
    name: 'Digital Downloads',
    description: 'PDFs, files, audio, video',
    tools: [
      ActivatedTool(
        'Digital Delivery',
        AppColors.purpleColor,
        AppColors.lightPurple,
      ),
    ],
  ),
  WhatYouSellData(
    option: WhatYouSellOption.educationalResources,
    emoji: '📚',
    name: 'Educational Resources',
    description: 'Worksheets, lesson plans',
    tools: [
      ActivatedTool(
        'Edu Resource Tools',
        AppColors.orange,
        AppColors.lightCameo,
      ),
      ActivatedTool(
        'AI Worksheet Builder',
        AppColors.primaryColor,
        AppColors.languageBg,
      ),
    ],
  ),
  WhatYouSellData(
    option: WhatYouSellOption.servicesBookings,
    emoji: '📋',
    name: 'Services / Bookings',
    description: 'Appointments and packages',
    tools: [
      ActivatedTool(
        'Booking Calendar',
        AppColors.accepted,
        AppColors.acceptedBg,
      ),
    ],
  ),
  WhatYouSellData(
    option: WhatYouSellOption.subscriptions,
    emoji: '🔄',
    name: 'Subscriptions',
    description: 'Recurring membership access',
    tools: [
      ActivatedTool('Subscriptions', AppColors.grey, AppColors.background),
    ],
  ),
  WhatYouSellData(
    option: WhatYouSellOption.inPersonPos,
    emoji: '🖥️',
    name: 'In-Person / POS',
    description: 'Sell at a physical location',
    tools: [
      ActivatedTool('POS Register', AppColors.red, AppColors.lightRed),
      ActivatedTool('AI Studio', AppColors.purpleColor, AppColors.lightPurple),
      ActivatedTool('Marketplace Listing', AppColors.blue, AppColors.lightBlue),
    ],
  ),
];

const kStoreCurrencies = ['PKR', 'USD'];

const kCountries = [
  'United States',
  'United Kingdom',
  'Canada',
  'Australia',
  'Germany',
  'France',
  'Netherlands',
  'UAE',
  'Saudi Arabia',
  'Malaysia',
  'Singapore',
  'Pakistan',
  'India',
  'South Africa',
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

extension WhatYouSellApi on WhatYouSellOption {
  String get apiValue {
    switch (this) {
      case WhatYouSellOption.physicalProducts:
        return 'physical_products';
      case WhatYouSellOption.digitalDownloads:
        return 'digital_downloads';
      case WhatYouSellOption.educationalResources:
        return 'educational_resources';
      case WhatYouSellOption.servicesBookings:
        return 'services_bookings';
      case WhatYouSellOption.subscriptions:
        return 'subscriptions';
      case WhatYouSellOption.inPersonPos:
        return 'in_person_pos';
    }
  }
}

extension WhatYouSellFromApi on String {
  /// Reverse of [WhatYouSellApi.apiValue] — used to rehydrate a store's saved
  /// `productTypes` (backend strings) back into [WhatYouSellOption]s for edit UIs.
  WhatYouSellOption? get asWhatYouSellOption =>
      WhatYouSellOption.values.firstWhereOrNull((o) => o.apiValue == this);
}

// ── Controller ─────────────────────────────────────────────────────────────────

class SellerOnboardingController extends GetxController {
  SellerOnboardingController({
    SellerRepository? sellerRepository,
    UploadRepository? uploadRepository,
    CategoryRepository? categoryRepository,
  }) : _sellerRepo = sellerRepository ?? SellerRepository(),
       _uploadRepo = uploadRepository ?? UploadRepository(),
       _categoryRepo = categoryRepository ?? CategoryRepository();

  // Starts at storeInfo — account creation is handled by AuthController
  final Rx<OnboardingStep> step = OnboardingStep.storeInfo.obs;
  final RxBool isSaving = false.obs;
  Rx<StoreModel?> createdStore = Rx(null);

  final SellerRepository _sellerRepo;
  final UploadRepository _uploadRepo;
  final CategoryRepository _categoryRepo;

  // Step 1 — Store Info
  final RxString storeName = ''.obs;
  final RxString storeCategory = ''.obs; // display name shown in the picker
  final RxString storeCategoryId =
      ''.obs; // real category _id sent to the backend
  final RxString storeDescription = ''.obs;
  final Rx<File?> logoFile = Rx<File?>(null);
  // Currency for pricing/payouts — required, immutable after store creation.
  final RxString storeCurrency = ''.obs;

  // Admin-curated main categories a seller picks from — sellers cannot
  // create these themselves, only choose one.
  final RxList<CategoryModel> mainCategories = <CategoryModel>[].obs;
  final RxBool isLoadingCategories = false.obs;

  // Step 2 — Seller Type (single-select)
  final Rx<SellerTypeOption?> sellerType = Rx(null);

  // Step 3 — What You Sell (multi-select)
  final RxSet<WhatYouSellOption> whatYouSell = <WhatYouSellOption>{}.obs;

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
      case OnboardingStep.whatYouSell:
        return whatYouSell.isNotEmpty;
      case OnboardingStep.goLive:
        return true;
    }
  }

  String get primaryButtonLabel {
    switch (step.value) {
      case OnboardingStep.sellerType:
        return canProceed ? 'Continue' : 'Select one to continue';
      case OnboardingStep.whatYouSell:
        return canProceed ? 'Continue' : 'Select at least one';
      case OnboardingStep.goLive:
        return 'Go to My Dashboard';
      default:
        return 'Continue';
    }
  }

  List<ActivatedTool> get activatedTools {
    final tools = <ActivatedTool>[];
    final seen = <String>{};
    for (final data in kWhatYouSell) {
      if (whatYouSell.contains(data.option)) {
        for (final t in data.tools) {
          if (seen.add(t.name)) tools.add(t);
        }
      }
    }
    return tools;
  }

  String get sellerTypeName {
    final t = kSellerTypes.firstWhereOrNull((t) => t.type == sellerType.value);
    return t?.name ?? '';
  }

  String get activatedProductsLabel {
    final names = kWhatYouSell
        .where((d) => whatYouSell.contains(d.option))
        .map((d) => d.name)
        .join(', ');
    return names.isEmpty ? 'None selected' : names;
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

  void toggleWhatYouSell(WhatYouSellOption option) {
    if (whatYouSell.contains(option)) {
      whatYouSell.remove(option);
    } else {
      whatYouSell.add(option);
    }
  }

  void pickLogo() {
    AppImagePicker.show(
      title: 'Store Logo',
      canRemove: logoFile.value != null,
      onPicked: (file) => logoFile.value = file,
      onRemove: () => logoFile.value = null,
    );
  }

  Future<void> _fetchMainCategories() async {
    isLoadingCategories.value = true;
    final trees = await _categoryRepo.getAllCategoryTrees();
    // `getAllCategoryTrees` returns only root categories already, but
    // filter defensively in case that ever changes.
    mainCategories.assignAll(trees.where((c) => c.isParent));
    isLoadingCategories.value = false;
  }

  Future<void> pickCategory() async {
    if (mainCategories.isEmpty && !isLoadingCategories.value) {
      await _fetchMainCategories();
    }
    if (mainCategories.isEmpty) {
      ToastUtil.showToast('No store categories are available right now.');
      return;
    }

    Get.bottomSheet(
      _PickerSheet(
        title: 'Store Category',
        items: mainCategories.map((c) => c.name).toList(),
        selected: storeCategory.value,
        onSelect: (name) {
          storeCategory.value = name;
          storeCategoryId.value =
              mainCategories.firstWhereOrNull((c) => c.name == name)?.id ?? '';
        },
      ),
      backgroundColor: Colors.transparent,
    );
  }

  void pickCurrency() {
    Get.bottomSheet(
      _PickerSheet(
        title: 'Store Currency',
        items: kStoreCurrencies,
        selected: storeCurrency.value,
        onSelect: (code) => storeCurrency.value = code,
      ),
      backgroundColor: Colors.transparent,
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
      productTypes: whatYouSell.map((o) => o.apiValue).toList(),
      description: storeDescription.value.trim(),
      categoryId: storeCategoryId.value.trim(),
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
      // The store is created 'pending' and stays invisible/unable to sell
      // until an admin approves it (see StoreService.createStore); business/
      // KYC verification is submitted on Seller Web, not in this app.
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
    _fetchMainCategories();
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
