import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';

class PosHeldSalesController extends GetxController {
  PosHeldSalesController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxList<PosSaleModel> heldSales = <PosSaleModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxString processingId = ''.obs;

  // Reuses PosHomeController's already-loaded store currency symbol rather
  // than fetching settings again — this screen is only ever reached from
  // the POS terminal shell, where that controller is already alive.
  String get currencySymbol =>
      Get.isRegistered<PosHomeController>() ? Get.find<PosHomeController>().currencySymbol.value : '\$';

  String _sessionId = '';
  String _storeId   = '';

  @override
  void onInit() {
    super.onInit();
    _loadContext().then((_) => loadHeldSales());
  }

  Future<void> _loadContext() async {
    _sessionId = await AppPreferences.getPosSessionId() ?? '';
    _storeId   = await AppPreferences.getStoreId()      ?? '';
  }

  Future<void> loadHeldSales() async {
    isLoading.value = true;
    try {
      final results = await _posRepo.getHeldSales(
        storeId: _storeId,
        sessionId: _sessionId,
      );
      heldSales.assignAll(results);
    } catch (e) {
      CustomAppSnackbar.error('Failed to load held sales.');
    } finally {
      isLoading.value = false;
    }
  }

  // ── Resume: pop back to PosHome and load items into cart ─────────────────
  void resumeSale(PosSaleModel sale) {
    final homeCtrl = Get.find<PosHomeController>();
    homeCtrl.resumeHeldSale(sale);
    Get.back();
  }

  // ── Complete a held sale, optionally with a different payment method ──────
  Future<void> completeSale(PosSaleModel sale, {String? paymentMethod}) async {
    processingId.value = sale.id;
    try {
      final result = await _posRepo.completeSale(
        saleId: sale.id,
        paymentMethod: paymentMethod ?? sale.paymentMethod,
        notes: sale.notes,
      );
      if (!result.success) {
        CustomAppSnackbar.error(result.message ?? 'Could not complete sale.');
        return;
      }
      heldSales.remove(sale);
      CustomAppSnackbar.success('Sale completed!');
    } finally {
      processingId.value = '';
    }
  }

  // ── Discard held sale ─────────────────────────────────────────────────────
  Future<void> discardSale(PosSaleModel sale) async {
    processingId.value = sale.id;
    try {
      final ok = await _posRepo.discardSale(sale.id);
      if (ok) {
        heldSales.remove(sale);
        CustomAppSnackbar.success('Sale discarded.');
      } else {
        CustomAppSnackbar.error('Could not discard sale.');
      }
    } catch (e) {
      CustomAppSnackbar.error('Could not discard sale.');
    } finally {
      processingId.value = '';
    }
  }
}
