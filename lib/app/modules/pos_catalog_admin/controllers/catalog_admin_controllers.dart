import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

// ── modifier groups ─────────────────────────────────────────────────────────
/// G4.5 modifier groups ("Size", "Extras"): every group, inactive ones too, and the editor's save (create when the id is empty, else update).
class ModifierGroupsController extends CatalogAdminController {
  ModifierGroupsController({super.repository, super.storeId});

  final Rxn<ModifierGroups> data = Rxn<ModifierGroups>();
  final CatalogNames names = CatalogNames();

  CatCur get cur => data.value?.cur ?? const CatCur('USD', 2);

  @override
  bool get hasData => data.value != null;
  @override
  String get loadFailure => 'Could not load the modifier groups.';

  @override
  Future<bool> fetch(String storeId) async {
    final g = await repo.getModifierGroups(storeId, all: true);
    if (g == null) return false;
    data.value = g;
    if (g.groups.any((x) => x.productIds.isNotEmpty)) await names.load(repo, storeId);
    return true;
  }

  Future<bool> save(ModifierGroup g) async {
    final r = await write('Saving a modifier group needs an internet connection.', (sid) => repo.saveModifierGroup(sid, g), done: 'Saved "${g.name.trim()}".');
    final saved = r.data;
    if (!r.ok || saved == null) return false;
    final cur = data.value;
    if (cur != null) {
      final list = [...cur.groups];
      final i = list.indexWhere((x) => x.id == saved.id);
      if (i >= 0) {
        list[i] = saved;
      } else {
        list.add(saved);
      }
      data.value = ModifierGroups(cur.cur, list);
    }
    return true;
  }
}

// ── price books ─────────────────────────────────────────────────────────────
/// G4.5 price books: the list (in force / scheduled / ended / off), the editor's save, and giving a customer a book (or clearing it).
class PriceBooksController extends CatalogAdminController {
  PriceBooksController({super.repository, super.storeId, DateTime Function()? clock}) : now = clock ?? DateTime.now;

  final DateTime Function() now;
  final Rxn<PriceBooks> data = Rxn<PriceBooks>();
  final CatalogNames names = CatalogNames();

  CatCur get cur => data.value?.cur ?? const CatCur('USD', 2);

  @override
  bool get hasData => data.value != null;
  @override
  String get loadFailure => 'Could not load the price books.';

  @override
  Future<bool> fetch(String storeId) async {
    final b = await repo.getPriceBooks(storeId);
    if (b == null) return false;
    data.value = b;
    if (b.books.any((x) => x.entries.isNotEmpty)) await names.load(repo, storeId);
    return true;
  }

  /// [body] = name, active, startsAt, endsAt, note, entries [{variantId, priceMinor}].
  Future<bool> save(Map<String, dynamic> body, {String? id}) async {
    final r = await write('Saving a price book needs an internet connection.', (sid) => repo.savePriceBook(sid, body, id: id), done: 'Saved "${body['name']}".');
    if (!r.ok) return false;
    // the server's view says whether it is in force now: read the list again
    await load();
    return true;
  }

  Future<bool> assign(PosCustomer customer, PriceBook? book) async {
    final r = await write<String>(
      'Assigning a price book needs an internet connection.',
      (sid) => repo.assignPriceBook(sid, customer.id, book?.id),
      done: book == null ? '${customer.name} now pays the normal prices.' : '${customer.name} now gets "${book.name}".',
    );
    return r.ok;
  }

  /// The store's customer book (the ids a price book is assigned to). Null on failure.
  Future<List<PosCustomer>?> searchCustomers(String q) async {
    if (!reportsOnline()) return null;
    final page = await repo.searchPosCustomers(await storeId(), q);
    return page?.items;
  }
}

// ── categories ──────────────────────────────────────────────────────────────
class CatalogCategoriesController extends CatalogAdminController {
  CatalogCategoriesController({super.repository, super.storeId});

  final RxList<CatalogCategory> categories = <CatalogCategory>[].obs;
  final RxBool _loaded = false.obs;

  @override
  bool get hasData => _loaded.value;
  @override
  String get loadFailure => 'Could not load the categories.';

  @override
  Future<bool> fetch(String storeId) async {
    final list = await repo.getCatalogCategories(storeId);
    if (list == null) return false;
    categories.assignAll(list);
    _loaded.value = true;
    return true;
  }

  Future<bool> _apply(({bool ok, List<CatalogCategory>? data}) r) async {
    if (r.ok && r.data != null) categories.assignAll(r.data!);
    return r.ok;
  }

  Future<bool> create(String name) async =>
      _apply(await write('Adding a category needs an internet connection.', (sid) => repo.createCatalogCategory(sid, name.trim()), done: 'Added "${name.trim()}".'));

  Future<bool> rename(CatalogCategory c, String name) async =>
      _apply(await write('Renaming a category needs an internet connection.', (sid) => repo.updateCatalogCategory(sid, c.id, name: name.trim()), done: 'Renamed to "${name.trim()}".'));

  Future<bool> delete(CatalogCategory c) async =>
      _apply(await write('Deleting a category needs an internet connection.', (sid) => repo.deleteCatalogCategory(sid, c.id), done: 'Deleted "${c.name}".'));
}

// ── new product ─────────────────────────────────────────────────────────────
/// G4.5 new product: the category picker, the create, then the created product with Add variant / Archive variant.
class NewProductController extends CatalogAdminController {
  NewProductController({super.repository, super.storeId});

  final RxList<CatalogCategory> categories = <CatalogCategory>[].obs;
  final RxBool _loaded = false.obs;
  final Rxn<CatalogProduct> product = Rxn<CatalogProduct>();
  final Rxn<CatCur> storeCur = Rxn<CatCur>();

  /// The store's currency + exponent, for typing prices BEFORE the product exists: the categories read does not carry it, so it comes from
  /// the modifier-groups read (same gate); after the create, the product's own response.
  CatCur get cur => product.value?.cur ?? storeCur.value ?? const CatCur('USD', 2);

  @override
  bool get hasData => _loaded.value;
  @override
  String get loadFailure => 'Could not load the categories.';

  @override
  Future<bool> fetch(String storeId) async {
    final list = await repo.getCatalogCategories(storeId);
    if (list == null) return false;
    final money = await repo.getModifierGroups(storeId);
    if (money == null) return false;
    categories.assignAll(list);
    storeCur.value = money.cur;
    _loaded.value = true;
    return true;
  }

  String? categoryName(String? id) => id == null ? null : categories.firstWhereOrNull((c) => c.id == id)?.name;

  /// [body] = name, categoryId?, variants [{priceMinor, costMinor?, sku?, barcode?, stock?, options?, trackLots?}]
  Future<bool> create(Map<String, dynamic> body) async {
    final r = await write('Creating a product needs an internet connection.', (sid) => repo.createCatalogProduct(sid, body), done: 'Created "${body['name']}".');
    if (r.ok && r.data != null) product.value = r.data;
    return r.ok && r.data != null;
  }

  Future<bool> addVariant(Map<String, dynamic> body) async {
    final p = product.value;
    if (p == null) return false;
    final r = await write('Adding a variant needs an internet connection.', (sid) => repo.addCatalogVariant(sid, p.id, body), done: 'Variant added.');
    if (r.ok && r.data != null) product.value = r.data;
    return r.ok && r.data != null;
  }

  Future<bool> archiveVariant(CatalogVariant v) async {
    final p = product.value;
    if (p == null) return false;
    final r = await write('Archiving a variant needs an internet connection.', (sid) => repo.archiveCatalogVariant(sid, p.id, v.id), done: 'Archived ${v.label}.');
    if (r.ok && r.data != null) product.value = r.data;
    return r.ok && r.data != null;
  }

  void startOver() {
    product.value = null;
    clearMessages();
  }
}

// ── CSV import ──────────────────────────────────────────────────────────────
typedef CsvFilePicker = Future<({String name, String text})?> Function();

/// Reads a .csv file the user picks as text (nothing is kept; the text goes in the import body).
Future<({String name, String text})?> pickCsvFile() async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['csv'], withData: true);
  final f = r?.files.single;
  final bytes = f?.bytes;
  if (f == null || bytes == null) return null;
  return (name: f.name, text: utf8.decode(bytes, allowMalformed: true));
}

/// G4.5 CSV import of products or categories (the dashboard's importer: same columns, same report). There is nothing to read first.
class CsvImportController extends CatalogAdminController {
  CsvImportController({super.repository, super.storeId, CsvFilePicker? filePicker}) : _picker = filePicker ?? pickCsvFile;
  final CsvFilePicker _picker;

  final RxString kind = 'products'.obs;
  final RxString csv = ''.obs;
  final RxnString fileName = RxnString();
  final Rxn<ImportReport> report = Rxn<ImportReport>();

  /// bumped when a file replaces the pasted text (the text field re-reads it)
  final RxInt revision = 0.obs;

  @override
  bool get hasData => true;
  @override
  String get loadFailure => '';

  @override
  Future<bool> fetch(String storeId) async => true;

  void setKind(String k) {
    kind.value = k;
    report.value = null;
  }

  void setText(String v) {
    csv.value = v;
    fileName.value = null;
  }

  Future<void> pickFile() async {
    clearMessages();
    try {
      final f = await _picker();
      if (f == null) return;
      csv.value = f.text;
      fileName.value = f.name;
      revision.value++;
      report.value = null;
    } catch (_) {
      saveError.value = 'Could not read that file. Paste the CSV text instead.';
    }
  }

  Future<bool> submit() async {
    report.value = null;
    final r = await write('Importing needs an internet connection.', (sid) => repo.importCatalogCsv(sid, kind: kind.value, csv: csv.value));
    if (r.ok && r.data != null) report.value = r.data;
    return r.ok;
  }
}
