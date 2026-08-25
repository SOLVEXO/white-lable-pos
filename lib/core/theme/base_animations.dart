import 'package:flutter/material.dart';

/// Motion tokens + a couple of reusable transition widgets, built entirely
/// on Flutter's own animation primitives (no extra animation package —
/// keeps the dependency surface unchanged).
class BaseMotion {
  BaseMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve bounce = Curves.easeOutBack;
}

/// Fades + slides [child] up into place — the default "content just
/// appeared" micro-animation used across redesigned screens.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = BaseMotion.normal,
    this.delay = Duration.zero,
    this.offsetY = 16,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: duration + delay,
      curve: Interval(
        (delay.inMilliseconds / (duration + delay).inMilliseconds).clamp(0, 1),
        1,
        curve: BaseMotion.standard,
      ),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offsetY),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A tap target that gently scales down on press — the "premium button
/// feel" used by [PrimaryButton]/[SecondaryButton] and tappable cards.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleTo;

  const PressableScale({super.key, required this.child, this.onTap, this.scaleTo = 0.97});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scaleTo : 1,
        duration: BaseMotion.fast,
        curve: BaseMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// Slide-up + fade page route — a premium alternative to the platform
/// default push, opt-in via [BaseRoute.to].
class BaseRoute<T> extends PageRouteBuilder<T> {
  BaseRoute({required Widget page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: BaseMotion.normal,
          reverseTransitionDuration: BaseMotion.normal,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: BaseMotion.emphasized);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
                child: child,
              ),
            );
          },
        );
}
