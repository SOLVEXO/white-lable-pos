import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class PosSessionHistoryController extends GetxController {
  final _posRepo = PosRepository();

  final ScrollController scrollController = ScrollController();

  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxList<PosSessionModel> sessions = <PosSessionModel>[].obs;

  String _storeId = '';
  int _page = 1;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadSessions());
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
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

  Future<void> loadSessions() async {
    isLoading.value = true;
    _page = 1;
    try {
      final result = await _posRepo.getSessionHistory(storeId: _storeId, page: _page);
      sessions.assignAll(result.items);
      _hasMore = result.hasMore;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    try {
      final result = await _posRepo.getSessionHistory(storeId: _storeId, page: _page + 1);
      sessions.addAll(result.items);
      _page++;
      _hasMore = result.hasMore;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> refreshData() => loadSessions();

  void openReport(PosSessionModel session) => Get.toNamed(Routes.posSessionReport, arguments: session.id);
}
