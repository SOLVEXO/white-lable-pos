import 'dart:async';

import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosProductsController extends GetxController {
  final _posRepo = PosRepository();

  final RxBool isLoading = false.obs;
  final RxString searchText = ''.obs;
  final TextEditingController searchController = TextEditingController();
  final RxList<PosProductModel> _allProducts = <PosProductModel>[].obs;

  String _storeId = '';
  Timer? _debounce;

  List<PosProductModel> get filteredProducts => _allProducts;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => _load());
  }

  Future<void> _loadContext() async {
    _storeId = await AppPreferences.getStoreId() ?? '';
  }

  Future<void> _load() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    try {
      final result = await _posRepo.getProducts(_storeId, limit: 200);
      _allProducts.assignAll(result.items);
    } finally {
      isLoading.value = false;
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
    super.onClose();
  }
}
