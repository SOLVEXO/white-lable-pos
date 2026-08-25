// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgIcon extends StatelessWidget {
  final String assetName;
  final double? size;
  final Color? color;
  final Function()? onTap;
  const SvgIcon({
    super.key,
    required this.assetName,
    this.size,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (assetName.toLowerCase().endsWith('.svg')) {
      return GestureDetector(
        onTap: onTap,
        child: SvgPicture.asset(
          assetName,
          height: size ?? 22,
          width: size ?? 22,
          color: color,
        ),
      );
    } else {
      // fallback for PNG/JPG
      return GestureDetector(
        onTap: onTap,
        child: Image.asset(
          assetName,
          height: size ?? 22,
          width: size ?? 22,
          color: color,
        ),
      );
    }
  }
}
