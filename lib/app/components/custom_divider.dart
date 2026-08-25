import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';

class CustomDivider extends StatelessWidget {
  const CustomDivider({
    super.key,
    this.dividerColor = AppColors.dividerColorApp,
    this.bgColor = AppColors.bgColorSearchField,
  });

  final Color dividerColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: dividerColor, width: 1.5)),
      ),
    );
  }
}
