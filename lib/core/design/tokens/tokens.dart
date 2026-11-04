import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 4-pt spacing scale.
abstract final class Space {
  static const double s0 = 0;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;

  /// Minimum interactive size (accessibility).
  static const double minTouch = 48;

  static const SizedBox gap1 = SizedBox(width: s1, height: s1);
  static const SizedBox gap2 = SizedBox(width: s2, height: s2);
  static const SizedBox gap3 = SizedBox(width: s3, height: s3);
  static const SizedBox gap4 = SizedBox(width: s4, height: s4);
  static const SizedBox gap6 = SizedBox(width: s6, height: s6);
  static const SizedBox gap8 = SizedBox(width: s8, height: s8);
}

/// Corner radii: 8 / 14 / 20 / 28.
abstract final class Radii {
  // Solvexo POS blueprint radii: small 10 / medium 14 / card 18 / sheet 24.
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double full = 999;

  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rFull = BorderRadius.all(Radius.circular(full));
}

/// Soft, layered shadows. Dark mode leans on borders and uses a deeper, tighter
/// shadow because a light-on-dark glow reads as a smudge.
abstract final class AppShadows {
  static List<BoxShadow> soft(Brightness b) => b == Brightness.dark
      ? const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F1B1A17),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x0F1B1A17),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ];

  static List<BoxShadow> raised(Brightness b) => b == Brightness.dark
      ? const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x141B1A17),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0x1A1B1A17),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ];

  static List<BoxShadow> overlay(Brightness b) => b == Brightness.dark
      ? const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1F1B1A17),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x261B1A17),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ];
}

/// Damped-spring easing: a short, soft overshoot that settles at 1.
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 7, this.frequency = 9});
  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) =>
      1 - math.exp(-damping * t) * math.cos(frequency * t);
}

/// Motion tokens. Durations 120 / 200 / 320 / 480 ms.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration slower = Duration(milliseconds: 480);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve spring = SpringCurve();

  /// True when the OS asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when the OS asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
