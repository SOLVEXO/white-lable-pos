import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// One note / coin and how many were counted (minor units: the server checks Σ value × count against the amount typed).
typedef Denomination = ({int valueMinor, int count});

/// G4.6: the notes and coins of a currency, largest first, in MAJOR units (null = not known: the till then takes the amount only).
List<num>? denominationsFor(String currency) => switch (currency.toUpperCase()) {
  'PKR' => const [5000, 1000, 500, 100, 50, 20, 10, 5, 2, 1],
  'USD' => const [100, 50, 20, 10, 5, 2, 1, 0.25, 0.10, 0.05, 0.01],
  'EUR' => const [500, 200, 100, 50, 20, 10, 5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01],
  'GBP' => const [50, 20, 10, 5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01],
  'AED' => const [1000, 500, 200, 100, 50, 20, 10, 5, 1, 0.5, 0.25],
  'SAR' => const [500, 200, 100, 50, 10, 5, 1, 0.5, 0.25, 0.1, 0.05],
  'INR' => const [2000, 500, 200, 100, 50, 20, 10, 5, 2, 1],
  'JPY' => const [10000, 5000, 2000, 1000, 500, 100, 50, 10, 5, 1],
  'KWD' => const [20, 10, 5, 1, 0.5, 0.25, 0.1, 0.05, 0.02, 0.01, 0.005],
  _ => null,
};

int denominationTotal(List<Denomination> rows) => rows.fold(0, (n, d) => n + d.valueMinor * d.count);

/// The rows the server takes (`[{valueMinor, count}]`, counted ones only).
List<Map<String, int>> denominationsJson(List<Denomination> rows) => [
  for (final d in rows)
    if (d.count > 0) {'valueMinor': d.valueMinor, 'count': d.count},
];

/// Count the drawer note by note: +/− or type the count; the total is the amount. Returns the counted rows (null = cancelled).
class DenominationSheet extends StatefulWidget {
  const DenominationSheet({super.key, required this.currency, required this.exponent, this.initial = const [], this.title = 'Count notes & coins'});
  final String currency;
  final int exponent;
  final List<Denomination> initial;
  final String title;

  static Future<List<Denomination>?> open({String? currency, int? exponent, List<Denomination> initial = const [], String title = 'Count notes & coins'}) => Get.bottomSheet<List<Denomination>>(
    DenominationSheet(currency: currency ?? Money.currency, exponent: exponent ?? Money.exponent, initial: initial, title: title),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );

  @override
  State<DenominationSheet> createState() => _DenominationSheetState();
}

class _DenominationSheetState extends State<DenominationSheet> {
  late final List<int> _values = [for (final v in denominationsFor(widget.currency) ?? const <num>[]) Money.toMinor(v, widget.exponent)];
  late final Map<int, TextEditingController> _counts = {
    for (final v in _values) v: TextEditingController(text: '${widget.initial.firstWhereOrNull((d) => d.valueMinor == v)?.count ?? ''}'.replaceAll(RegExp(r'^0$'), '')),
  };

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _count(int v) => int.tryParse(_counts[v]!.text) ?? 0;
  List<Denomination> get _rows => [for (final v in _values) (valueMinor: v, count: _count(v))];
  String _money(int minor) => Money.format(Money.fromMinor(minor, widget.exponent), currency: widget.currency, exponent: widget.exponent);

  void _step(int v, int by) {
    final n = (_count(v) + by).clamp(0, 99999);
    setState(() => _counts[v]!.text = n == 0 ? '' : '$n');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final total = denominationTotal(_rows);
    return AppSheetSurface(
      key: const Key('denominationSheet'),
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in _values)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s1),
              child: Row(
                children: [
                  SizedBox(width: 110, child: Text(_money(v), style: t.amountMd.copyWith(color: p.textPrimary))),
                  IconButton(key: Key('denomMinus_$v'), tooltip: 'One less', icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: () => _step(v, -1)),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      key: Key('denomCount_$v'),
                      controller: _counts[v],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                      decoration: const InputDecoration(hintText: '0', isDense: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(key: Key('denomPlus_$v'), tooltip: 'One more', icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => _step(v, 1)),
                  Expanded(
                    child: Text(_count(v) == 0 ? '' : _money(v * _count(v)), textAlign: TextAlign.end, style: t.caption.copyWith(color: p.textSecondary)),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text('Total', style: t.subtitle.copyWith(color: p.textPrimary))),
              Text(_money(total), key: const Key('denomTotal'), style: t.amountMd.copyWith(color: p.textPrimary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Space.s3),
          AppButton(key: const Key('denomUse'), label: 'Use ${_money(total)}', onPressed: () => Get.back(result: _rows.where((d) => d.count > 0).toList())),
        ],
      ),
    );
  }
}
