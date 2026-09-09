import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class PosStockActivityController extends GetxController {
  PosStockActivityController({InventoryRepository? inventoryRepository})
      : _inventoryRepo = inventoryRepository ?? InventoryRepository();

  final InventoryRepository _inventoryRepo;

  final ScrollController scrollController = ScrollController();
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxList<ActivityLogEntry> entries = <ActivityLogEntry>[].obs;

  String _storeId = '';
  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadEntries());
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 300) {
        loadMore();
      }
    });
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  Future<void> loadEntries() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _inventoryRepo.getStockActivity(_storeId, page: _page);
      entries.assignAll(result.items);
      _hasMore = result.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    try {
      final result = await _inventoryRepo.getStockActivity(_storeId, page: _page + 1);
      entries.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> refreshData() => loadEntries();
}
