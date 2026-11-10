import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// G4.5: the options of a product sold with modifier groups ("Size: Small / Large", "Extras: up to 2"). Required groups must be answered before
/// Add; the price shown is an estimate (list price + deltas) — the SERVER prices the line. Offline it works from the cached groups; with none cached
/// the product is added plain (a sale is never blocked for options).
class PosModifierSheet extends StatefulWidget {
  const PosModifierSheet({super.key, required this.product, required this.variant, required this.groups, required this.controller});
  final PosProductModel product;
  final PosProductVariant variant;
  final List<ModifierGroup> groups;
  final PosHomeController controller;

  @override
  State<PosModifierSheet> createState() => _PosModifierSheetState();
}

class _PosModifierSheetState extends State<PosModifierSheet> {
  /// groupId → chosen option ids, in tap order
  final Map<String, List<String>> _chosen = {};

  bool get _valid => widget.groups.every((g) => (_chosen[g.id]?.length ?? 0) >= g.minSelect);

  List<ChosenModifier> get _mods => [
    for (final g in widget.groups)
      for (final id in _chosen[g.id] ?? const <String>[])
        if (g.options.firstWhereOrNull((o) => o.id == id) case final o?) ChosenModifier(groupId: g.id, groupName: g.name, optionId: o.id, name: o.name, priceDeltaMinor: o.priceDeltaMinor),
  ];

  void _tap(ModifierGroup g, ModifierOption o) {
    setState(() {
      final list = _chosen[g.id] ??= [];
      if (list.contains(o.id)) {
        list.remove(o.id);
      } else if (g.single) {
        list
          ..clear()
          ..add(o.id);
      } else if (list.length < g.maxSelect) {
        list.add(o.id);
      }
    });
  }

  String _delta(int m) => m == 0 ? '' : '${m > 0 ? '+' : '−'}${Money.format(Money.fromMinor(m.abs()))}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final mods = _mods;
    final base = widget.controller.priceBook.value?.entries[widget.variant.variantId];
    final unit = (base != null ? Money.fromMinor(base) : widget.variant.price) + Money.fromMinor(mods.fold(0, (n, m) => n + m.priceDeltaMinor));
    final missing = widget.groups.where((g) => (_chosen[g.id]?.length ?? 0) < g.minSelect).map((g) => g.name).toList();
    return AppSheetSurface(
      key: const Key('modifierSheet'),
      title: widget.product.hasMultipleVariants ? '${widget.product.name} · ${widget.variant.label}' : widget.product.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in widget.groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.s2, bottom: Space.s1),
              child: Row(
                children: [
                  Expanded(child: Text(g.name, style: t.subtitle.copyWith(color: p.textPrimary))),
                  Text(g.rule, style: t.caption.copyWith(color: g.required && (_chosen[g.id]?.length ?? 0) < g.minSelect ? p.warningFg : p.textMuted)),
                ],
              ),
            ),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s1,
              children: [
                for (final o in g.activeOptions)
                  FilterChip(
                    key: Key('mod_${g.id}_${o.id}'),
                    showCheckmark: !g.single,
                    label: Text(o.priceDeltaMinor == 0 ? o.name : '${o.name}  ${_delta(o.priceDeltaMinor)}'),
                    selected: _chosen[g.id]?.contains(o.id) ?? false,
                    onSelected: (_) => _tap(g, o),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.s4),
          if (missing.isNotEmpty) Text('Choose ${missing.join(', ')}', key: const Key('modifierMissing'), style: t.caption.copyWith(color: p.warningFg)),
          const SizedBox(height: Space.s2),
          AppButton(
            key: const Key('modifierAdd'),
            label: 'Add · ${Money.format(unit)}',
            onPressed: _valid
                ? () {
                    Get.back();
                    widget.controller.addToCart(widget.product, widget.variant, mods);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
