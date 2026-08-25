import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_images.dart';
import 'package:flutter/material.dart';

class CustomRefreshWrapper extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const CustomRefreshWrapper({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  State<CustomRefreshWrapper> createState() => _CustomRefreshWrapperState();
}

class _CustomRefreshWrapperState extends State<CustomRefreshWrapper>
    with SingleTickerProviderStateMixin {
  // ─── Constants ─────────────────────────────────────────────────────────────
  static const double _triggerThreshold = 80.0;
  static const double _maxPull = 120.0;
  static const double _resistance = 0.45; // dampen drag so it feels natural

  // ─── State ─────────────────────────────────────────────────────────────────
  double _pullDistance = 0;
  bool _isRefreshing = false;
  bool _isAtTop = true;
  double? _dragStartY;

  late final AnimationController _snapController;
  late Animation<double> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _snapController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 320),
        )..addListener(() {
          if (mounted) setState(() => _pullDistance = _snapAnimation.value);
        });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  // ─── Scroll position tracking ───────────────────────────────────────────────
  // Determines if the scrollable child is at its very top edge.
  // Works with any scroll physics because we read metrics, not events.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) {
      _isAtTop = n.metrics.pixels <= 0;
    }
    return false;
  }

  // ─── Pointer tracking ──────────────────────────────────────────────────────
  // Listener captures raw touch before any ScrollPhysics processes it,
  // so this works identically on ClampingScrollPhysics, BouncingScrollPhysics,
  // NeverScrollableScrollPhysics, and AlwaysScrollableScrollPhysics.
  void _onPointerDown(PointerDownEvent e) {
    _dragStartY = e.position.dy;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_isRefreshing || !_isAtTop || _dragStartY == null) return;

    final dragDelta = e.position.dy - _dragStartY!;
    if (dragDelta <= 0) return; // only downward drag counts

    _snapController.stop();
    setState(() {
      _pullDistance = (dragDelta * _resistance).clamp(0, _maxPull);
    });
  }

  void _onPointerUp(PointerUpEvent e) {
    _dragStartY = null;
    if (_isRefreshing) return;
    if (_pullDistance >= _triggerThreshold) {
      _triggerRefresh();
    } else {
      _snapBack(to: 0);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _dragStartY = null;
    if (!_isRefreshing) _snapBack(to: 0);
  }

  // ─── Actions ────────────────────────────────────────────────────────────────
  void _snapBack({required double to}) {
    _snapAnimation = Tween<double>(
      begin: _pullDistance,
      end: to,
    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOut));
    _snapController.forward(from: 0);
  }

  Future<void> _triggerRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _pullDistance = _triggerThreshold; // hold indicator at trigger point
    });
    await widget.onRefresh();
    if (!mounted) return;
    _snapBack(to: 0);
    setState(() => _isRefreshing = false);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Stack(
          children: [
            widget.child,
            if (_pullDistance > 0 || _isRefreshing) _buildIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    final progress = (_pullDistance / _triggerThreshold).clamp(0.0, 1.0);
    final offsetY = (_pullDistance * 0.45) - 15;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Center(
        child: Transform.translate(
          offset: Offset(0, offsetY),
          child: Transform.scale(
            scale: (0.6 + progress * 0.4).clamp(0.0, 1.0),
            child: SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Gradient progress ring
                  ShaderMask(
                    shaderCallback: (rect) => SweepGradient(
                      startAngle: 0,
                      endAngle: 6.28,
                      colors: [
                        AppColors.primaryColor,
                        AppColors.primaryColorLight,
                        AppColors.accentColor,
                        AppColors.primaryColorLight,
                        AppColors.primaryColor,
                      ],
                      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                    ).createShader(rect),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _isRefreshing ? null : progress,
                        // color is masked by ShaderMask
                        color: AppColors.background,
                      ),
                    ),
                  ),

                  // Logo bubble
                  Container(
                    width: 35,
                    height: 35,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CommonImageView(
                      imagePath: AppImages.logoImage,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
