import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One variant being typed: attribute pairs, price, cost, SKU, barcode, starting stock, lots.
class VariantDraft {
  VariantDraft({List<String> optionNames = const []}) : options = [for (final n in optionNames) (name: TextEditingController(text: n), value: TextEditingController())];
  final List<({TextEditingController name, TextEditingController value})> options;
  final TextEditingController price = TextEditingController();
  final TextEditingController cost = TextEditingController();
  final TextEditingController sku = TextEditingController();
  final TextEditingController barcode = TextEditingController();
  final TextEditingController stock = TextEditingController();
  bool trackLots = false;
  String? priceError, costError, stockError;

  /// The write body, or null with the field errors set (input checks only; the server decides the rest).
  Map<String, dynamic>? toBody(int exponent) {
    final p = catParseMajor(price.text, exponent);
    final costText = cost.text.trim();
    final c = costText.isEmpty ? null : catParseMajor(costText, exponent);
    final stockText = stock.text.trim();
    final s = stockText.isEmpty ? null : int.tryParse(stockText);
    priceError = p == null ? (price.text.trim().isEmpty ? 'A price is needed.' : catAmountHint(exponent)) : null;
    costError = costText.isNotEmpty && c == null ? catAmountHint(exponent) : null;
    stockError = stockText.isNotEmpty && s == null ? 'Enter a whole number.' : null;
    if (p == null || costError != null || stockError != null) return null;
    String? opt(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();
    return {
      'priceMinor': p,
      'costMinor': ?c,
      'sku': ?opt(sku),
      'barcode': ?opt(barcode),
      'stock': ?s,
      'trackLots': trackLots,
      'options': [
        for (final o in options)
          if (o.name.text.trim().isNotEmpty && o.value.text.trim().isNotEmpty) {'name': o.name.text.trim(), 'value': o.value.text.trim()},
      ],
    };
  }

  void dispose() {
    for (final o in options) {
      o.name.dispose();
      o.value.dispose();
    }
    for (final t in [price, cost, sku, barcode, stock]) {
      t.dispose();
    }
  }
}

/// The fields of one variant (shared by the new-product form and the Add variant sheet).
class VariantForm extends StatefulWidget {
  const VariantForm({super.key, required this.draft, required this.index, required this.currency, this.lockOptionNames = false});
  final VariantDraft draft;
  final int index;
  final String currency;

  /// adding to an existing product: the attribute names are those of its other variants
  final bool lockOptionNames;
  @override
  State<VariantForm> createState() => _VariantFormState();
}

class _VariantFormState extends State<VariantForm> {
  VariantDraft get d => widget.draft;
  int get i => widget.index;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var k = 0; k < d.options.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('varOptName_${i}_$k'),
                    controller: d.options[k].name,
                    enabled: !widget.lockOptionNames,
                    decoration: catField('Attribute', hint: 'e.g. Size'),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: TextField(
                    key: Key('varOptValue_${i}_$k'),
                    controller: d.options[k].value,
                    decoration: catField('Value', hint: 'e.g. Large'),
                  ),
                ),
                if (!widget.lockOptionNames)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      final gone = d.options[k];
                      setState(() => d.options.removeAt(k));
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        gone.name.dispose();
                        gone.value.dispose();
                      });
                    },
                  ),
              ],
            ),
          ),
        if (!widget.lockOptionNames)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('varAddOption_$i'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add an attribute (size, colour…)'),
              onPressed: () => setState(() => d.options.add((name: TextEditingController(), value: TextEditingController()))),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: Key('varPrice_$i'),
                controller: d.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: catField('Price', prefix: '${widget.currency} ', error: d.priceError),
              ),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: TextField(
                key: Key('varCost_$i'),
                controller: d.cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: catField('Cost (optional)', prefix: '${widget.currency} ', error: d.costError),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(key: Key('varSku_$i'), controller: d.sku, decoration: catField('SKU (optional)')),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: TextField(key: Key('varBarcode_$i'), controller: d.barcode, decoration: catField('Barcode (optional)')),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        TextField(
          key: Key('varStock_$i'),
          controller: d.stock,
          keyboardType: TextInputType.number,
          decoration: catField('Starting stock', hint: '0', error: d.stockError),
        ),
        SwitchListTile.adaptive(
          key: Key('varLots_$i'),
          contentPadding: EdgeInsets.zero,
          title: Text('Track lots and expiry', style: t.body.copyWith(color: p.textPrimary)),
          value: d.trackLots,
          onChanged: (v) => setState(() => d.trackLots = v),
        ),
      ],
    );
  }
}

/// G4.5 new product: name, category, one or more variants. After the create it shows the product with its variants, Add variant and Archive.
class NewProductView extends StatefulWidget {
  const NewProductView({super.key, this.controller});
  final NewProductController? controller;
  @override
  State<NewProductView> createState() => _NewProductViewState();
}

class _NewProductViewState extends State<NewProductView> with CatOwnedController<NewProductView, NewProductController> {
  @override
  NewProductController? get given => widget.controller;
  @override
  NewProductController create() => NewProductController();

  final TextEditingController _name = TextEditingController();
  String? _categoryId;
  final List<VariantDraft> _variants = [VariantDraft()];

  @override
  void dispose() {
    _name.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final exp = c.cur.exponent;
    final bodies = [for (final v in _variants) v.toBody(exp)];
    setState(() {});
    if (bodies.any((b) => b == null)) return;
    await c.create({'name': _name.text.trim(), 'categoryId': ?_categoryId, 'variants': bodies});
  }

  void _startOver() {
    c.startOver();
    setState(() {
      _name.clear();
      _categoryId = null;
      final old = [..._variants];
      _variants
        ..clear()
        ..add(VariantDraft());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final v in old) {
          v.dispose();
        }
      });
    });
  }

  Future<void> _addVariant(CatalogProduct p) async {
    final names = p.variants.isEmpty ? const <String>[] : [for (final o in p.variants.first.options) o.name];
    await AppBottomSheet.showGet<bool>(
      _AddVariantSheet(c: c, optionNames: names),
      title: 'Add a variant',
    );
  }

  Future<void> _archive(CatalogVariant v) async {
    final ok = await AppDialog.confirm(context, title: 'Archive ${v.label}?', message: 'It stops selling. Past sales and stock history keep it.', confirmLabel: 'Archive', destructive: true);
    if (ok) await c.archiveVariant(v);
  }

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'New product',
    body: CatStateBody(
      c: c,
      subject: 'Creating products',
      builder: (context) {
        final made = c.product.value;
        return made == null ? _form(context) : _result(context, made);
      },
    ),
  );

  List<Widget> _form(BuildContext context) => [
    TextField(key: const Key('prodName'), controller: _name, decoration: catField('Product name')),
    const SizedBox(height: Space.s3),
    DropdownButtonFormField<String?>(
      key: const Key('prodCategory'),
      initialValue: _categoryId,
      decoration: catField('Category'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No category')),
        for (final cat in c.categories) DropdownMenuItem<String?>(value: cat.id, child: Text(cat.name)),
      ],
      onChanged: (v) => setState(() => _categoryId = v),
    ),
    if (c.categories.isEmpty)
      const Padding(
        padding: EdgeInsets.only(top: Space.s1),
        child: CatHint('No categories yet. Add them under Categories.'),
      ),
    for (var i = 0; i < _variants.length; i++) ...[
      Row(
        children: [
          Expanded(child: InvSectionTitle(_variants.length == 1 ? 'Price & stock' : 'Variant ${i + 1}')),
          if (_variants.length > 1)
            IconButton(
              key: Key('prodRemoveVariant_$i'),
              tooltip: 'Remove variant',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                final gone = _variants[i];
                setState(() => _variants.removeAt(i));
                WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
              },
            ),
        ],
      ),
      VariantForm(key: ObjectKey(_variants[i]), draft: _variants[i], index: i, currency: c.cur.currency),
    ],
    AppButton(
      key: const Key('prodAddVariant'),
      label: 'Add another variant',
      icon: Icons.add_rounded,
      variant: AppButtonVariant.secondary,
      onPressed: () => setState(() => _variants.add(VariantDraft(optionNames: [for (final o in _variants.first.options) o.name.text]))),
    ),
    const SizedBox(height: Space.s5),
    AppButton(key: const Key('prodCreate'), label: 'Create product', loading: c.busy.value, onPressed: c.busy.value ? null : _create),
  ];

  List<Widget> _result(BuildContext context, CatalogProduct made) {
    final p = context.palette;
    final t = context.type;
    final cat = c.categoryName(made.categoryId);
    return [
      AppCard(
        key: const Key('prodCreated'),
        radius: Radii.rMd,
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(made.name, style: t.title.copyWith(color: p.textPrimary)),
            Text([cat ?? 'No category', if (made.status != null) made.status!].join(' · '), style: t.caption.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
      InvSectionTitle('Variants · ${made.variants.where((v) => v.status != 'archived').length} selling'),
      for (final v in made.variants)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s2),
          child: AppCard(
            key: Key('prodVariant_${v.id}'),
            radius: Radii.rMd,
            padding: const EdgeInsets.all(Space.s3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.label, style: t.subtitle.copyWith(color: p.textPrimary)),
                      Text(
                        [
                          'SKU ${v.sku}',
                          if (v.barcode != null) v.barcode!,
                          v.unlimitedStock ? 'Unlimited stock' : '${v.stock} in stock',
                          if (v.costMinor != null) 'Cost ${catMoney(v.costMinor!, made.cur)}',
                          if (v.trackLots) 'Lots',
                        ].join(' · '),
                        style: t.caption.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(catMoney(v.priceMinor, made.cur), style: t.subtitle.copyWith(color: p.textPrimary)),
                const SizedBox(width: Space.s2),
                if (v.status == 'archived')
                  const StatusBadge('Archived', tone: StatusTone.neutral)
                else
                  TextButton(key: Key('prodArchive_${v.id}'), onPressed: c.busy.value ? null : () => _archive(v), child: const Text('Archive')),
              ],
            ),
          ),
        ),
      AppButton(key: const Key('prodAddVariantAfter'), label: 'Add variant', icon: Icons.add_rounded, variant: AppButtonVariant.secondary, onPressed: () => _addVariant(made)),
      const SizedBox(height: Space.s2),
      AppButton(key: const Key('prodStartOver'), label: 'Create another product', variant: AppButtonVariant.ghost, onPressed: _startOver),
    ];
  }
}

class _AddVariantSheet extends StatefulWidget {
  const _AddVariantSheet({required this.c, required this.optionNames});
  final NewProductController c;
  final List<String> optionNames;
  @override
  State<_AddVariantSheet> createState() => _AddVariantSheetState();
}

class _AddVariantSheetState extends State<_AddVariantSheet> {
  late final VariantDraft _d = VariantDraft(optionNames: widget.optionNames);

  @override
  void dispose() {
    _d.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _d.toBody(widget.c.cur.exponent);
    setState(() {});
    if (body == null) return;
    final ok = await widget.c.addVariant(body);
    if (ok && mounted) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CatBanners(c: widget.c),
      VariantForm(draft: _d, index: 99, currency: widget.c.cur.currency, lockOptionNames: widget.optionNames.isNotEmpty),
      const SizedBox(height: Space.s3),
      Obx(() => AppButton(key: const Key('varSave'), label: 'Add variant', loading: widget.c.busy.value, onPressed: widget.c.busy.value ? null : _save)),
    ],
  );
}
