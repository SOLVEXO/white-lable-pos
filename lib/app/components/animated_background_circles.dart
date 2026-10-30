import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';

/// Slowly drifting semi-transparent white circles for gradient backgrounds.
/// Self-contained — just drop it into a Stack above the gradient container.
class AnimatedBackgroundCircles extends StatefulWidget {
  const AnimatedBackgroundCircles({super.key});

  @override
  State<AnimatedBackgroundCircles> createState() =>
      _AnimatedBackgroundCirclesState();
}

class _AnimatedBackgroundCirclesState extends State<AnimatedBackgroundCircles>
    with TickerProviderStateMixin {
  late final AnimationController _driftA;
  late final AnimationController _driftB;

  @override
  void initState() {
    super.initState();
    _driftA = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    _driftB = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _driftA.dispose();
    _driftB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: Listenable.merge([_driftA, _driftB]),
      builder: (context, _) {
        final a = _driftA.value;
        final b = _driftB.value;
        return Stack(
          children: [
            // Top-right large circle
            Positioned(
              top: -size.width * 0.35,
              right: -size.width * 0.2,
              child: Transform.translate(
                offset: Offset(-14 * b, 18 * a),
                child: Transform.scale(
                  scale: 0.93 + 0.07 * b,
                  child: _Circle(
                    diameter: size.width * 0.75,
                    opacity: 0.06 + 0.04 * a,
                  ),
                ),
              ),
            ),

            // Bottom-left circle
            Positioned(
              bottom: -size.width * 0.3,
              left: -size.width * 0.15,
              child: Transform.translate(
                offset: Offset(10 * a, -14 * b),
                child: Transform.scale(
                  scale: 0.94 + 0.06 * a,
                  child: _Circle(
                    diameter: size.width * 0.65,
                    opacity: 0.06 + 0.03 * b,
                  ),
                ),
              ),
            ),

            // Mid-right smaller circle
            Positioned(
              top: size.height * 0.38,
              right: -size.width * 0.4,
              child: Transform.translate(
                offset: Offset(16 * a, -20 * b),
                child: Transform.scale(
                  scale: 0.95 + 0.05 * b,
                  child: _Circle(
                    diameter: size.width * 0.55,
                    opacity: 0.04 + 0.03 * a,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.diameter, required this.opacity});
  final double diameter;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white.withOpacity(opacity),
      ),
    );
  }
}
