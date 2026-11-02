import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';

class PosNeedsAttentionBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PosNeedsAttentionController>(() => PosNeedsAttentionController());
  }
}
