import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';

class Skeleton extends StatefulWidget {
  final double height;
  final double width;
  final double cornerRadius;
  final bool switchColor;

  const Skeleton({
    super.key,
    this.height = 20,
    this.width = 200,
    this.cornerRadius = 4,
    this.switchColor = true,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  Animation? gradientPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    gradientPosition = Tween<double>(begin: -3, end: 10).animate(
      CurvedAnimation(parent: _controller!, curve: Curves.linear),
    )..addListener(() {
      setState(() {});
    });

    _controller?.repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
        gradient: LinearGradient(
          begin: Alignment(gradientPosition!.value, 0),
          end: const Alignment(-1, 0),
          colors: [
            widget.switchColor
                ? AppColors.blackOverlay5
                : AppColors.white.withOpacity(0.2),
            widget.switchColor
                ? AppColors.blackOverlay10
                : AppColors.white.withOpacity(0.3),
            widget.switchColor
                ? AppColors.blackOverlay5
                : AppColors.white.withOpacity(0.5),
          ],
        ),
      ),
    );
  }
}
