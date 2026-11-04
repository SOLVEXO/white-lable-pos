import 'package:flutter/material.dart';
import '../tokens/tokens.dart';

/// "Fly to cart": a dot arcs from where the user tapped to the cart target and shrinks into it. Purely visual — call it
/// next to (not instead of) the real add-to-cart call. No-ops under reduced motion or if either end isn't laid out.
///
/// The dot's animation is owned by the overlay entry's own widget (not the Overlay), so it is disposed with the entry
/// and can never outlive the widget tree.
abstract final class FlyToCart {
  static void run(BuildContext from, GlobalKey to, {required Color color, double size = 22}) {
    if (Motion.reduced(from)) return;
    final overlay = Overlay.maybeOf(from);
    final fromBox = from.findRenderObject() as RenderBox?;
    final toBox = to.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || fromBox == null || toBox == null || !fromBox.attached || !toBox.attached) {
      return;
    }
    final start = fromBox.localToGlobal(fromBox.size.center(Offset.zero));
    final end = toBox.localToGlobal(toBox.size.center(Offset.zero));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyDot(
        start: start,
        end: end,
        color: color,
        size: size,
        onDone: () {
          if (entry.mounted) {
            entry.remove();
            entry.dispose();
          }
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _FlyDot extends StatefulWidget {
  const _FlyDot({required this.start, required this.end, required this.color, required this.size, required this.onDone});
  final Offset start;
  final Offset end;
  final Color color;
  final double size;
  final VoidCallback onDone;

  @override
  State<_FlyDot> createState() => _FlyDotState();
}

class _FlyDotState extends State<_FlyDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      // After the frame: removing an OverlayEntry while the overlay is building is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final end = widget.end;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (_, __) {
          final t = _curve.value;
          // Quadratic arc: control point lifted above both ends.
          final ctl = Offset((start.dx + end.dx) / 2, (start.dy < end.dy ? start.dy : end.dy) - 90);
          final x = (1 - t) * (1 - t) * start.dx + 2 * (1 - t) * t * ctl.dx + t * t * end.dx;
          final y = (1 - t) * (1 - t) * start.dy + 2 * (1 - t) * t * ctl.dy + t * t * end.dy;
          final s = widget.size * (1 - 0.55 * t);
          return Stack(
            children: [
              Positioned(
                left: x - s / 2,
                top: y - s / 2,
                child: Opacity(
                  opacity: t < 0.85 ? 1 : (1 - t) / 0.15,
                  child: Container(width: s, height: s, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
