import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Who is on the till: the employee, their role and register, and since when the shift is open.
class PosSettingsProfileCard extends StatelessWidget {
  final PosSettingsController controller;

  const PosSettingsProfileCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Obx(
        () => Row(
          children: [
            _Avatar(initials: controller.initials),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(controller.name.value, style: context.type.title.copyWith(color: p.textPrimary)),
                  const SizedBox(height: Space.s1),
                  Text(
                    '${controller.role.value} · ${controller.registerName.value}',
                    style: context.type.bodySmall.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: Space.s2),
                  StatusBadge('Shift open since ${controller.shiftSince.value}', tone: StatusTone.success, dot: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;

  const _Avatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: context.type.title.copyWith(color: p.accentFg)),
    );
  }
}
