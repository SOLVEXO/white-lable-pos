import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresProfileSection extends StatelessWidget {
  final SellerStoresController controller;

  const StoresProfileSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final fg = p.onAccentFill;
    return Obx(
      () => Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: 0.18),
              border: Border.all(color: fg.withValues(alpha: 0.5), width: 2.5),
            ),
            child: controller.userProfileImage.value.isNotEmpty
                ? ClipOval(
                    child: CommonImageView(
                      url: controller.userProfileImage.value,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      controller.userInitials.value,
                      style: t.headline.copyWith(color: fg),
                    ),
                  ),
          ),
          const SizedBox(height: Space.s3),
          Text(
            controller.userName.value,
            style: t.title.copyWith(color: fg),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s1),
          Text(
            controller.userEmail.value,
            style: t.bodySmall.copyWith(color: fg.withValues(alpha: 0.75)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s1,
            ),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.14),
              borderRadius: Radii.rFull,
              border: Border.all(color: fg.withValues(alpha: 0.35)),
            ),
            child: Text(
              '✨ Starter Plan — Free',
              style: t.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
