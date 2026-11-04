import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Shown across the POS shell in *restricted mode* (no active POS plan, enforced by the backend):
/// selling and the catalog are off; closing the shift, reports, refund/void and sign-out still work.
/// "Check again" re-asks the backend, so the banner clears itself once the plan is renewed on the web.
/// Deliberately has no price, buy button or link — plans are bought on the web, never in the app.
class PosRestrictedBanner extends StatelessWidget {
  const PosRestrictedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PosEntitlementService>();
    final p = context.palette;
    return Obx(() {
      if (!service.restricted.value) return const SizedBox.shrink();
      return Material(
        color: p.warningSoft,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s3),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 20, color: p.warningFg),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.message.value.isEmpty ? PosEntitlementService.planInactiveMessage : service.message.value,
                        style: context.type.label.copyWith(color: p.warningFg, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Selling is off. You can still close the shift, view reports, refund or void (manager) and sign out.',
                        style: context.type.caption.copyWith(color: p.warningFg),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: service.checkPlan,
                  style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.warningFg),
                  child: Text('Check again', style: context.type.label.copyWith(color: p.warningFg)),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
