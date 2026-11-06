import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Discount (managers only — the server checks the manager's token again at Charge): percent or amount, quick percentages, Apply / Remove.
/// Cannot be combined with a coupon (the sheet says so instead of silently dropping one).
class DiscountSheet extends StatefulWidget {
  const DiscountSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(DiscountSheet(c: c), title: 'Discount');

  @override
  State<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<DiscountSheet> {
  late final TextEditingController _value = TextEditingController(text: widget.c.discountController.text == '0' ? '' : widget.c.discountController.text);
  late bool _percent = widget.c.isPercentDiscount.value;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _apply() {
    final v = double.tryParse(_value.text.trim()) ?? 0;
    if (v <= 0) return setState(() => _error = 'Enter a discount above zero.');
    if (_percent && v > 100) return setState(() => _error = 'A percentage cannot be more than 100.');
    widget.c.isPercentDiscount.value = _percent;
    widget.c.discountController.text = _value.text.trim();
    widget.c.cartItems.refresh();
    Get.back();
  }

  void _remove() {
    widget.c.discountController.text = '0';
    widget.c.cartItems.refresh();
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final hasCoupon = widget.c.appliedCoupon.value != null;
      final manager = widget.c.isManager.value;
      if (hasCoupon || !manager) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s3),
          child: Text(hasCoupon ? 'A coupon is applied. Remove it first — a coupon and a discount cannot be combined.' : 'Only managers can apply a discount.', key: const Key('discountBlocked'), style: context.type.body.copyWith(color: p.textSecondary)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            key: const Key('discountMode'),
            segments: [
              const ButtonSegment(value: true, label: Text('Percent')),
              ButtonSegment(value: false, label: Text('Amount (${widget.c.currencySymbol.value})')),
            ],
            selected: {_percent},
            onSelectionChanged: (s) => setState(() => _percent = s.first),
          ),
          const SizedBox(height: Space.s3),
          AppTextField(
            key: const Key('discountValue'),
            label: _percent ? 'Discount (%)' : 'Discount amount',
            controller: _value,
            autofocus: true,
            mono: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
            errorText: _error,
          ),
          if (_percent) ...[
            const SizedBox(height: Space.s2),
            Wrap(
              spacing: Space.s2,
              children: [
                for (final q in const [5, 10, 15, 20])
                  ActionChip(key: Key('discountQuick_$q'), label: Text('$q%'), onPressed: () => setState(() {
                        _value.text = '$q';
                        _error = null;
                      })),
              ],
            ),
          ],
          const SizedBox(height: Space.s4),
          Row(
            children: [
              Expanded(child: AppButton(key: const Key('discountRemove'), label: 'Remove', variant: AppButtonVariant.secondary, onPressed: _remove)),
              const SizedBox(width: Space.s3),
              Expanded(child: AppButton(key: const Key('discountApply'), label: 'Apply', onPressed: _apply)),
            ],
          ),
        ],
      );
    });
  }
}
