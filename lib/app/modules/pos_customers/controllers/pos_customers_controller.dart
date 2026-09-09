import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/repositories/customer_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Browse-only list of the store's real past buyers (order stats included).
/// Not a picker — selecting a customer for a sale happens via the separate
/// PosCustomerPickerSheet reachable from checkout, keeping this screen's
/// only job "look at who's bought from us."
class PosCustomersController extends GetxController {
  PosCustomersController({CustomerRepository? customerRepository, PosRepository? posRepository})
      : _customerRepo = customerRepository ?? CustomerRepository(),
        _posRepo = posRepository ?? PosRepository();

  final CustomerRepository _customerRepo;
  final PosRepository _posRepo;

  final ScrollController scrollController = ScrollController();
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxString currencySymbol = '\$'.obs;
  final RxList<CustomerModel> customers = <CustomerModel>[].obs;

  String _storeId = '';
  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadCustomers());
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
    final settings = await _posRepo.getPosSettings(_storeId);
    final symbol = settings?.currencySymbol;
    if (symbol != null && symbol.trim().isNotEmpty) currencySymbol.value = symbol;
  }

  Future<void> loadCustomers() async {
    if (_storeId.isEmpty) return;
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _customerRepo.getStoreCustomers(_storeId, page: _page);
      customers.assignAll(result.items);
      _hasMore = result.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    try {
      final result = await _customerRepo.getStoreCustomers(_storeId, page: _page + 1);
      customers.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> refreshData() => loadCustomers();
}
