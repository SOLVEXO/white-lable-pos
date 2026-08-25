import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';
import 'package:get/get.dart';

class PosSaleDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosSaleDetailController>(() => PosSaleDetailController());
  }
}
