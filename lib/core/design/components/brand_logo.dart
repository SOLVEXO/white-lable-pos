import 'package:flutter/material.dart';

/// The Solvexo POS logo tile (the same PNG the native splash uses, so the two
/// match). `size` is logical px; the splash uses 120.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 120});
  final double size;

  static const String asset = 'assets/icon/splash_logo.png';

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Solvexo POS',
    image: true,
    child: Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    ),
  );
}
