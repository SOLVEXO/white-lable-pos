import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_limits_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Approval limits, read-only: what a cashier may do alone before a manager has to approve. Only the owner can change them (on the web panel).
class InvLimitsView extends StatelessWidget {
  InvLimitsView({super.key, InvLimitsController? controller}) : c = controller ?? (Get.isRegistered<InvLimitsController>() ? Get.find<InvLimitsController>() : Get.put(InvLimitsController()));
  final InvLimitsController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Approval limits',
      body: Obx(() {
        if (c.loading.value && c.limits.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
        if (c.error.value != null && c.limits.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        return ListView(
          key: const Key('invLimitsList'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            Text('Above these limits a manager has to approve. Only the owner can change them.', style: t.bodySmall.copyWith(color: p.textSecondary)),
            const SizedBox(height: Space.s3),
            for (final l in c.limits)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s2),
                child: AppCard(
                  key: Key('invLimit_${l.key}'),
                  radius: Radii.rMd,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.label, style: t.subtitle.copyWith(color: p.textPrimary)),
                            Text('Default ${l.format(l.defaultValue, c.exponent.value)}', style: t.caption.copyWith(color: p.textMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      Text(
                        l.format(l.value, c.exponent.value),
                        key: Key('invLimitValue_${l.key}'),
                        style: t.amountMd.copyWith(color: p.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}
