import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/app/data/repositories/store_locations_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class SellerPosLocationsController extends GetxController {
  SellerPosLocationsController({StoreLocationsRepository? storeLocationsRepository})
      : _repo = storeLocationsRepository ?? StoreLocationsRepository();

  final StoreLocationsRepository _repo;

  String storeId = '';

  final RxBool isLoading = true.obs;
  final RxBool isSaving = false.obs;
  final RxList<StoreLocationModel> locations = <StoreLocationModel>[].obs;
  final Rx<StoreLocationsOverviewModel> overview =
      Rx<StoreLocationsOverviewModel>(StoreLocationsOverviewModel.empty);

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    storeId = await AppPreferences.getStoreId() ?? '';
    if (storeId.isEmpty) {
      debugPrint('⚠️ SellerPosLocationsController: no storeId in prefs');
      isLoading.value = false;
      return;
    }
    await loadData();
  }

  Future<void> loadData() async {
    if (storeId.isEmpty) return;
    isLoading.value = true;
    await refreshData();
    isLoading.value = false;
  }

  /// Reload without toggling the full-screen loader (used by pull-to-refresh).
  Future<void> refreshData() async {
    if (storeId.isEmpty) return;
    locations.assignAll(await _repo.getLocations(storeId));
    overview.value = await _repo.getOverview(storeId);
  }

  /// Per-branch stats for a location, or null if the overview has no row for it.
  LocationOverviewStat? statFor(String locationId) {
    for (final row in overview.value.byLocation) {
      if (row.locationId == locationId) return row;
    }
    return null;
  }

  Future<bool> createLocation({
    required String name,
    String? addressLine1,
    String? city,
    String? phone,
  }) async {
    isSaving.value = true;
    final created = await _repo.createLocation(
      storeId,
      name: name,
      addressLine1: addressLine1,
      city: city,
      phone: phone,
    );
    isSaving.value = false;
    if (created != null) {
      locations.add(created);
      _reloadOverview();
      return true;
    }
    return false;
  }

  Future<bool> updateLocation(
    StoreLocationModel existing, {
    String? name,
    String? addressLine1,
    String? city,
    String? phone,
    String? status,
  }) async {
    isSaving.value = true;
    final updated = await _repo.updateLocation(
      storeId,
      existing.id,
      name: name,
      addressLine1: addressLine1,
      city: city,
      phone: phone,
      status: status,
    );
    isSaving.value = false;
    if (updated != null) {
      final index = locations.indexWhere((l) => l.id == existing.id);
      if (index != -1) locations[index] = updated;
      _reloadOverview();
      return true;
    }
    return false;
  }

  Future<bool> archiveLocation(StoreLocationModel location, {bool force = false}) async {
    final ok = await _repo.archiveLocation(storeId, location.id, force: force);
    if (ok) await refreshData();
    return ok;
  }

  Future<void> _reloadOverview() async {
    overview.value = await _repo.getOverview(storeId);
  }
}
