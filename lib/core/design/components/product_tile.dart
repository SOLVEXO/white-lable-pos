import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'app_network_image.dart';
import 'fly_to_cart.dart';
import 'press_scale.dart';

/// Product grid tile: image, name, price, and a stock ring.
///
/// Stock: pass [stock] with [stockCapacity] (the level that counts as "full")
/// for a ring; [unlimited] shows ∞; [stock] == 0 dims the tile and marks it
/// sold out (tap disabled). Tapping adds ([onAdd]) and plays a ripple, a pop and
/// — when [cartKey] is given — a fly-to-cart dot. The price is the pre-formatted
/// [priceText]; this widget never computes money.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.name,
    required this.priceText,
    required this.onAdd,
    this.imageUrl,
    this.stock,
    this.stockCapacity = 20,
    this.unlimited = false,
    this.cartKey,
    this.inCartQty = 0,
  });

  final String name;
  final String priceText;
  final VoidCallback? onAdd;
  final String? imageUrl;
  final int? stock;
  final int stockCapacity;
  final bool unlimited;
  final GlobalKey? cartKey;

  /// Shows an accent count badge when > 0.
  final int inCartQty;

  bool get _soldOut => !unlimited && stock != null && stock! <= 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onAdd != null && !_soldOut;
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          '$name, $priceText${_soldOut ? ', sold out' : ''}${inCartQty > 0 ? ', $inCartQty in cart' : ''}',
      excludeSemantics: true,
      onTap: enabled ? onAdd : null,
      child: PressScale(
        enabled: enabled,
        scale: 0.96,
        child: Builder(
          builder: (tileContext) => Opacity(
            opacity: _soldOut ? 0.55 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: Radii.rLg,
                border: Border.all(
                  color: inCartQty > 0 ? p.accent : p.border,
                  width: inCartQty > 0 ? 1.5 : 1,
                ),
                boxShadow: context.softShadow,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: Radii.rLg,
                  onTap: enabled
                      ? () {
                          HapticFeedback.lightImpact();
                          onAdd!();
                          if (cartKey != null) {
                            FlyToCart.run(
                              tileContext,
                              cartKey!,
                              color: p.accent,
                            );
                          }
                        }
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(Radii.md),
                                ),
                                child: AppNetworkImage(url: imageUrl),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: _StockBadge(
                                  stock: stock,
                                  capacity: stockCapacity,
                                  unlimited: unlimited,
                                ),
                              ),
                              if (inCartQty > 0)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 26,
                                      minHeight: 26,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: p.accent,
                                      borderRadius: Radii.rFull,
                                    ),
                                    child: Text(
                                      '$inCartQty',
                                      style: context.type.amountMd.copyWith(
                                        fontSize: 13,
                                        color: p.onAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_soldOut)
                                Positioned.fill(
                                  child: Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: p.surface.withValues(
                                          alpha: 0.92,
                                        ),
                                        borderRadius: Radii.rFull,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: Space.s3,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          'Sold out',
                                          style: context.type.caption.copyWith(
                                            color: p.dangerFg,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.s3,
                          Space.s1,
                          Space.s3,
                          Space.s3,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Always two lines tall, so image areas line up
                            // across a grid whatever the name length.
                            Builder(
                              builder: (context) {
                                final style = context.type.label.copyWith(
                                  color: p.textPrimary,
                                  fontSize: context.type.body.fontSize,
                                );
                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight:
                                        2 *
                                        style.fontSize! *
                                        (style.height ?? 1.3) *
                                        MediaQuery.textScalerOf(
                                          context,
                                        ).scale(1),
                                  ),
                                  child: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: style,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 2),
                            Text(
                              priceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.type.amountMd.copyWith(
                                color: p.accentFg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({
    required this.stock,
    required this.capacity,
    required this.unlimited,
  });
  final int? stock;
  final int capacity;
  final bool unlimited;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Sold out is already stated by the tile's own pill; no ring for 0.
    if (!unlimited && (stock == null || stock! <= 0)) {
      return const SizedBox.shrink();
    }
    final frac = unlimited ? 1.0 : (stock!.clamp(0, capacity) / capacity);
    final color = unlimited || frac > 0.35
        ? p.success
        : (frac > 0.1 ? p.warning : p.danger);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.94),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(34, 34),
            painter: _RingPainter(frac, color, p.border),
          ),
          unlimited
              ? Icon(
                  Icons.all_inclusive_rounded,
                  size: 14,
                  color: p.textSecondary,
                )
              : Text(
                  '${stock! > 99 ? '99+' : stock}',
                  style: context.type.caption.copyWith(
                    fontSize: 10,
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac, this.color, this.track);
  final double frac;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 6.2831853, false, paint..color = track);
    canvas.drawArc(
      r,
      -1.5707963,
      6.2831853 * frac,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.frac != frac || o.color != color || o.track != track;
}
