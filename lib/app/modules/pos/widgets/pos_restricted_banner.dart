import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';

/// Shown across the POS shell in *restricted mode* (no active POS plan, enforced by the backend):
/// selling and the catalog are off; closing the shift, reports, refund/void and sign-out still work.
/// "Check again" re-asks the backend, so the banner clears itself once the plan is renewed on the web.
/// Deliberately has no price, buy button or link — plans are bought on the web, never in the app.
class PosRestrictedBanner extends StatelessWidget {
  const PosRestrictedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PosEntitlementService>();
    return Obx(() {
      if (!service.restricted.value) return const SizedBox.shrink();
      return Material(
        color: const Color(0xFFFFF4E5),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF9A5B00)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.message.value.isEmpty ? PosEntitlementService.planInactiveMessage : service.message.value,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF5C3700)),
                      ),
                      const Text(
                        'Selling is off. You can still close the shift, view reports, refund or void (manager) and sign out.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF5C3700)),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: service.checkPlan, child: const Text('Check again')),
              ],
            ),
          ),
        ),
      );
    });
  }
}
