import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// − / + stepper. Each button has a 48×48 hit area; [compact] shrinks only the
/// visual (for dense cart rows). Reports intent via [onChanged]; the owner
/// decides whether the new value is allowed (max stock etc.).
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.compact = false,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int? max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canDec = value > min;
    final canInc = max == null || value < max!;
    final visual = compact ? 32.0 : 40.0;
    return Semantics(
      label: 'Quantity',
      value: '$value',
      increasedValue: canInc ? '${value + 1}' : null,
      decreasedValue: canDec ? '${value - 1}' : null,
      onIncrease: canInc ? () => onChanged(value + 1) : null,
      onDecrease: canDec ? () => onChanged(value - 1) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.fill,
          borderRadius: Radii.rFull,
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              enabled: canDec,
              visual: visual,
              onTap: () => onChanged(value - 1),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minWidth: compact ? 28 : 36),
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: Tween(begin: 0.7, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: Text(
                  '$value',
                  key: ValueKey(value),
                  textAlign: TextAlign.center,
                  style: context.type.amountMd.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              enabled: canInc,
              visual: visual,
              onTap: () => onChanged(value + 1),
              accent: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.visual,
    required this.onTap,
    this.accent = false,
  });
  final IconData icon;
  final bool enabled;
  final double visual;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap();
            }
          : null,
      child: SizedBox(
        width: Space.minTouch,
        height: Space.minTouch,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            width: visual,
            height: visual,
            decoration: BoxDecoration(
              color: enabled && accent ? p.accent : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: !enabled
                  ? p.textMuted.withValues(alpha: 0.5)
                  : (accent ? p.onAccent : p.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
