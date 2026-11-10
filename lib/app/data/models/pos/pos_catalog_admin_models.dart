/// G4.5 read models over `api/pos/catalog-admin/*`: modifier groups (sold with a product, priced by the server), price books (another price for some
/// variants; picked at checkout or assigned to a customer), categories, a created product, a CSV import report. Money is minor units with the response's
/// own currency + exponent.
library;

int _int(dynamic v) => v is num ? v.toInt() : 0;
String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// The currency every money figure of a response is in.
class CatCur {
  const CatCur(this.currency, this.exponent);
  final String currency;
  final int exponent;
  factory CatCur.fromJson(Map<String, dynamic> j) => CatCur('${j['currency'] ?? 'USD'}'.toUpperCase(), j['currencyExponent'] is num ? (j['currencyExponent'] as num).toInt() : 2);
}

// ── modifiers ───────────────────────────────────────────────────────────────
class ModifierOption {
  const ModifierOption({required this.id, required this.name, this.priceDeltaMinor = 0, this.active = true});
  final String id, name;
  final int priceDeltaMinor;
  final bool active;
  factory ModifierOption.fromJson(Map<String, dynamic> j) => ModifierOption(id: '${j['id'] ?? ''}', name: '${j['name'] ?? ''}', priceDeltaMinor: _int(j['priceDeltaMinor']), active: j['active'] != false);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'priceDeltaMinor': priceDeltaMinor, 'active': active};
}

class ModifierGroup {
  const ModifierGroup({required this.id, required this.name, this.minSelect = 0, this.maxSelect = 1, this.productIds = const [], this.options = const [], this.active = true, this.sortOrder = 0});
  final String id, name;
  final int minSelect, maxSelect, sortOrder;
  final List<String> productIds;
  final List<ModifierOption> options;
  final bool active;

  bool get required => minSelect > 0;
  bool get single => maxSelect == 1;
  List<ModifierOption> get activeOptions => options.where((o) => o.active).toList();

  /// "Choose 1" / "Optional, up to 2" / "Choose 2–3"
  String get rule => minSelect == 0
      ? (maxSelect == 1 ? 'Optional' : 'Optional, up to $maxSelect')
      : (minSelect == maxSelect ? 'Choose $minSelect' : 'Choose $minSelect–$maxSelect');

  factory ModifierGroup.fromJson(Map<String, dynamic> j) => ModifierGroup(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    minSelect: _int(j['minSelect']),
    maxSelect: j['maxSelect'] is num ? (j['maxSelect'] as num).toInt() : 1,
    productIds: j['productIds'] is List ? [for (final p in j['productIds'] as List) '$p'] : const [],
    options: [for (final o in _maps(j['options'])) ModifierOption.fromJson(o)],
    active: j['active'] != false,
    sortOrder: _int(j['sortOrder']),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'productIds': productIds,
    'options': [for (final o in options) o.toJson()],
    'active': active,
    'sortOrder': sortOrder,
  };

  /// The write body (the server assigns ids to new options; existing ones keep theirs).
  Map<String, dynamic> toWrite() => {
    'name': name,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'productIds': productIds,
    'active': active,
    'options': [
      for (final o in options) {if (o.id.isNotEmpty) 'id': o.id, 'name': o.name, 'priceDeltaMinor': o.priceDeltaMinor, 'active': o.active},
    ],
  };
}

class ModifierGroups {
  const ModifierGroups(this.cur, this.groups);
  final CatCur cur;
  final List<ModifierGroup> groups;
  factory ModifierGroups.fromJson(Map<String, dynamic> j) => ModifierGroups(CatCur.fromJson(j), [for (final g in _maps(j['groups'])) ModifierGroup.fromJson(g)]);
  Map<String, dynamic> toJson() => {'currency': cur.currency, 'currencyExponent': cur.exponent, 'groups': [for (final g in groups) g.toJson()]};

  /// the active groups a product is sold with, in the store's order
  List<ModifierGroup> of(String productId) => groups.where((g) => g.active && g.productIds.contains(productId) && g.activeOptions.isNotEmpty).toList();
}

/// One option the cashier chose for a cart line (names kept for the cart, the offline receipt and a held sale).
class ChosenModifier {
  const ChosenModifier({required this.groupId, required this.groupName, required this.optionId, required this.name, required this.priceDeltaMinor});
  final String groupId, groupName, optionId, name;
  final int priceDeltaMinor;

  factory ChosenModifier.fromJson(Map<String, dynamic> j) => ChosenModifier(
    groupId: '${j['groupId'] ?? ''}',
    groupName: '${j['groupName'] ?? ''}',
    optionId: '${j['optionId'] ?? ''}',
    name: '${j['name'] ?? ''}',
    priceDeltaMinor: _int(j['priceDeltaMinor']),
  );
  Map<String, dynamic> toJson() => {'groupId': groupId, 'groupName': groupName, 'optionId': optionId, 'name': name, 'priceDeltaMinor': priceDeltaMinor};

  /// what the sale / quote request sends: `[{groupId, optionIds}]` (the server prices)
  static List<Map<String, dynamic>> toRequest(List<ChosenModifier> mods) {
    final by = <String, List<String>>{};
    for (final m in mods) {
      (by[m.groupId] ??= []).add(m.optionId);
    }
    return [for (final e in by.entries) {'groupId': e.key, 'optionIds': e.value}];
  }

  /// " (Large, Extra shot)" — the same suffix the server puts on the line name
  static String suffix(List<ChosenModifier> mods) => mods.isEmpty ? '' : ' (${mods.map((m) => m.name).join(', ')})';

  /// a stable key so two lines with different choices stay apart in the cart
  static String key(List<ChosenModifier> mods) => ([for (final m in mods) m.optionId]..sort()).join('+');
}

// ── price books ─────────────────────────────────────────────────────────────
class PriceBook {
  const PriceBook({required this.id, required this.name, this.active = true, this.startsAt, this.endsAt, this.note, this.entries = const {}, this.inForce = true});
  final String id, name;
  final bool active, inForce;
  final DateTime? startsAt, endsAt;
  final String? note;

  /// variantId → price in minor units
  final Map<String, int> entries;

  factory PriceBook.fromJson(Map<String, dynamic> j) => PriceBook(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    active: j['active'] != false,
    startsAt: _date(j['startsAt']),
    endsAt: _date(j['endsAt']),
    note: _str(j['note']),
    entries: {for (final e in _maps(j['entries'])) '${e['variantId']}': _int(e['priceMinor'])},
    inForce: j['inForce'] is bool ? j['inForce'] as bool : j['active'] != false,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'active': active,
    'startsAt': startsAt?.toUtc().toIso8601String(),
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'note': note,
    'entries': [
      for (final e in entries.entries) {'variantId': e.key, 'priceMinor': e.value},
    ],
    'inForce': inForce,
  };

  /// in force at [at] by its own window (the server decides at the sale; this is for the picker)
  bool inForceAt(DateTime at) => active && (startsAt == null || !startsAt!.isAfter(at)) && (endsAt == null || endsAt!.isAfter(at));
}

class PriceBooks {
  const PriceBooks(this.cur, this.books);
  final CatCur cur;
  final List<PriceBook> books;
  factory PriceBooks.fromJson(Map<String, dynamic> j) => PriceBooks(CatCur.fromJson(j), [for (final b in _maps(j['books'])) PriceBook.fromJson(b)]);
  Map<String, dynamic> toJson() => {'currency': cur.currency, 'currencyExponent': cur.exponent, 'books': [for (final b in books) b.toJson()]};
}

// ── categories, products, import ────────────────────────────────────────────
class CatalogCategory {
  const CatalogCategory({required this.id, required this.name, this.parentId, this.sortOrder = 0, this.products = 0, this.status = 'active'});
  final String id, name, status;
  final String? parentId;
  final int sortOrder, products;
  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
    id: '${j['id'] ?? ''}',
    name: '${j['name'] ?? ''}',
    parentId: _str(j['parentId']),
    sortOrder: _int(j['sortOrder']),
    products: _int(j['products']),
    status: '${j['status'] ?? 'active'}',
  );
  static List<CatalogCategory> listFrom(Map<String, dynamic> j) => [for (final c in _maps(j['categories'])) CatalogCategory.fromJson(c)];
}

class CatalogVariant {
  const CatalogVariant({required this.id, required this.sku, this.barcode, this.options = const [], required this.priceMinor, this.costMinor, this.stock = 0, this.unlimitedStock = false, this.trackLots = false, this.status = 'active'});
  final String id, sku, status;
  final String? barcode;
  final List<({String name, String value})> options;
  final int priceMinor, stock;
  final int? costMinor;
  final bool unlimitedStock, trackLots;
  String get label => options.isEmpty ? sku : options.map((o) => o.value).join(' / ');
  factory CatalogVariant.fromJson(Map<String, dynamic> j) => CatalogVariant(
    id: '${j['id'] ?? ''}',
    sku: '${j['sku'] ?? ''}',
    barcode: _str(j['barcode']),
    options: [for (final o in _maps(j['options'])) (name: '${o['name'] ?? ''}', value: '${o['value'] ?? ''}')],
    priceMinor: _int(j['priceMinor']),
    costMinor: j['costMinor'] is num ? (j['costMinor'] as num).toInt() : null,
    stock: _int(j['stock']),
    unlimitedStock: j['unlimitedStock'] == true,
    trackLots: j['trackLots'] == true,
    status: '${j['status'] ?? 'active'}',
  );
}

class CatalogProduct {
  const CatalogProduct({required this.cur, required this.id, required this.name, this.categoryId, this.status, this.variants = const []});
  final CatCur cur;
  final String id, name;
  final String? categoryId, status;
  final List<CatalogVariant> variants;
  factory CatalogProduct.fromJson(Map<String, dynamic> j) {
    final p = j['product'] is Map ? (j['product'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    return CatalogProduct(
      cur: CatCur.fromJson(j),
      id: '${p['id'] ?? ''}',
      name: '${p['name'] ?? ''}',
      categoryId: _str(p['categoryId']),
      status: _str(p['status']),
      variants: [for (final v in _maps(p['variants'])) CatalogVariant.fromJson(v)],
    );
  }
}

/// The dashboard importer's report, read loosely (it counts created / updated / refused rows and lists the refusals).
class ImportReport {
  const ImportReport({this.created = 0, this.updated = 0, this.failed = 0, this.errors = const []});
  final int created, updated, failed;
  final List<String> errors;
  factory ImportReport.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] is Map ? (j['summary'] as Map).cast<String, dynamic>() : j;
    final errs = j['errors'] ?? j['failedRows'] ?? s['errors'];
    return ImportReport(
      created: _int(s['created'] ?? s['inserted']),
      updated: _int(s['updated']),
      failed: _int(s['failed'] ?? s['skipped'] ?? (errs is List ? errs.length : 0)),
      errors: errs is List
          ? [
              for (final e in errs.take(50))
                if (e is Map) '${e['row'] != null ? 'Row ${e['row']}: ' : ''}${e['message'] ?? e['error'] ?? e['reason'] ?? e}' else '$e',
            ]
          : const [],
    );
  }
}

String catalogErrorMessage(String? code, {String? message}) => switch (code) {
  'PRICE_BOOK_NOT_ACTIVE' => 'That price book is not available now. Choose another or sell at the normal prices.',
  'MODIFIER_REQUIRED' || 'MODIFIER_TOO_MANY' || 'MODIFIER_OPTION_UNKNOWN' || 'MODIFIER_NOT_ON_PRODUCT' || 'MODIFIER_GROUP_TWICE' => message ?? 'Check the options chosen for this item.',
  'PRICE_BELOW_ZERO' => 'The options make the price negative.',
  'NAME_REQUIRED' => message ?? 'A name is needed.',
  'VARIANTS_REQUIRED' => 'Add at least one variant with a price.',
  'INVALID_AMOUNT' => message ?? 'Enter a valid amount.',
  'INVALID_GROUP' || 'OPTIONS_REQUIRED' => message ?? 'Check the group\'s options and how many can be chosen.',
  'INVALID_DATE' => message ?? 'Check the dates.',
  'DUPLICATE_ENTRY' => 'A variant appears twice in the price book.',
  'VARIANT_NOT_FOUND' => 'A variant was not found in this store.',
  'SKU_TAKEN' => message ?? 'That SKU is already used.',
  'BARCODE_TAKEN' => 'That barcode is already on another product.',
  'VARIANT_EXISTS' => 'A variant with these attributes already exists.',
  'OPTIONS_MISMATCH' => message ?? 'Use the same attributes as the other variants.',
  'LAST_VARIANT' => 'A product needs at least one active variant.',
  'CATEGORY_IN_USE' => message ?? 'That category still has products.',
  'CSV_REQUIRED' => 'Paste or attach the CSV text.',
  'CSV_TOO_LARGE' => 'The file is too large (2 MB at most).',
  'POS_ACTION_FORBIDDEN' => 'Your role cannot do this. Ask a manager.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => message ?? 'Something went wrong. Please try again.',
};
