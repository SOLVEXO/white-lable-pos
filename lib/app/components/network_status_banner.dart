import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Slim, app-wide status strip — wired into `MyApp`'s `builder:` in
/// main.dart so every screen gets it with one change. Reflects two things:
/// no network (see NetworkStatusService's doc comment on what "online"
/// means here) and/or sales still waiting in the local queue (see
/// PendingSaleSyncService) — most other actions still just fail with their
/// normal error message if attempted while offline; only sale creation is
/// queued.
class NetworkStatusBanner extends StatelessWidget {
  final Widget child;
  const NetworkStatusBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NetworkStatusService>()) return child;
    final status = Get.find<NetworkStatusService>();
    final syncService =
        Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>() : null;
    // A Stack overlay (not a Column) so the banner never resizes/repositions
    // `child` — every screen underneath computes its own safe-area padding
    // independently via MediaQuery, and stacking a sibling above it would
    // double-pad the status-bar inset when the banner is visible.
    return Stack(children: [
      child,
      Obx(() {
        final offline = !status.isOnline.value;
        final pending = syncService?.pendingCount.value ?? 0;
        final failed = syncService?.failedCount.value ?? 0;
        if (!offline && pending == 0 && failed == 0) return const SizedBox.shrink();

        final last = syncService?.lastSuccessfulSync.value;
        final lastText = last == null ? '' : ' · last sync ${DateFormat('HH:mm').format(last.toLocal())}';
        String sales(int n) => '$n sale${n == 1 ? '' : 's'}';

        final String text;
        final Color color;
        if (failed > 0) {
          // A rejected sale is never hidden: it stays until a manager retries or discards it.
          text = '${sales(failed)} rejected — tap to review${pending > 0 ? ' · ${sales(pending)} waiting' : ''}$lastText';
          color = AppColors.red;
        } else if (offline && pending > 0) {
          text = 'No internet — ${sales(pending)} saved on this device, will sync$lastText';
          color = AppColors.red;
        } else if (offline) {
          text = 'No internet connection$lastText';
          color = AppColors.red;
        } else {
          text = '${sales(pending)} syncing…$lastText';
          color = AppColors.amberDark;
        }
        final tappable = (failed > 0 || pending > 0) && (AppPreferences.cachedToken ?? '').isNotEmpty;

        return Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: GestureDetector(
              onTap: tappable && Get.currentRoute != Routes.posNeedsAttention ? () => Get.toNamed(Routes.posNeedsAttention) : null,
              child: Container(
                width: double.infinity,
                color: color,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Center(
                  child: CustomText(
                    text: text,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    ]);
  }
}
