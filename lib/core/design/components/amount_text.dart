import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// Money / quantity text with a rolling-digit animation.
///
/// Pass the *already formatted* string (e.g. `Money.format(total)`) — this widget
/// only displays; it never computes or rounds. Digits are slotted from the right,
/// so `9.99 → 10.99` keeps the cents column in place and only changed digits roll.
/// JetBrains Mono + tabular figures keep every slot the same width.
class AmountText extends StatelessWidget {
  const AmountText(
    this.text, {
    super.key,
    this.style,
    this.color,
    this.animate = true,
    this.alignment = MainAxisAlignment.start,
  });

  final String text;

  /// Defaults to `context.type.amountLg`.
  final TextStyle? style;
  final Color? color;
  final bool animate;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? context.type.amountLg).copyWith(
      color: color ?? context.palette.textPrimary,
    );
    // A long total at a large text scale shrinks to fit instead of overflowing.
    final fitAlign = switch (alignment) {
      MainAxisAlignment.end => Alignment.centerRight,
      MainAxisAlignment.center => Alignment.center,
      _ => Alignment.centerLeft,
    };
    Widget fit(Widget w) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: fitAlign, child: w);
    if (!animate || Motion.reduced(context)) {
      return Semantics(
        label: text,
        excludeSemantics: true,
        child: fit(Text(text, style: base, maxLines: 1, softWrap: false)),
      );
    }
    final chars = text.characters.toList();
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: fit(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chars.length; i++)
                KeyedSubtree(
                  key: ValueKey<int>(
                    chars.length - i,
                  ), // slot counted from the right
                  child: _RollingChar(char: chars[i], style: base),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RollingChar extends StatelessWidget {
  const _RollingChar({required this.char, required this.style});
  final String char;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final isDigit = RegExp(r'[0-9]').hasMatch(char);
    final text = Text(
      char,
      key: ValueKey<String>(char),
      style: style,
      maxLines: 1,
      softWrap: false,
    );
    if (!isDigit) return text;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Motion.slow,
        switchInCurve: Motion.emphasized,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey<String>(char);
          // Incoming slides up from below; outgoing (anim runs 1→0) exits upward.
          final offset = Tween<Offset>(
            begin: Offset(0, incoming ? 0.7 : -0.7),
            end: Offset.zero,
          ).animate(anim);
          return SlideTransition(
            position: offset,
            child: FadeTransition(opacity: anim, child: child),
          );
        },
        child: text,
      ),
    );
  }
}
