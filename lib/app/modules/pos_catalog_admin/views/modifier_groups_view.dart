import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.5 modifier groups: every group (inactive ones too) with its rule, options and how many products it is on. Tap to edit; "New group".
class ModifierGroupsView extends StatefulWidget {
  const ModifierGroupsView({super.key, this.controller});
  final ModifierGroupsController? controller;
  @override
  State<ModifierGroupsView> createState() => _ModifierGroupsViewState();
}

class _ModifierGroupsViewState extends State<ModifierGroupsView> with CatOwnedController<ModifierGroupsView, ModifierGroupsController> {
  @override
  ModifierGroupsController? get given => widget.controller;
  @override
  ModifierGroupsController create() => ModifierGroupsController();

  void _edit(ModifierGroup? g) {
    c.clearMessages();
    Get.to(() => ModifierGroupEditorView(controller: c, group: g));
  }

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Modifier groups',
    actions: [Obx(() => c.hasData ? TextButton(key: const Key('modNew'), onPressed: () => _edit(null), child: const Text('New group')) : const SizedBox.shrink())],
    body: CatStateBody(
      c: c,
      subject: 'Modifier groups',
      builder: (context) {
        final d = c.data.value!;
        final p = context.palette;
        final t = context.type;
        return [
          const CatHint('Options sold with a product (Size, Extras). The server prices them at the sale; a price change can be negative.'),
          if (d.groups.isEmpty) const CatEmpty(icon: Icons.tune_rounded, title: 'No modifier groups yet', message: 'Add one with "New group".'),
          for (final g in d.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('mod_${g.id}'),
                radius: Radii.rMd,
                padding: const EdgeInsets.all(Space.s3),
                onTap: () => _edit(g),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(g.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                        ),
                        StatusBadge(g.active ? 'On' : 'Off', tone: g.active ? StatusTone.success : StatusTone.neutral),
                      ],
                    ),
                    Text(
                      '${g.rule} · ${g.options.length} option${g.options.length == 1 ? '' : 's'} · on ${g.productIds.length} product${g.productIds.length == 1 ? '' : 's'}',
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      [for (final o in g.options) '${o.name}${o.priceDeltaMinor == 0 ? '' : ' ${catSigned(o.priceDeltaMinor, d.cur)}'}${o.active ? '' : ' (off)'}'].join(', '),
                      style: t.caption.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    ),
  );
}

class _OptionDraft {
  _OptionDraft({this.id = '', String name = '', String price = '', this.active = true}) : name = TextEditingController(text: name), price = TextEditingController(text: price);
  final String id;
  final TextEditingController name, price;
  bool active;
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// The editor: name, min / max choices, options (name + price change in major units, ± allowed, on / off), the products it is sold with, on / off.
class ModifierGroupEditorView extends StatefulWidget {
  const ModifierGroupEditorView({super.key, required this.controller, this.group});
  final ModifierGroupsController controller;
  final ModifierGroup? group;
  @override
  State<ModifierGroupEditorView> createState() => _ModifierGroupEditorViewState();
}

class _ModifierGroupEditorViewState extends State<ModifierGroupEditorView> {
  ModifierGroupsController get c => widget.controller;
  late final ModifierGroup? g = widget.group;
  late final TextEditingController _name = TextEditingController(text: g?.name ?? '');
  late final TextEditingController _min = TextEditingController(text: '${g?.minSelect ?? 0}');
  late final TextEditingController _max = TextEditingController(text: '${g?.maxSelect ?? 1}');
  late final List<_OptionDraft> _options = g == null
      ? [_OptionDraft()]
      : [for (final o in g!.options) _OptionDraft(id: o.id, name: o.name, price: o.priceDeltaMinor == 0 ? '' : catMajorText(o.priceDeltaMinor, c.cur.exponent), active: o.active)];
  late final List<String> _products = [...?g?.productIds];
  late bool _active = g?.active ?? true;
  final Map<int, String> _priceErrors = {};
  String? _countError;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await CatSearchSheet.open<PosProductModel>(
      title: 'Attach to a product',
      hint: 'Search products',
      search: c.searchProducts,
      tile: (context, p, pick) =>
          ListTile(key: Key('pickProduct_${p.productId}'), title: Text(p.name), subtitle: Text('${p.variants.length} variant${p.variants.length == 1 ? '' : 's'}'), onTap: pick),
    );
    if (picked == null || !mounted) return;
    c.names.addAll([picked]);
    if (!_products.contains(picked.productId)) setState(() => _products.add(picked.productId));
  }

  Future<void> _save() async {
    final exp = c.cur.exponent;
    final errors = <int, String>{};
    final options = <ModifierOption>[];
    for (var i = 0; i < _options.length; i++) {
      final o = _options[i];
      final text = o.price.text.trim();
      final minor = text.isEmpty ? 0 : catParseMajor(text, exp);
      if (minor == null) {
        errors[i] = catAmountHint(exp);
        continue;
      }
      options.add(ModifierOption(id: o.id, name: o.name.text.trim(), priceDeltaMinor: minor, active: o.active));
    }
    final min = int.tryParse(_min.text.trim());
    final max = int.tryParse(_max.text.trim());
    setState(() {
      _priceErrors
        ..clear()
        ..addAll(errors);
      _countError = min == null || max == null ? 'Enter whole numbers.' : null;
    });
    if (errors.isNotEmpty || min == null || max == null) return;
    final ok = await c.save(
      ModifierGroup(id: g?.id ?? '', name: _name.text.trim(), minSelect: min, maxSelect: max, productIds: _products, options: options, active: _active, sortOrder: g?.sortOrder ?? 0),
    );
    if (ok && mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: g == null ? 'New modifier group' : 'Edit modifier group',
      actions: [Obx(() => TextButton(key: const Key('modSave'), onPressed: c.busy.value ? null : _save, child: const Text('Save')))],
      body: ListView(
        key: const Key('modEditor'),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        children: [
          CatBanners(c: c),
          TextField(
            key: const Key('modName'),
            controller: _name,
            decoration: catField('Group name', hint: 'e.g. Size'),
          ),
          const SizedBox(height: Space.s3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('modMin'),
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: catField('Must choose at least', error: _countError),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: TextField(key: const Key('modMax'), controller: _max, keyboardType: TextInputType.number, decoration: catField('Can choose up to')),
              ),
            ],
          ),
          const CatHint('0 means optional. The server checks the numbers against the options that are on.'),
          SwitchListTile.adaptive(
            key: const Key('modActive'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Group is on'),
            subtitle: const Text('Off hides it at the till'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          InvSectionTitle('Options · ${c.cur.currency}'),
          for (var i = 0; i < _options.length; i++)
            Padding(
              key: Key('modOption_$i'),
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                radius: Radii.rMd,
                padding: const EdgeInsets.all(Space.s3),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: Key('modOptName_$i'),
                            controller: _options[i].name,
                            decoration: catField('Option', hint: 'e.g. Large'),
                          ),
                        ),
                        const SizedBox(width: Space.s2),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: Key('modOptPrice_$i'),
                            controller: _options[i].price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: catField('Price change', hint: '0, 1.50 or -0.50', error: _priceErrors[i]),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile.adaptive(
                            key: Key('modOptActive_$i'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('On', style: t.body.copyWith(color: p.textPrimary)),
                            value: _options[i].active,
                            onChanged: (v) => setState(() => _options[i].active = v),
                          ),
                        ),
                        // saved options keep their id (sales name them): turn them off rather than remove them
                        if (_options[i].id.isEmpty && _options.length > 1)
                          IconButton(
                            key: Key('modOptRemove_$i'),
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () {
                              final gone = _options[i];
                              setState(() => _options.removeAt(i));
                              WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          AppButton(key: const Key('modAddOption'), label: 'Add option', icon: Icons.add_rounded, variant: AppButtonVariant.secondary, onPressed: () => setState(() => _options.add(_OptionDraft()))),
          const InvSectionTitle('Sold with'),
          if (_products.isEmpty) const CatHint('Not on any product yet.'),
          Obx(
            // reads the names map even with no product yet, so the Obx always has an observable
            () => c.names.products.isEmpty && _products.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    children: [for (final id in _products) InputChip(key: Key('modProduct_$id'), label: Text(c.names.product(id)), onDeleted: () => setState(() => _products.remove(id)))],
                  ),
          ),
          const SizedBox(height: Space.s2),
          AppButton(key: const Key('modAttach'), label: 'Attach to a product', icon: Icons.link_rounded, variant: AppButtonVariant.secondary, onPressed: _attach),
          const SizedBox(height: Space.s5),
          Obx(() => AppButton(key: const Key('modSaveBottom'), label: 'Save group', loading: c.busy.value, onPressed: c.busy.value ? null : _save)),
        ],
      ),
    );
  }
}
