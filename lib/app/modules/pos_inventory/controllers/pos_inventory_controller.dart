import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosInventoryController extends GetxController {
  PosInventoryController({InventoryRepository? inventoryRepository})
      : _inventoryRepo = inventoryRepository ?? InventoryRepository();

  final InventoryRepository _inventoryRepo;

  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool showLowStockOnly = false.obs;
  final RxBool isAdjusting = false.obs;
  final RxList<InventoryProductSummary> products = <InventoryProductSummary>[].obs;
  final RxList<LowStockItem> lowStockItems = <LowStockItem>[].obs;
  final Rx<InventoryStats?> stats = Rx(null);

  final ScrollController scrollController = ScrollController();
  final TextEditingController stockController = TextEditingController();

  String _storeId = '';
  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadInventory());
    scrollController.addListener(() {
      if (!showLowStockOnly.value &&
          scrollController.position.pixels >= scrollController.position.maxScrollExtent - 300) {
        loadMore();
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    stockController.dispose();
    super.onClose();
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  Future<void> loadInventory() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _inventoryRepo.getStoreInventory(_storeId, page: _page);
      products.assignAll(result.page.items);
      stats.value = result.stats;
      _hasMore = result.page.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    try {
      final result = await _inventoryRepo.getStoreInventory(_storeId, page: _page + 1);
      products.addAll(result.page.items);
      _page++;
      _hasMore = result.page.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> loadLowStock() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    try {
      final summary = await _inventoryRepo.getLowStockSummary(_storeId);
      lowStockItems.assignAll(summary?.items ?? []);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleLowStockOnly() async {
    showLowStockOnly.value = !showLowStockOnly.value;
    if (showLowStockOnly.value) {
      await loadLowStock();
    } else {
      await loadInventory();
    }
  }

  Future<void> refreshData() => showLowStockOnly.value ? loadLowStock() : loadInventory();

  // ── Adjust stock ──────────────────────────────────────────────────────
  /// The inventory list only has an aggregate stock figure across all of a
  /// product's variants — to adjust the right one, the product's actual
  /// variants are fetched first, then either the single variant is adjusted
  /// directly or the cashier picks which one (mirrors
  /// PosHomeController._showVariantSheet's pattern).
  Future<void> openAdjustStock(String productId, String productName) async {
    final variants = await _inventoryRepo.getProductVariants(productId);
    if (variants.isEmpty) {
      CustomAppSnackbar.error('Could not load stock details for this product.');
      return;
    }
    if (variants.length == 1) {
      _showAdjustDialog(productId, productName, variants.first);
    } else {
      _showVariantPicker(productId, productName, variants);
    }
  }

  void _showVariantPicker(String productId, String productName, List<InventoryVariant> variants) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomText(
              text: 'Select Variant — $productName',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(height: 12),
            ...variants.map((v) => GestureDetector(
              onTap: () {
                Get.back();
                _showAdjustDialog(productId, productName, v);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.lightGrey2),
                ),
                child: Row(children: [
                  Expanded(
                    child: CustomText(text: v.label, fontSize: AppFontSize.verySmall, color: AppColors.black2),
                  ),
                  CustomText(
                    text: '${v.stock} in stock',
                    fontSize: AppFontSize.tiny,
                    color: AppColors.iosGrey,
                  ),
                ]),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _showAdjustDialog(String productId, String productName, InventoryVariant variant) {
    stockController.text = '${variant.stock}';
    final ctx = Get.context;
    if (ctx == null) return;
    CustomConfirmDialog.show(
      ctx,
      title: 'Adjust Stock',
      confirmLabel: 'Save',
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            text: '$productName${variant.label.isNotEmpty && variant.label != productName ? ' — ${variant.label}' : ''}',
            fontSize: AppFontSize.verySmall,
            color: AppColors.iosGrey,
          ),
          const SizedBox(height: 4),
          CustomText(
            text: 'Current stock: ${variant.stock}',
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
          const SizedBox(height: 12),
          CustomTextField(
            controller: stockController,
            keyboardType: TextInputType.number,
            hintText: 'New quantity',
            isborder: true,
            fillColor: AppColors.background,
          ),
        ],
      ),
      onConfirm: () => _saveStockAdjustment(productId, variant.variantId),
    );
  }

  Future<void> _saveStockAdjustment(String productId, String variantId) async {
    final newStock = int.tryParse(stockController.text.trim());
    if (newStock == null || newStock < 0) {
      CustomAppSnackbar.warning('Enter a valid stock quantity.');
      return;
    }
    isAdjusting.value = true;
    try {
      final ok = await _inventoryRepo.updateVariantStock(
        productId: productId,
        variantId: variantId,
        stock: newStock,
      );
      if (ok) {
        CustomAppSnackbar.success('Stock updated.');
        await refreshData();
      }
    } finally {
      isAdjusting.value = false;
    }
  }
}
