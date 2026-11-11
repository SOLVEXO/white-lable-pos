import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/utils/money.dart';

/// G4.5 products & pricing: what every catalog-admin controller shares. Reads load online (nothing is cached); writes are online-only and the
/// server decides every rule (managers by default, through the permission matrix) — a refusal is shown in words, never guessed beforehand.
abstract class CatalogAdminController extends GetxController {
  CatalogAdminController({PosRepository? repository, String? storeId}) : repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository repo;
  final String? _storeIdOverride;

  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString saveError = RxnString();
  final RxnString notice = RxnString();

  /// the server said this role may not make these changes (POS_ACTION_FORBIDDEN): the screen says so and stays readable
  final RxBool forbidden = false.obs;
  Worker? _online;

  Future<String> storeId() => reportsStoreId(_storeIdOverride);

  /// Whether the screen has what it shows (reactive: read inside an Obx).
  bool get hasData;

  /// Reads the screen's data; false on failure (the code is in the repository's `lastErrorCode`).
  Future<bool> fetch(String storeId);

  /// "Could not load the price books."
  String get loadFailure;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && !hasData) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final ok = await fetch(await storeId());
    if (!ok) {
      final code = repo.lastErrorCode;
      if (code == 'POS_ACTION_FORBIDDEN') forbidden.value = true;
      error.value = code == null ? '$loadFailure Try again.' : catalogErrorMessage(code, message: '$loadFailure Try again.');
    }
    loading.value = false;
  }

  void clearMessages() {
    saveError.value = null;
    notice.value = null;
  }

  /// One write: online only, one at a time, the server's refusal in words. [done] is the notice shown on success.
  Future<({bool ok, T? data})> write<T>(String needsInternet, Future<({bool success, String? code, String? message, T? data})> Function(String storeId) run, {String? done}) async {
    clearMessages();
    if (!reportsOnline()) {
      saveError.value = needsInternet;
      return (ok: false, data: null);
    }
    if (busy.value) return (ok: false, data: null);
    busy.value = true;
    try {
      final r = await run(await storeId());
      if (!r.success) {
        if (r.code == 'POS_ACTION_FORBIDDEN') forbidden.value = true;
        saveError.value = catalogErrorMessage(r.code, message: r.message);
        return (ok: false, data: null);
      }
      if (done != null) notice.value = done;
      return (ok: true, data: r.data);
    } finally {
      busy.value = false;
    }
  }

  /// The till's product search (physical products with their variants) for the pickers; empty when offline or on a blank query.
  Future<List<PosProductModel>> searchProducts(String q) async {
    final text = q.trim();
    if (text.isEmpty || !reportsOnline()) return const [];
    return repo.searchProducts(storeId: await storeId(), q: text);
  }
}

/// Names for the ids the catalog-admin reads return (modifier groups list product ids, price books list variant ids). Read best-effort from the
/// till's product list (the first few pages) and from every pick; an id it cannot name is shown by its tail.
class CatalogNames {
  final RxMap<String, String> products = <String, String>{}.obs;
  final RxMap<String, ({String label, double price})> variants = <String, ({String label, double price})>{}.obs;
  bool _started = false;

  Future<void> load(PosRepository repo, String storeId, {int pages = 3}) async {
    if (_started) return;
    _started = true;
    try {
      for (var p = 1; p <= pages; p++) {
        final page = await repo.getProducts(storeId, page: p, limit: 100);
        addAll(page.items);
        if (!page.hasMore) break;
      }
    } catch (_) {
      // names only: the ids still show
    }
  }

  void addAll(Iterable<PosProductModel> list) {
    for (final p in list) {
      products[p.productId] = p.name;
      for (final v in p.variants) {
        variants[v.variantId] = (label: variantLabel(p, v), price: v.price);
      }
    }
  }

  static String variantLabel(PosProductModel p, PosProductVariant v) => p.variants.length > 1 ? '${p.name} · ${v.label}' : p.name;

  static String _tail(String id) => id.length > 6 ? id.substring(id.length - 6) : id;
  String product(String id) => products[id] ?? 'Product …${_tail(id)}';
  String variant(String id) => variants[id]?.label ?? 'Variant …${_tail(id)}';
}

/// A typed amount in MAJOR units → minor units at the response's [exponent]. Null when it is not a number or has more decimals than the
/// currency has (an input check only; whether the amount is allowed is the server's call).
int? catParseMajor(String text, int exponent) {
  final s = text.trim().replaceAll(',', '').replaceAll(' ', '');
  final m = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(s);
  if (m == null) return null;
  final whole = m.group(2) ?? '';
  final frac = m.group(3) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (frac.length > exponent) return null;
  final v = double.tryParse('${m.group(1)}${whole.isEmpty ? '0' : whole}${frac.isEmpty ? '' : '.$frac'}');
  return v == null ? null : Money.toMinor(v, exponent);
}

/// A minor amount as the text of an amount field ("12.50"; "-1.00").
String catMajorText(int minor, int exponent) => Money.fromMinor(minor, exponent).toStringAsFixed(exponent);

String catMoney(int minor, CatCur cur) => Money.format(Money.fromMinor(minor, cur.exponent), currency: cur.currency, exponent: cur.exponent);
String catSigned(int minor, CatCur cur) => Money.signed(Money.fromMinor(minor, cur.exponent), currency: cur.currency, exponent: cur.exponent);

/// The words of a bad amount field.
String catAmountHint(int exponent) => exponent == 0 ? 'Enter a whole amount.' : 'Enter an amount with at most $exponent decimals.';

/// Where a price book stands now (the server's `inForce` decides; the rest only explains why not).
enum BookState {
  inForce('In force'),
  scheduled('Scheduled'),
  ended('Ended'),
  off('Off');

  const BookState(this.label);
  final String label;

  static BookState of(PriceBook b, DateTime now) {
    if (b.inForce) return BookState.inForce;
    if (!b.active) return BookState.off;
    if (b.scheduledAt(now)) return BookState.scheduled; // G4.8: the store's day boundaries, in UTC
    return BookState.ended;
  }
}
