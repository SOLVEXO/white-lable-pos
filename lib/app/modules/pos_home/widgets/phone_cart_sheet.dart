import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The phone's cart: a pill with the live item count and total, docked above the bottom bar, that you drag (or tap) up
/// into the full receipt cart and back down. It only exists while the cart has items. Not a route — so the keyboard
/// barcode scanner keeps working with it open — and the Charge / Hold buttons inside still open the payment / hold
/// sheets.
class PhoneCartSheet extends StatefulWidget {
  const PhoneCartSheet({super.key, required this.c, required this.cartKey});
  final PosHomeController c;
  final GlobalKey cartKey;

  static const double pillHeight = 72;

  @override
  State<PhoneCartSheet> createState() => _PhoneCartSheetState();
}

class _PhoneCartSheetState extends State<PhoneCartSheet> with SingleTickerProviderStateMixin {
  /// 0 = collapsed (the pill), 1 = expanded.
  late final AnimationController _a;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this, duration: Motion.slow);
    // an emptied cart (charged, held, cleared) must not leave the NEXT sale opening already expanded
    _emptyWorker = ever<List<CartItem>>(widget.c.cartItems, (items) {
      if (items.isEmpty) _a.value = 0;
    });
  }

  late final Worker _emptyWorker;

  @override
  void dispose() {
    _emptyWorker.dispose();
    _a.dispose();
    super.dispose();
  }

  void _settle(double target) {
    HapticFeedback.selectionClick();
    if (Motion.reduced(context)) {
      _a.value = target;
    } else {
      _a.animateTo(target, curve: Motion.emphasized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (!widget.c.hasItems) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, box) {
          final expandedH = (box.maxHeight * 0.88).clamp(PhoneCartSheet.pillHeight + 200, box.maxHeight);
          final range = expandedH - PhoneCartSheet.pillHeight;
          return Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _a,
              builder: (context, _) {
                final h = PhoneCartSheet.pillHeight + range * _a.value;
                return Container(
                  key: const Key('phoneCartSheet'),
                  height: h,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
                    border: Border.all(color: p.border),
                    boxShadow: context.overlayShadow,
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: PhoneCartSheet.pillHeight,
                        left: 0,
                        right: 0,
                        height: range,
                        child: IgnorePointer(
                          ignoring: _a.value < 0.6,
                          child: Opacity(opacity: Curves.easeIn.transform(_a.value.clamp(0.0, 1.0)), child: Padding(padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s2), child: CartPanel(c: widget.c, perforated: false))),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: PhoneCartSheet.pillHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _settle(_a.value < 0.5 ? 1 : 0),
                          onVerticalDragUpdate: (d) => _a.value = (_a.value - d.delta.dy / range).clamp(0.0, 1.0),
                          onVerticalDragEnd: (d) {
                            final v = d.primaryVelocity ?? 0;
                            _settle(v < -300 ? 1 : (v > 300 ? 0 : (_a.value > 0.5 ? 1 : 0)));
                          },
                          child: _Pill(c: widget.c, cartKey: widget.cartKey, openness: _a.value),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    });
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.c, required this.cartKey, required this.openness});
  final PosHomeController c;
  final GlobalKey cartKey;
  final double openness;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final n = c.itemCount;
      return Semantics(
        button: true,
        label: 'Cart, $n ${n == 1 ? 'item' : 'items'}, ${Money.format(c.total)}. ${openness < 0.5 ? 'Expand' : 'Collapse'}',
        excludeSemantics: true,
        child: Column(
          children: [
            const SizedBox(height: Space.s2),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: Radii.rFull)),
            const SizedBox(height: Space.s2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: Row(
                children: [
                  Container(
                    key: cartKey,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: p.accentFill, shape: BoxShape.circle),
                    child: Icon(Icons.shopping_bag_outlined, size: 20, color: p.onAccentFill),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(child: Text('$n ${n == 1 ? 'item' : 'items'}', key: const Key('pillCount'), style: context.type.subtitle.copyWith(color: p.textPrimary))),
                  AmountText(Money.format(c.total), key: const Key('pillTotal'), style: context.type.amountLg),
                  const SizedBox(width: Space.s2),
                  Transform.rotate(angle: openness * 3.14159, child: Icon(Icons.keyboard_arrow_up_rounded, color: p.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
