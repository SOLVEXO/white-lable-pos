import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// "Custom item" — a line with no catalogue product: a name, a price, a quantity and a tax category. It never touches stock; the
/// server prices and audits it and decides whether a manager must approve (asked at Charge, so no limit lives on this device).
class CustomItemSheet extends StatefulWidget {
  const CustomItemSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) => AppBottomSheet.showGet<void>(CustomItemSheet(c: c), title: 'Custom item');

  @override
  State<CustomItemSheet> createState() => _CustomItemSheetState();
}

class _CustomItemSheetState extends State<CustomItemSheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  int _qty = 1;
  String _tax = 'standard';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  void _add() {
    final price = double.tryParse(_price.text.trim()) ?? 0;
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the item a name.');
    if (price <= 0) return setState(() => _error = 'Enter a price above zero.');
    if (widget.c.addCustomItem(name: _name.text, price: price, qty: _qty, taxCategory: _tax, note: _note.text)) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(key: const Key('customName'), label: 'Item name', controller: _name, autofocus: true, textInputAction: TextInputAction.next),
        const SizedBox(height: Space.s3),
        AppTextField(
          key: const Key('customPrice'),
          label: 'Price (${Money.symbol()})',
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(child: Text('Quantity', style: context.type.subtitle.copyWith(color: p.textPrimary))),
            IconButton(key: const Key('customQtyMinus'), tooltip: 'Fewer', onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
            Text('$_qty', key: const Key('customQty'), style: context.type.amountMd),
            IconButton(key: const Key('customQtyPlus'), tooltip: 'More', onPressed: () => setState(() => _qty++), icon: const Icon(Icons.add_circle_outline_rounded)),
          ],
        ),
        const SizedBox(height: Space.s2),
        SegmentedButton<String>(
          key: const Key('customTax'),
          segments: const [
            ButtonSegment(value: 'standard', label: Text('Store tax rate')),
            ButtonSegment(value: 'exempt', label: Text('Tax exempt')),
          ],
          selected: {_tax},
          onSelectionChanged: (s) => setState(() => _tax = s.first),
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('customNote'), label: 'Note (optional)', controller: _note),
        if (_error != null) ...[
          const SizedBox(height: Space.s2),
          Text(_error!, key: const Key('customError'), style: context.type.caption.copyWith(color: p.danger)),
        ],
        const SizedBox(height: Space.s2),
        Text('A manager may be asked to approve this item when the sale is charged.', style: context.type.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s4),
        Obx(() => AppButton(key: const Key('customAdd'), label: 'Add to sale', icon: Icons.add_rounded, onPressed: widget.c.isAddingCustomItem.value ? null : _add)),
      ],
    );
  }
}
