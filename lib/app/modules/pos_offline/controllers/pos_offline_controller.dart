import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';

/// "Offline mode" screen state: whether the till can reach the network, how many sales wait to sync, when it last synced.
/// Read-only apart from "Sync now". Both services are optional (a till that never registered them shows the defaults).
class PosOfflineController extends GetxController {
  PosOfflineController({NetworkStatusService? network, PendingSaleSyncService? sync})
      : _network = network ?? (Get.isRegistered<NetworkStatusService>() ? Get.find<NetworkStatusService>() : null),
        _sync = sync ?? (Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>() : null);

  final NetworkStatusService? _network;
  final PendingSaleSyncService? _sync;

  bool get isOnline => _network?.isOnline.value ?? true;
  int get pending => _sync?.pendingCount.value ?? 0;
  int get failed => _sync?.failedCount.value ?? 0;
  bool get isSyncing => _sync?.isSyncing.value ?? false;
  DateTime? get lastSync => _sync?.lastSuccessfulSync.value;

  /// What a sale can and cannot do without a connection. The server enforces the same split: a Raast QR payment needs the provider's
  /// live confirmation, and a coupon needs a live check (its usage is counted inside the sale on the server).
  static const worksOffline = <String>[
    'Cash sales',
    'Card sales recorded on the card terminal',
    'Held sales (saved on this device)',
    'Your sales are queued and sync on their own when the connection returns',
  ];
  static const needsConnection = <String>[
    'Raast QR payments',
    'Coupons (they need a live check)',
    'Refunds and voids',
    'The digital receipt QR (it appears once the sale syncs)',
  ];

  Future<void> syncNow() async {
    await _sync?.syncNow(ignoreBackoff: true);
  }

  /// A change of any of the observed values rebuilds an `Obx` that calls this.
  void watch() {
    _network?.isOnline.value;
    _sync?.pendingCount.value;
    _sync?.failedCount.value;
    _sync?.isSyncing.value;
    _sync?.lastSuccessfulSync.value;
  }
}
