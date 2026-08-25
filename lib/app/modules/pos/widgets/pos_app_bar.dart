import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosAppBar extends StatelessWidget {
  final String title;

  /// Defaults to "{tenant app name} POS" via BrandingService when unset.
  final String? subtitle;

  const PosAppBar({super.key, this.title = 'Quick Sale', this.subtitle});

  @override
  Widget build(BuildContext context) {
    final effectiveSubtitle = subtitle ?? '${Get.find<BrandingService>().config.value.appName} POS';
    return Container(
      decoration: BoxDecoration(gradient: AppColors.appbarGradient),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 20,
        right: 20,
        bottom: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomText(
                  text: effectiveSubtitle,
                  fontSize: AppFontSize.small2,
                  color: AppColors.background,
                  fontWeight: FontWeight.w400,
                ),
                const SizedBox(height: 2),
                CustomText(
                  text: title,
                  fontSize: AppFontSize.large,
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ],
            ),
          ),
          FutureBuilder<String?>(
            future: AppPreferences.getPosEmployeeName(),
            builder: (context, snapshot) {
              final name = snapshot.data ?? '';
              final initial = name.trim().isNotEmpty
                  ? name.trim()[0].toUpperCase()
                  : 'P';
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: CustomText(
                  text: initial,
                  fontSize: 15,
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
