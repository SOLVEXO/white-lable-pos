import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "Coupon" — enter a code, the server checks it against this cart (a live check: coupons are online-only) and the discount shows in
/// the totals. Apply is disabled while the check runs, so a double tap is one check.
class CouponSheet extends StatefulWidget {
  const CouponSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(CouponSheet(c: c), title: 'Coupon');

  @override
  State<CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends State<CouponSheet> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final err = await widget.c.applyCoupon(_code.text);
    if (!mounted) return;
    if (err == null && widget.c.appliedCoupon.value != null) {
      Get.back();
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final applied = widget.c.appliedCoupon.value;
      final busy = widget.c.isApplyingCoupon.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (applied != null) ...[
            AppCard(
              color: p.fill,
              radius: Radii.rMd,
              child: Row(
                children: [
                  Icon(Icons.sell_rounded, color: p.accent),
                  const SizedBox(width: Space.s3),
                  Expanded(child: Text('${applied.code} applied', key: const Key('couponApplied'), style: context.type.subtitle.copyWith(color: p.textPrimary))),
                  TextButton(key: const Key('couponRemove'), onPressed: () { widget.c.removeCoupon(); Get.back(); }, child: const Text('Remove')),
                ],
              ),
            ),
          ] else ...[
            AppTextField(
              key: const Key('couponCode'),
              label: 'Coupon code',
              controller: _code,
              autofocus: true,
              enabled: !busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
              errorText: _error,
            ),
            const SizedBox(height: Space.s2),
            Text('Needs a connection. A coupon cannot be combined with a discount, and is not kept on a held sale.', style: context.type.caption.copyWith(color: p.textSecondary)),
            const SizedBox(height: Space.s4),
            AppButton(key: const Key('couponApply'), label: 'Apply coupon', icon: Icons.check_rounded, loading: busy, onPressed: busy ? null : _apply),
          ],
        ],
      );
    });
  }
}
