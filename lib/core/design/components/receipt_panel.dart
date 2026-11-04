import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// A cart/receipt surface with perforated (scalloped) top and bottom edges.
///
/// Uses a single clipped [PhysicalShape] so the shadow follows the notches —
/// no BackdropFilter, no per-frame work. Lay out [header], an expanding [body]
/// (usually a scrolling list) and a pinned [footer] (totals / charge button).
class ReceiptPanel extends StatelessWidget {
  const ReceiptPanel({
    super.key,
    this.header,
    required this.body,
    this.footer,
    this.perforatedTop = true,
    this.perforatedBottom = true,
  });
  final Widget? header;
  final Widget body;
  final Widget? footer;
  final bool perforatedTop;
  final bool perforatedBottom;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const notch = 7.0;
    final clipper = _PerforatedClipper(
      top: perforatedTop,
      bottom: perforatedBottom,
      notchRadius: notch,
    );
    return Stack(
      children: [
        // Soft shadow that follows the perforated outline. Its own repaint
        // boundary: it repaints on resize/theme only, never when the cart
        // contents change.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _PanelShadowPainter(
                clipper,
                p.isDark ? const Color(0x99000000) : const Color(0x261B1A17),
              ),
            ),
          ),
        ),
        ClipPath(
          clipper: clipper,
          child: ColoredBox(
            color: p.surface,
            child: Padding(
              padding: EdgeInsets.only(
                top: perforatedTop ? notch * 2 : 0,
                bottom: perforatedBottom ? notch * 2 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) header!,
                  Expanded(child: body),
                  if (footer != null) footer!,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelShadowPainter extends CustomPainter {
  _PanelShadowPainter(this.clipper, this.color);
  final _PerforatedClipper clipper;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      clipper.getClip(size).shift(const Offset(0, 4)),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  @override
  bool shouldRepaint(_PanelShadowPainter o) =>
      o.color != color || o.clipper.shouldReclip(clipper);
}

class _PerforatedClipper extends CustomClipper<Path> {
  const _PerforatedClipper({
    required this.top,
    required this.bottom,
    required this.notchRadius,
  });
  final bool top;
  final bool bottom;
  final double notchRadius;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final step = notchRadius * 2.6;
    final count = (size.width / step).floor();
    final start = (size.width - (count - 1) * step) / 2;
    final holes = Path();
    for (var i = 0; i < count; i++) {
      final cx = start + i * step;
      if (top) {
        holes.addOval(
          Rect.fromCircle(center: Offset(cx, 0), radius: notchRadius * 0.62),
        );
      }
      if (bottom) {
        holes.addOval(
          Rect.fromCircle(
            center: Offset(cx, size.height),
            radius: notchRadius * 0.62,
          ),
        );
      }
    }
    return Path.combine(PathOperation.difference, path, holes);
  }

  @override
  bool shouldReclip(_PerforatedClipper o) =>
      o.top != top || o.bottom != bottom || o.notchRadius != notchRadius;
}

/// Dashed receipt divider.
class ReceiptDivider extends StatelessWidget {
  const ReceiptDivider({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: Space.s3),
  });
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(context.palette.border)),
    ),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, 0), Offset(x + 5, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

/// One label/value line for a receipt (subtotal, tax, total). Values are
/// pre-formatted strings in the tabular amount style.
class ReceiptRow extends StatelessWidget {
  const ReceiptRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (strong ? context.type.subtitle : context.type.body)
                  .copyWith(color: strong ? p.textPrimary : p.textSecondary),
            ),
          ),
          Text(
            value,
            style: (strong ? context.type.amountLg : context.type.amountMd)
                .copyWith(color: valueColor ?? p.textPrimary),
          ),
        ],
      ),
    );
  }
}
