import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart' show dayKey, parseDayKey;
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

String _day(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// G4.8: a store day ("2026-11-12") as "12 Nov 2026" (no time zone conversion — it IS the store's day)
String _storeDay(String key) => parseDayKey(key) == null ? key : _day(parseDayKey(key)!);

/// the store's first / last valid day of a book (the server's; derived from the instants for a book saved before G4.8)
String? _fromDayOf(PriceBook b) => b.validFromDay ?? (b.startsAt == null ? null : dayKey(b.startsAt!));
String? _toDayOf(PriceBook b) => b.validToDay ?? (b.endsAt == null ? null : dayKey(b.endsAt!.subtract(const Duration(milliseconds: 1))));

StatusTone _tone(BookState s) => switch (s) {
  BookState.inForce => StatusTone.success,
  BookState.scheduled => StatusTone.info,
  BookState.ended => StatusTone.warning,
  BookState.off => StatusTone.neutral,
};

/// G4.5 price books: each book with where it stands now (in force / scheduled / ended / off), its window and how many prices it holds.
/// Tap to edit; "New book"; "Assign to a customer".
class PriceBooksView extends StatefulWidget {
  const PriceBooksView({super.key, this.controller});
  final PriceBooksController? controller;
  @override
  State<PriceBooksView> createState() => _PriceBooksViewState();
}

class _PriceBooksViewState extends State<PriceBooksView> with CatOwnedController<PriceBooksView, PriceBooksController> {
  @override
  PriceBooksController? get given => widget.controller;
  @override
  PriceBooksController create() => PriceBooksController();

  void _edit(PriceBook? b) {
    c.clearMessages();
    Get.to(() => PriceBookEditorView(controller: c, book: b));
  }

  void _assign() {
    c.clearMessages();
    Get.to(() => AssignPriceBookView(controller: c));
  }

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Price books',
    actions: [Obx(() => c.hasData ? TextButton(key: const Key('bookNew'), onPressed: () => _edit(null), child: const Text('New book')) : const SizedBox.shrink())],
    body: CatStateBody(
      c: c,
      subject: 'Price books',
      builder: (context) {
        final d = c.data.value!;
        final p = context.palette;
        final t = context.type;
        final now = c.now();
        return [
          const CatHint('Another price for some items. Picked at checkout, or given to a customer. The server decides at each sale whether a book is in force.'),
          AppButton(key: const Key('bookAssign'), label: 'Assign to a customer', icon: Icons.person_add_alt_rounded, variant: AppButtonVariant.secondary, onPressed: d.books.isEmpty ? null : _assign),
          const SizedBox(height: Space.s3),
          if (d.books.isEmpty) const CatEmpty(icon: Icons.sell_outlined, title: 'No price books yet', message: 'Add one with "New book".'),
          for (final b in d.books)
            Builder(
              builder: (context) {
                final s = BookState.of(b, now);
                final window = [if (_fromDayOf(b) != null) 'From ${_storeDay(_fromDayOf(b)!)}', if (_toDayOf(b) != null) 'Until the end of ${_storeDay(_toDayOf(b)!)}', if (b.timeZone != null && (_fromDayOf(b) != null || _toDayOf(b) != null)) '${b.timeZone} time'].join(' · ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: AppCard(
                    key: Key('book_${b.id}'),
                    radius: Radii.rMd,
                    padding: const EdgeInsets.all(Space.s3),
                    onTap: () => _edit(b),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(b.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                            ),
                            StatusBadge(s.label, key: Key('bookState_${b.id}'), tone: _tone(s)),
                          ],
                        ),
                        Text('${b.entries.length} price${b.entries.length == 1 ? '' : 's'}${window.isEmpty ? ' · No dates' : ' · $window'}', style: t.caption.copyWith(color: p.textSecondary)),
                        if (b.note != null) Text(b.note!, style: t.caption.copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                );
              },
            ),
        ];
      },
    ),
  );
}

class _EntryDraft {
  _EntryDraft(this.variantId, String price) : price = TextEditingController(text: price);
  final String variantId;
  final TextEditingController price;
}

typedef _PickedVariant = ({String id, String label, double price});

/// The editor: name, on / off, an optional start and end date, a note, and the prices (a variant + its price in major units).
class PriceBookEditorView extends StatefulWidget {
  const PriceBookEditorView({super.key, required this.controller, this.book});
  final PriceBooksController controller;
  final PriceBook? book;
  @override
  State<PriceBookEditorView> createState() => _PriceBookEditorViewState();
}

class _PriceBookEditorViewState extends State<PriceBookEditorView> {
  PriceBooksController get c => widget.controller;
  late final PriceBook? b = widget.book;
  late final TextEditingController _name = TextEditingController(text: b?.name ?? '');
  late final TextEditingController _note = TextEditingController(text: b?.note ?? '');
  late bool _active = b?.active ?? true;
  /// G4.8: the first and last valid STORE days ("2026-11-12"); the server turns them into the store's midnights
  late String? _fromDay = b == null ? null : _fromDayOf(b!);
  late String? _toDay = b == null ? null : _toDayOf(b!);
  late final List<_EntryDraft> _entries = [for (final e in (b?.entries ?? const <String, int>{}).entries) _EntryDraft(e.key, catMajorText(e.value, c.cur.exponent))];
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    for (final e in _entries) {
      e.price.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final cur = parseDayKey((start ? _fromDay : _toDay) ?? '');
    final now = c.now();
    final d = await showDatePicker(context: context, initialDate: cur ?? now, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 10));
    if (d == null || !mounted) return;
    // a store day: from its start / until its end, in the STORE's time zone (the server computes the instants)
    setState(() => start ? _fromDay = dayKey(d) : _toDay = dayKey(d));
  }

  Future<void> _addEntry() async {
    final picked = await CatSearchSheet.open<_PickedVariant>(
      title: 'Add a price',
      hint: 'Search products',
      search: (q) async {
        final list = await c.searchProducts(q);
        c.names.addAll(list);
        return [
          for (final p in list)
            for (final v in p.variants) (id: v.variantId, label: CatalogNames.variantLabel(p, v), price: v.price),
        ];
      },
      tile: (context, v, pick) => ListTile(
        key: Key('pickVariant_${v.id}'),
        title: Text(v.label),
        subtitle: Text('Normal price ${Money.format(v.price, currency: c.cur.currency, exponent: c.cur.exponent)}'),
        onTap: pick,
      ),
    );
    if (picked == null || !mounted) return;
    if (_entries.any((e) => e.variantId == picked.id)) return;
    setState(() => _entries.add(_EntryDraft(picked.id, '')));
  }

  Future<void> _save() async {
    final exp = c.cur.exponent;
    final errors = <String, String>{};
    final entries = <Map<String, dynamic>>[];
    for (final e in _entries) {
      final minor = catParseMajor(e.price.text, exp);
      if (minor == null) {
        errors[e.variantId] = catAmountHint(exp);
      } else {
        entries.add({'variantId': e.variantId, 'priceMinor': minor});
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;
    final note = _note.text.trim();
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'active': _active,
      'validFrom': _fromDay,
      'validTo': _toDay,
      'note': note.isEmpty ? null : note,
      'entries': entries,
    };
    final ok = await c.save(body, id: b?.id);
    if (ok && mounted) Get.back();
  }

  Widget _dateRow(String label, String? value, bool start, String shown) {
    final p = context.palette;
    return ListTile(
      key: Key(start ? 'bookStarts' : 'bookEnds'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: Text(label),
      subtitle: Text(value == null ? (start ? 'From now' : 'No end') : shown, style: context.type.caption.copyWith(color: p.textSecondary)),
      trailing: value == null
          ? TextButton(onPressed: () => _pickDate(start), child: const Text('Set'))
          : IconButton(
              key: Key(start ? 'bookStartsClear' : 'bookEndsClear'),
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => start ? _fromDay = null : _toDay = null),
            ),
      onTap: () => _pickDate(start),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: b == null ? 'New price book' : 'Edit price book',
      actions: [Obx(() => TextButton(key: const Key('bookSave'), onPressed: c.busy.value ? null : _save, child: const Text('Save')))],
      body: ListView(
        key: const Key('bookEditor'),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        children: [
          CatBanners(c: c),
          TextField(
            key: const Key('bookName'),
            controller: _name,
            decoration: catField('Name', hint: 'e.g. Wholesale'),
          ),
          SwitchListTile.adaptive(key: const Key('bookActive'), contentPadding: EdgeInsets.zero, title: const Text('Book is on'), value: _active, onChanged: (v) => setState(() => _active = v)),
          _dateRow('Starts', _fromDay, true, _fromDay == null ? '' : 'From ${_storeDay(_fromDay!)}'),
          _dateRow('Ends', _toDay, false, _toDay == null ? '' : 'Until the end of ${_storeDay(_toDay!)}'),
          TextField(key: const Key('bookNote'), controller: _note, maxLength: 300, decoration: catField('Note (optional)')),
          InvSectionTitle('Prices · ${c.cur.currency}'),
          if (_entries.isEmpty) const CatHint('No prices yet. Items not in the book sell at their normal price.'),
          Obx(
            // reads the names map even with no entry yet, so the Obx always has an observable
            () => c.names.variants.isEmpty && _entries.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      for (final e in _entries)
                        Padding(
                          key: Key('bookEntry_${e.variantId}'),
                          padding: const EdgeInsets.only(bottom: Space.s2),
                          child: AppCard(
                            radius: Radii.rMd,
                            padding: const EdgeInsets.all(Space.s3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c.names.variant(e.variantId), style: t.body.copyWith(color: p.textPrimary)),
                                      if (c.names.variants[e.variantId] != null)
                                        Text(
                                          'Normal ${Money.format(c.names.variants[e.variantId]!.price, currency: c.cur.currency, exponent: c.cur.exponent)}',
                                          style: t.caption.copyWith(color: p.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: Space.s2),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    key: Key('bookPrice_${e.variantId}'),
                                    controller: e.price,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: catField('Price', error: _errors[e.variantId]),
                                  ),
                                ),
                                IconButton(
                                  key: Key('bookEntryRemove_${e.variantId}'),
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () {
                                    setState(() => _entries.remove(e));
                                    WidgetsBinding.instance.addPostFrameCallback((_) => e.price.dispose());
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          AppButton(key: const Key('bookAddEntry'), label: 'Add a price', icon: Icons.add_rounded, variant: AppButtonVariant.secondary, onPressed: _addEntry),
          const SizedBox(height: Space.s5),
          Obx(() => AppButton(key: const Key('bookSaveBottom'), label: 'Save price book', loading: c.busy.value, onPressed: c.busy.value ? null : _save)),
        ],
      ),
    );
  }
}

/// Give a customer a price book (their sales are then priced with it while it is in force), or clear it.
class AssignPriceBookView extends StatefulWidget {
  const AssignPriceBookView({super.key, required this.controller});
  final PriceBooksController controller;
  @override
  State<AssignPriceBookView> createState() => _AssignPriceBookViewState();
}

class _AssignPriceBookViewState extends State<AssignPriceBookView> {
  PriceBooksController get c => widget.controller;
  PosCustomer? _customer;
  String? _bookId; // null = normal prices

  Future<void> _pickCustomer() async {
    final picked = await CatSearchSheet.open<PosCustomer>(
      title: 'Choose a customer',
      hint: 'Name, phone or e-mail',
      search: c.searchCustomers,
      searchOnOpen: true,
      tile: (context, x, pick) => ListTile(key: Key('pickCustomer_${x.id}'), title: Text(x.name), subtitle: x.phone == null ? null : Text(x.phone!), onTap: pick),
    );
    if (picked != null && mounted) setState(() => _customer = picked);
  }

  Future<void> _save() async {
    final cu = _customer;
    if (cu == null) return;
    final book = c.data.value?.books.firstWhereOrNull((b) => b.id == _bookId);
    await c.assign(cu, book);
  }

  @override
  Widget build(BuildContext context) {
    final books = c.data.value?.books ?? const <PriceBook>[];
    return InvScaffold(
      title: 'Assign a price book',
      body: ListView(
        key: const Key('assignList'),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        children: [
          CatBanners(c: c),
          const CatHint('The customer\'s sales are priced with their book while it is in force. Choose "Normal prices" to clear it.'),
          ListTile(
            key: const Key('assignCustomer'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(_customer?.name ?? 'Choose a customer'),
            subtitle: _customer?.phone == null ? null : Text(_customer!.phone!),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickCustomer,
          ),
          const InvSectionTitle('Price book'),
          RadioGroup<String?>(
            groupValue: _bookId,
            onChanged: (v) => setState(() => _bookId = v),
            child: Column(
              children: [
                const RadioListTile<String?>(key: Key('assignNone'), contentPadding: EdgeInsets.zero, value: null, title: Text('Normal prices (no book)')),
                for (final b in books)
                  RadioListTile<String?>(key: Key('assignBook_${b.id}'), contentPadding: EdgeInsets.zero, value: b.id, title: Text(b.name), subtitle: Text(BookState.of(b, c.now()).label)),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          Obx(
            () => AppButton(
              key: const Key('assignSave'),
              label: _bookId == null ? 'Clear the customer\'s book' : 'Assign',
              loading: c.busy.value,
              onPressed: _customer == null || c.busy.value ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
