import 'dart:async';

import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosProductsController extends GetxController {
  PosProductsController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString searchText = ''.obs;
  final RxString currencySymbol = '\$'.obs;
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final RxList<PosProductModel> _allProducts = <PosProductModel>[].obs;

  static const _pageSize = 40;

  String _storeId = '';
  Timer? _debounce;
  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  List<PosProductModel> get filteredProducts => _allProducts;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) {
      _load();
      _loadSettings();
    });
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 300) {
        loadMore();
      }
    });
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  Future<void> _loadSettings() async {
    if (_storeId.isEmpty) return;
    final settings = await _posRepo.getPosSettings(_storeId);
    final symbol = settings?.currencySymbol;
    if (symbol != null && symbol.trim().isNotEmpty) currencySymbol.value = symbol;
  }

  Future<void> _load() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _posRepo.getProducts(_storeId, page: _page, limit: _pageSize);
      _allProducts.assignAll(result.items);
      _hasMore = result.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore || searchText.value.trim().isNotEmpty) return;
    isLoadingMore.value = true;
    try {
      final result = await _posRepo.getProducts(_storeId, page: _page + 1, limit: _pageSize);
      _allProducts.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  void onSearchChanged(String value) {
    searchText.value = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _load();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (_storeId.isEmpty) return;
      final results = await _posRepo.searchProducts(storeId: _storeId, q: value.trim());
      _allProducts.assignAll(results);
    });
  }

  Future<void> refreshData() async => _load();

  @override
  void onClose() {
    _debounce?.cancel();
    searchController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}
