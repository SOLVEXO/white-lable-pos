import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Shared helpers of the G3.3 customer controllers.
Future<String> customerStoreId(String? override) => invStoreId(override);

final RxBool _assumedOnline = true.obs;

/// The till's connectivity as an observable (so an `Obx` always has something to watch). With no status service the till is assumed online.
RxBool customersOnlineRx() => Get.isRegistered<NetworkStatusService>() ? Get.find<NetworkStatusService>().isOnline : _assumedOnline;

/// Can this till reach the server right now?
bool customersOnline() => customersOnlineRx().value;

/// A first guess of the role BEFORE the server answers; the server enforces every rule.
Future<bool> customerGuessCanManage() async => InvRole.canManage(await invGuessRole());
