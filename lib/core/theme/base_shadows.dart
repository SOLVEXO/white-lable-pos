import 'package:flutter/material.dart';
import 'base_colors.dart';
import 'base_spacing.dart';

/// Elevation presets — soft, layered shadows instead of Material's default
/// flat elevation, used by [BaseDecorations] and premium card widgets.
///
/// [level1]–[level5] are the canonical 5-level elevation system; [xs]/[sm]/
/// [md]/[lg] remain as lower-level building blocks the levels are made of.
class BaseShadows {
  BaseShadows._();

  static const List<BoxShadow> none = [];

  static List<BoxShadow> xs = [
    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
  ];

  static List<BoxShadow> sm = [
    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
  ];

  static List<BoxShadow> md = [
    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> lg = [
    BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12)),
  ];

  /// Tinted "glow" shadow for primary CTAs — a Stripe/Linear-style accent.
  static List<BoxShadow> glow([Color? color]) => [
        BoxShadow(color: (color ?? BaseColors.primary).withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 8)),
      ];

  // ── 5-level elevation system ────────────────────────────────────────────
  // Level 1: resting cards, list items, ProductCard/StoreCard at rest.
  static List<BoxShadow> get level1 => xs;
  // Level 2: raised cards, chips, hover/pressed-out states.
  static List<BoxShadow> get level2 => sm;
  // Level 3: sticky headers, bottom nav bars, app bars with content behind.
  static List<BoxShadow> get level3 => md;
  // Level 4: dialogs, bottom sheets, modals.
  static List<BoxShadow> get level4 => lg;
  // Level 5: FABs, toasts/snackbars, anything floating above a modal.
  static List<BoxShadow> get level5 => [
        BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 40, offset: const Offset(0, 16)),
      ];

  static List<BoxShadow> forLevel(BaseElevation level) {
    switch (level) {
      case BaseElevation.level1:
        return level1;
      case BaseElevation.level2:
        return level2;
      case BaseElevation.level3:
        return level3;
      case BaseElevation.level4:
        return level4;
      case BaseElevation.level5:
        return level5;
    }
  }
}
