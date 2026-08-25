import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// import 'package:hifzpro_app/apptheme/app_colors.dart';

// ignore: must_be_immutable
class CustomTextField extends StatelessWidget {
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final Function(String)? onFieldSubmitted;
  final String? label;
  final bool isDecoration;
  final int? maxLength;
  final int? maxLines;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool? filled;
  final Color? fillColor;
  final Color color;
  final Color textColor;
  final BorderRadiusGeometry? borderRadius;
  final bool ispadding;
  final bool isborder;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final double borderBorderradius;
  final EdgeInsetsGeometry? contentPadding;

  const CustomTextField({
    super.key,
    this.borderBorderradius = AppDimen.borderRadius,
    this.label,
    this.hintText,
    this.prefixIcon,
    this.isDecoration = true,
    this.obscureText = false,
    this.suffixIcon,
    this.filled = true,
    this.fillColor = AppColors.white,
    this.borderRadius,
    this.ispadding = false,
    this.isborder = false,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.color = AppColors.white,
    this.textColor = AppColors.black,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.onFieldSubmitted,
    this.maxLength,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Container(
      margin: ispadding ? EdgeInsets.only(bottom: 2) : null,
      decoration: isDecoration
          ? BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(borderBorderradius),
              // border: Border.all(
              //   color: AppColors.primaryColor.withOpacity(0.55),
              // ),
            )
          : null,
      child: TextFormField(
        style: TextStyle(color: textColor),
        onFieldSubmitted: onFieldSubmitted,
        maxLength: maxLength,
        maxLines: maxLines,

        validator: validator,
        onChanged: onChanged,
        keyboardType: keyboardType,
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        decoration: InputDecoration(
          prefixIcon: prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: prefixIcon,
                ),
          prefixIconColor: AppColors.grey,
          labelText: label,
          labelStyle: TextStyle(
            color: AppColors.grey,
            fontSize: isTablet ? 18 : 14,
          ),
          hintText: "$hintText".tr,
          hintStyle: TextStyle(color: AppColors.grey),
          suffixIcon: suffixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: suffixIcon,
                ),
          suffixIconColor: AppColors.grey,
          filled: filled,
          fillColor: fillColor,
          contentPadding: contentPadding ??
              EdgeInsets.only(
                left: 12,
                right: 18,
                top: isTablet ? 20 : 16,
                bottom: isTablet ? 20 : 16,
              ),
          enabledBorder: isborder
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderBorderradius),
                  borderSide: BorderSide(
                    color: AppColors.lightGrey,
                    width: 0.3,
                  ),
                )
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderBorderradius),
                  borderSide: BorderSide.none,
                ),
          focusedBorder: isborder
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderBorderradius),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                )
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderBorderradius),
                  borderSide: BorderSide.none,
                ),
        ),
      ),
    );
  }
}
