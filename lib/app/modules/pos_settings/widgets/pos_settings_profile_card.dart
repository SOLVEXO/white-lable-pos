import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosSettingsProfileCard extends StatelessWidget {
  final PosSettingsController controller;

  const PosSettingsProfileCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppDimen.allPadding),
      padding: const EdgeInsets.all(AppDimen.allPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Obx(
        () => Row(
          children: [
            _Avatar(initials: controller.initials),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: controller.name.value,
                    fontSize: AppFontSize.small,
                    fontWeight: FontWeight.bold,
                    color: AppColors.black,
                  ),
                  const SizedBox(height: 3),
                  CustomText(
                    text: '${controller.role.value} · ${controller.registerName.value}',
                    fontSize: AppFontSize.verySmall,
                    color: AppColors.grey,
                  ),
                  const SizedBox(height: 8),
                  _ShiftStatus(since: controller.shiftSince.value),
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
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: CustomText(
        text: initials,
        fontSize: AppFontSize.medium,
        fontWeight: FontWeight.bold,
        color: AppColors.primaryColor,
      ),
    );
  }
}

class _ShiftStatus extends StatelessWidget {
  final String since;

  const _ShiftStatus({required this.since});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primaryColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        CustomText(
          text: 'Shift open since $since',
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w500,
          color: AppColors.primaryColor,
        ),
      ],
    );
  }
}
